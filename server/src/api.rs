use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use crate::twitch;
use flate2::write::GzEncoder;
use http_types::mime;
use serde::Serialize;
use std::io;
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

    // Start the server
    let mut server = tide::with_state(model);
    server.at("/api/catalog").get(catalog);
    server.at("/api/download/:slug").get(download);
    server.at("/favicon.ico").get(favicon);
    server.at("/*").get(index);
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
