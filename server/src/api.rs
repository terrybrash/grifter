use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use crate::twitch;
use async_std::fs::{self, File};
use async_std::io;
use async_std::path::{Path, PathBuf};
use async_std::prelude::*;
use flate2::write::GzEncoder;
use http_types::mime;
use image::{imageops::FilterType, GenericImageView, ImageFormat, ImageOutputFormat};
use serde::{Deserialize, Serialize};
use std::io::Write;
use tide::{Body, Request, Response};

pub fn gzip(bytes: &[u8]) -> io::Result<Vec<u8>> {
    let mut encoder = GzEncoder::new(Vec::new(), flate2::Compression::best());
    encoder.write_all(bytes)?;
    encoder.finish()
}

#[derive(Clone)]
struct Model {
    catalog: Catalog,
    catalog_gz: Vec<u8>,
    index_gz: Vec<u8>,
}

#[derive(Clone, Serialize)]
struct Catalog {
    games: Vec<Game>,
    genres: Vec<igdb::Genre>,
    themes: Vec<igdb::Theme>,
}

pub async fn start(
    config: &Config,
    last_request: &mut std::time::Instant,
    games: Vec<Game>,
) -> std::io::Result<()> {
    let access_token = twitch::authenticate(&config.twitch_client_id, &config.twitch_client_secret)
        .unwrap()
        .access_token;

    let mut genres = igdb::get_genres(&config.twitch_client_id, &access_token, last_request)
        .await
        .unwrap();
    for genre in genres.iter_mut() {
        // The names for some of these genres are ugly/verbose. Manually fixing them here.
        match genre.id {
            25 => genre.name = "Hack and slash".to_string(),
            16 => genre.name = "Turn-based strategy".to_string(),
            11 => genre.name = "Real Time Strategy".to_string(),
            _ => {}
        }
    }
    genres.drain_filter(|genre| !games.iter().any(|game| game.genres.contains(&genre.id)));
    genres.sort_by(|a, b| a.name.cmp(&b.name));

    let mut themes = igdb::get_themes(&config.twitch_client_id, &access_token, last_request)
        .await
        .unwrap();
    themes.drain_filter(|theme| !games.iter().any(|game| game.themes.contains(&theme.id)));
    themes.sort_by(|a, b| a.name.cmp(&b.name));

    let model = {
        let catalog = Catalog {
            games,
            genres,
            themes,
        };
        let catalog_json = serde_json::to_vec(&catalog).unwrap();
        let catalog_gz = gzip(&catalog_json).unwrap();

        let index_bytes = include_bytes!(concat!(env!("OUT_DIR"), "/index.html"));
        let index_gz = gzip(index_bytes).unwrap();
        Model {
            catalog,
            catalog_gz,
            index_gz,
        }
    };

    let address = "http://0.0.0.0:8000";
    println!("{}", address);

    // Start the server
    let mut server = tide::with_state(model);
    server.at("/api/catalog").get(catalog);
    server.at("/api/download/:slug").get(download);
    server.at("/api/image/:id").get(image);
    server.at("/favicon.ico").get(favicon);
    server.at("/*").get(index);
    server.at("/").get(index);
    server.listen("0.0.0.0:8000").await
}

async fn index(r: Request<Model>) -> tide::Result<Response> {
    let response = Response::builder(200)
        .body(r.state().index_gz.as_slice())
        .header("content-encoding", "gzip")
        .content_type(mime::HTML)
        .build();
    Ok(response)
}

async fn download(r: Request<Model>) -> tide::Result<Response> {
    let slug = r.param("slug")?;
    let games = &r.state().catalog.games;
    let game = match games.iter().find(|game| game.slug == slug) {
        Some(game) => game,
        None => {
            println!("Download failed: slug doesn't exist {:?}", slug);
            return Ok(Response::new(404));
        }
    };

    let body = match Body::from_file(&game.path).await {
        Ok(file) => file,
        Err(_) => {
            println!("Download failed: file doesn't exist {:?}", game.path);
            return Ok(Response::new(404));
        }
    };

    let response = Response::builder(200).body(body).build();
    Ok(response)
}

async fn favicon(_r: Request<Model>) -> tide::Result<Response> {
    let icon = include_bytes!("../favicon.ico");
    let response = tide::Response::builder(200)
        .body(icon.as_ref())
        .content_type(mime::ICO)
        .build();
    Ok(response)
}

async fn catalog(r: Request<Model>) -> tide::Result<Response> {
    let response = Response::builder(200)
        .body(r.state().catalog_gz.as_slice())
        .header("content-encoding", "gzip")
        .content_type(mime::JSON)
        .build();
    Ok(response)
}

async fn image(r: Request<Model>) -> tide::Result<Response> {
    let image_id = r.param("id")?;

    let cache_root = Path::new("./cache");
    if let Err(e) = fs::create_dir(cache_root).await {
        match e.kind() {
            io::ErrorKind::AlreadyExists => { /* this is fine */ }
            _ => {
                let err = tide::Error::from_str(500, "failed to create cache directory");
                return Err(err);
            }
        }
    }

    let image_dir = cache_root.join(image_id);
    if let Err(e) = fs::create_dir(&image_dir).await {
        match e.kind() {
            io::ErrorKind::AlreadyExists => { /* this is fine */ }
            _ => {
                let err = tide::Error::from_str(500, "failed to create cache directory");
                return Err(err);
            }
        }
    }

    #[derive(Deserialize)]
    struct Query {
        w: Option<u32>,
        h: Option<u32>,
    }
    let query: Query = r.query()?;

    let scaled_image_name = match (query.w, query.h) {
        (Some(width), Some(height)) => Some(format!("{}x{}", width, height)),
        (Some(width), None) => Some(format!("{}x_", width)),
        (None, Some(height)) => Some(format!("_x{}", height)),
        (None, None) => None,
    };

    let image = match scaled_image_name {
        None => {
            let original_image_path = image_dir.join("original.jpeg");
            match fs::read(&original_image_path).await {
                Ok(original_image) => original_image,
                Err(_) => {
                    let original_image = get_jpeg_from_igdb(&image_id).await?;
                    let mut file = File::create(&original_image_path).await?;
                    file.write_all(original_image.as_ref()).await?;
                    original_image
                }
            }
        }
        Some(scaled_image_name) => {
            let scaled_image_path = image_dir.join(format!("{}.jpeg", scaled_image_name));
            match fs::read(&scaled_image_path).await {
                Ok(scaled_image) => scaled_image,
                Err(_) => {
                    let original_image_path = image_dir.join("original.jpeg");
                    let original_image = match fs::read(&original_image_path).await {
                        Ok(original_image) => original_image,
                        Err(_) => {
                            let original_image = get_jpeg_from_igdb(&image_id).await?;
                            let mut file = File::create(&original_image_path).await?;
                            file.write_all(original_image.as_ref()).await?;
                            original_image
                        }
                    };

                    let scaled_image =
                        match resize_image(query.w, query.h, ImageFormat::Jpeg, &original_image) {
                            Ok(image) => image,
                            Err(e) => {
                                println!("resizing failed: {:?}", e);
                                return Err(tide::Error::from_str(404, "test"));
                            }
                        };
                    let mut file = File::create(&scaled_image_path).await?;
                    file.write_all(scaled_image.as_ref()).await?;
                    scaled_image
                }
            }
        }
    };

    let response = Response::builder(200)
        .body(image)
        .header("cache-control", "max-age=31536000, immutable")
        .content_type(mime::JPEG)
        .build();
    Ok(response)
}

async fn get_jpeg_from_igdb(image_id: &str) -> tide::Result<Vec<u8>> {
    match igdb::get_image(&image_id).await {
        Ok(igdb::ImageData::Jpeg(jpeg)) => Ok(jpeg),
        Ok(igdb::ImageData::Png(png)) => {
            let mut jpeg: Vec<u8> = Vec::with_capacity(1_000_000);
            image::load_from_memory_with_format(&png, ImageFormat::Png)?
                .write_to(&mut jpeg, ImageFormat::Jpeg)?;
            Ok(jpeg)
        }
        Ok(igdb::ImageData::Webp(webp)) => {
            let mut jpeg: Vec<u8> = Vec::with_capacity(1_000_000);
            image::load_from_memory_with_format(&webp, ImageFormat::WebP)?
                .write_to(&mut jpeg, ImageFormat::Jpeg)?;
            Ok(jpeg)
        }
        Ok(igdb::ImageData::Gif(gif)) => {
            let mut jpeg: Vec<u8> = Vec::with_capacity(1_000_000);
            image::load_from_memory_with_format(&gif, ImageFormat::Gif)?
                .write_to(&mut jpeg, ImageFormat::Jpeg)?;
            Ok(jpeg)
        }
        Ok(igdb::ImageData::Unsupported(format)) => {
            println!(
                "IGDB gave me an image in a file format I don't support ({}). Report this.",
                format
            );
            return Err(tide::Error::from_str(500, "unsupported image format"));
        }
        Ok(igdb::ImageData::Unknown) => {
            println!("IGDB gave me an image without a file format.");
            return Err(tide::Error::from_str(500, "no image format"));
        }
        Err(_) => panic!(),
    }
}

fn resize_image<T: AsRef<[u8]>>(
    max_width: Option<u32>,
    max_height: Option<u32>,
    image_format: ImageFormat,
    jpeg_bytes: T,
) -> image::error::ImageResult<Vec<u8>> {
    let original_image = image::load_from_memory_with_format(jpeg_bytes.as_ref(), image_format)?;
    let (mut width, mut height) = original_image.dimensions();
    if let Some(max_width) = max_width {
        width = u32::min(width, max_width);
    }
    if let Some(max_height) = max_height {
        height = u32::min(height, max_height);
    }
    let scaled_image = original_image.thumbnail(width, height);
    let mut jpeg_bytes_scaled: Vec<u8> = Vec::new();
    scaled_image.write_to(&mut jpeg_bytes_scaled, image_format)?;
    Ok(jpeg_bytes_scaled)
}
