use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use flate2::write::GzEncoder;
use rocket::http::hyper::header::ContentEncoding;
use rocket::http::hyper::header::Encoding;
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
    let allowed_origins = AllowedOrigins::All;
    let cors = CorsOptions {
        allowed_origins,
        ..Default::default()
    }
    .to_cors()
    .unwrap();

    let mut genres = igdb::get_genres(&config.igdb_key).unwrap();
    genres.drain_filter(|genre| !games.iter().any(|game| game.genres.contains(&genre.id)));
    genres.sort_by(|a, b| a.name.cmp(&b.name));

    let mut themes = igdb::get_themes(&config.igdb_key).unwrap();
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
        .mount("/games", StaticFiles::from(&config.root))
        .mount("/", routes![get_index, get_catalog])
        .launch();
}

struct EncodedContent<R>(pub ContentType, pub Encoding, pub R);
impl<'r, R: Responder<'r>> Responder<'r> for EncodedContent<R> {
    fn respond_to(self, req: &rocket::Request) -> Result<Response<'r>, Status> {
        let EncodedContent(content_type, encoding, responder) = self;
        Response::build()
            .merge(responder.respond_to(req)?)
            .header(ContentEncoding(vec![encoding]))
            .header(content_type)
            .status(Status::Accepted)
            .ok()
    }
}

#[get("/catalog")]
fn get_catalog(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(ContentType::JSON, Encoding::Gzip, model.catalog.clone())
}

#[get("/")]
fn get_index(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(ContentType::HTML, Encoding::Gzip, model.index.clone())
}
