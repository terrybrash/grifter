use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use crate::twitch;
use flate2::write::GzEncoder;
use image::{GenericImageView, ImageFormat};
use rouille::{router, Request, Response};
use serde::Serialize;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

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

pub fn start(
    config: &Config,
    last_request: &mut std::time::Instant,
    games: Vec<Game>,
) -> std::io::Result<()> {
    let access_token = twitch::authenticate(&config.twitch_client_id, &config.twitch_client_secret)
        .unwrap()
        .access_token;

    let mut genres =
        igdb::get_genres(&config.twitch_client_id, &access_token, last_request).unwrap();
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

    let mut themes =
        igdb::get_themes(&config.twitch_client_id, &access_token, last_request).unwrap();
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

    println!("Grifter started on {}:{}", config.address, config.port);
    rouille::start_server_with_pool((config.address.as_str(), config.port), None, move |request| {
        router!(request,
            (GET) ["/api/catalog"] => {catalog(&model, request)},
            (GET) ["/api/download/{slug}", slug: String] => {download(&model, request, &slug)},
            (GET) ["/api/image/{id}", id: String] => {image(&model, request, &id)},
            (GET) ["/favicon.ico"] => {favicon()},
            (GET) ["/"] => {index(&model, request)},
            _ => index(&model, request),
        )
    });
}

fn index(model: &Model, _: &Request) -> Response {
    Response::from_data("text/html", model.index_gz.clone())
        .with_unique_header("content-encoding", "gzip")
}

fn download(model: &Model, _: &Request, slug: &str) -> Response {
    let game = match model.catalog.games.iter().find(|game| game.slug == slug) {
        Some(game) => game,
        None => {
            println!("Download failed: slug doesn't exist {:?}", slug);
            return Response::empty_404();
        }
    };

    let file = match File::open(&game.path) {
        Ok(file) => file,
        Err(_) => {
            println!("Download failed: file doesn't exist {:?}", game.path);
            return Response::empty_404();
        }
    };

    let save_as = game
        .path
        .file_name()
        .and_then(|f| f.to_str())
        .unwrap_or(slug);
    Response::from_file("application/octet-stream", file).with_unique_header(
        "content-disposition",
        format!("attachment; filename=\"{}\"", save_as),
    )
}

fn favicon() -> Response {
    let icon = include_bytes!("../favicon.ico");
    Response::from_data("image/x-icon", &icon[..])
}

fn catalog(model: &Model, _: &Request) -> Response {
    Response::from_data("application/json", model.catalog_gz.clone())
        .with_unique_header("content-encoding", "gzip")
}

enum ImageSize {
    Thumbnail,
    Original,
}

fn image(_: &Model, request: &Request, image_id: &str) -> Response {
    let size = match request.get_param("size").as_deref() {
        Some("Thumbnail") => ImageSize::Thumbnail,
        Some("Original") => ImageSize::Original,
        _ => return Response::empty_404(),
    };

    match get_jpeg_from_cache_or_igdb(image_id, size) {
        Ok(image) => Response::from_data("image/jpeg", image)
            .with_unique_header("cache-control", "max-age=10368000, immutable"), // 10368000 seconds = 120 days
        Err(_) => Response::empty_404(),
    }
}

fn image_cache(image_id: &str) -> PathBuf {
    let cache_root = Path::new("./cache");
    if let Err(e) = fs::create_dir(cache_root) {
        match e.kind() {
            io::ErrorKind::AlreadyExists => { /* this is fine */ }
            _ => panic!("failed to create cache directory"),
        }
    }
    let image_dir = cache_root.join(image_id);
    if let Err(e) = fs::create_dir(&image_dir) {
        match e.kind() {
            io::ErrorKind::AlreadyExists => { /* this is fine */ }
            _ => panic!("failed to create cache directory"),
        }
    }

    image_dir
}

fn get_jpeg_from_cache_or_igdb(image_id: &str, size: ImageSize) -> Result<Vec<u8>, std::io::Error> {
    let image_dir = image_cache(image_id);
    match size {
        ImageSize::Original => {
            let original_image_path = image_dir.join("original.jpeg");
            match fs::read(&original_image_path) {
                Ok(original_image) => Ok(original_image),
                Err(_) => {
                    let original_image = igdb::get_image(image_id).unwrap();
                    let jpeg = original_image.into_jpeg().unwrap();
                    let mut file = File::create(&original_image_path)?;
                    file.write_all(jpeg.as_ref())?;
                    Ok(jpeg)
                }
            }
        }
        ImageSize::Thumbnail => {
            let scaled_image_path = image_dir.join("thumbnail.jpeg");
            match fs::read(&scaled_image_path) {
                Ok(scaled_image) => Ok(scaled_image),
                Err(_) => {
                    let original_image =
                        get_jpeg_from_cache_or_igdb(image_id, ImageSize::Original)?;
                    let scaled_image =
                        match resize_image(None, Some(400), ImageFormat::Jpeg, &original_image) {
                            Ok(image) => image,
                            Err(e) => panic!("resizing failed: {:?}", e), // FIXME: Unexpected EOF, failed to fill whole buffer
                        };
                    let mut file = File::create(&scaled_image_path)?;
                    file.write_all(scaled_image.as_ref())?;
                    Ok(scaled_image)
                }
            }
        }
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
