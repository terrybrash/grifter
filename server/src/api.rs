use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use crate::twitch;
use flate2::write::GzEncoder;
use rocket::http::hyper::header::{CacheControl, CacheDirective, ContentEncoding, Encoding};
use rocket::http::ContentType;
use rocket::http::Status;
use rocket::response::Responder;
use rocket::response::Response;
use rocket::State;
use rocket::{get, routes};
use rocket_contrib::serve::StaticFiles;
use rocket_cors::{AllowedOrigins, CorsOptions};
use serde::Serialize;
use std::io;
use std::io::Write;
use std::path::PathBuf;

pub fn gzip(bytes: Vec<u8>) -> io::Result<Vec<u8>> {
    let mut encoder = GzEncoder::new(Vec::new(), flate2::Compression::best());
    encoder.write_all(&bytes)?;
    encoder.finish()
}

struct Model {
    catalog: Vec<u8>,
    index: Vec<u8>,
}

#[derive(Clone, Serialize)]
struct Catalog {
    games: Vec<Game>,
    genres: Vec<igdb::Genre>,
    themes: Vec<igdb::Theme>,
}

pub fn start(config: &Config, games: Vec<Game>) {
    let cors_options = CorsOptions {
        allowed_origins: AllowedOrigins::All,
        ..Default::default()
    };
    let cors = cors_options.to_cors().unwrap();

    let access_token = twitch::authenticate(&config.client_id, &config.client_secret)
        .unwrap()
        .access_token;

    let mut genres = igdb::get_genres(&config.client_id, &access_token).unwrap();
    genres.drain_filter(|genre| !games.iter().any(|game| game.genres.contains(&genre.id)));
    genres.sort_by(|a, b| a.name.cmp(&b.name));

    let mut themes = igdb::get_themes(&config.client_id, &access_token).unwrap();
    themes.drain_filter(|theme| !games.iter().any(|game| game.themes.contains(&theme.id)));
    themes.sort_by(|a, b| a.name.cmp(&b.name));

    let catalog = Catalog {
        games,
        genres,
        themes,
    };

    let model = Model {
        catalog: gzip(serde_json::to_vec(&catalog).unwrap()).unwrap(),
        index: gzip(include_bytes!(concat!(env!("OUT_DIR"), "/index.html"))[..].into()).unwrap(),
    };

    rocket::ignite()
        .attach(cors)
        .manage(model)
        .mount("/", routes![get_index, get_anything, get_catalog])
        .mount("/api/download", StaticFiles::from(&config.root).rank(-2))
        .launch();
}

struct EncodedContent<R>(pub ContentType, pub Encoding, pub CacheControl, pub R);
impl<'r, R: Responder<'r>> Responder<'r> for EncodedContent<R> {
    fn respond_to(self, req: &rocket::Request) -> Result<Response<'r>, Status> {
        let EncodedContent(content_type, encoding, cache_control, responder) = self;
        Response::build()
            .merge(responder.respond_to(req)?)
            .header(ContentEncoding(vec![encoding]))
            .header(content_type)
            .header(cache_control)
            .status(Status::Accepted)
            .ok()
    }
}

#[get("/")]
fn get_index(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(
        ContentType::HTML,
        Encoding::Gzip,
        CacheControl(vec![CacheDirective::MaxAge(60 * 2)]),
        model.index.clone(),
    )
}

#[get("/<_path..>")]
fn get_anything(_path: PathBuf, model: State<Model>) -> EncodedContent<Vec<u8>> {
    get_index(model)
}

#[get("/api/catalog")]
fn get_catalog(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(
        ContentType::JSON,
        Encoding::Gzip,
        CacheControl(vec![CacheDirective::MaxAge(60 * 60)]),
        model.catalog.clone(),
    )
}
