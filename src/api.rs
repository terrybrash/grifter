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
use std::io;
use std::io::Write;

pub fn gzip(mut bytes: Vec<u8>) -> io::Result<Vec<u8>> {
    let mut encoder = GzEncoder::new(Vec::new(), flate2::Compression::best());
    encoder.write_all(&mut bytes)?;
    encoder.finish()
}

struct Model {
    games: Vec<u8>,
    genres: Vec<u8>,
    themes: Vec<u8>,
    index: Vec<u8>,
}

pub fn start(config: &Config, games: Vec<Game>) {
    let allowed_origins = AllowedOrigins::All;
    let cors = CorsOptions {
        allowed_origins,
        ..Default::default()
    }
    .to_cors()
    .unwrap();

    let games = gzip(serde_json::to_vec(&games).unwrap()).unwrap();

    let mut genres = igdb::get_genres(&config.igdb_key).unwrap();
    genres.sort_by(|a, b| a.name.cmp(&b.name));
    let genres = gzip(serde_json::to_vec(&genres).unwrap()).unwrap();

    let mut themes = igdb::get_themes(&config.igdb_key).unwrap();
    themes.sort_by(|a, b| a.name.cmp(&b.name));
    let themes = gzip(serde_json::to_vec(&themes).unwrap()).unwrap();

    let model = Model {
        games,
        genres,
        themes,
        index: gzip(include_bytes!(concat!(env!("OUT_DIR"), "/index.html"))[..].into()).unwrap(),
    };

    rocket::ignite()
        .attach(cors)
        .manage(model)
        .mount("/games", StaticFiles::from(&config.root))
        .mount("/", routes![get_index, get_games, get_genres, get_themes])
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

#[get("/themes")]
fn get_themes(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(ContentType::JSON, Encoding::Gzip, model.themes.clone())
}

#[get("/genres")]
fn get_genres(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(ContentType::JSON, Encoding::Gzip, model.genres.clone())
}

#[get("/games")]
fn get_games(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(ContentType::JSON, Encoding::Gzip, model.games.clone())
}

#[get("/")]
fn get_index(model: State<Model>) -> EncodedContent<Vec<u8>> {
    EncodedContent(ContentType::HTML, Encoding::Gzip, model.index.clone())
}
