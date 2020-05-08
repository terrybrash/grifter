use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use rocket::http::ContentType;
use rocket::response::Response;
use rocket::State;
use rocket::{get, routes};
use rocket_contrib::json::Json;
use rocket_contrib::serve::StaticFiles;
use rocket_cors::{AllowedOrigins, CorsOptions};
use std::sync::{Arc, Mutex};

pub fn start(config: &Config, games: Vec<Game>) {
    let allowed_origins = AllowedOrigins::All;
    let cors = CorsOptions {
        allowed_origins,
        ..Default::default()
    }
    .to_cors()
    .unwrap();

    let games = Arc::new(Mutex::new(games));
    let genres = Arc::new(Mutex::new(igdb::get_genres(&config.igdb_key).unwrap()));
    genres.lock().unwrap().sort_by(|a, b| a.name.cmp(&b.name));
    let themes = Arc::new(Mutex::new(igdb::get_themes(&config.igdb_key).unwrap()));
    themes.lock().unwrap().sort_by(|a, b| a.name.cmp(&b.name));
    rocket::ignite()
        .attach(cors)
        .manage(games)
        .manage(genres)
        .manage(themes)
        .mount("/games", StaticFiles::from(&config.root))
        .mount("/", routes![get_index, get_games, get_genres, get_themes])
        .launch();
}

#[get("/themes")]
fn get_themes(themes: State<Arc<Mutex<Vec<igdb::Theme>>>>) -> Json<Vec<igdb::Theme>> {
    Json((*themes.lock().unwrap()).clone())
}

#[get("/genres")]
fn get_genres(genres: State<Arc<Mutex<Vec<igdb::Genre>>>>) -> Json<Vec<igdb::Genre>> {
    Json((*genres.lock().unwrap()).clone())
}

#[get("/games")]
fn get_games(games: State<Arc<Mutex<Vec<Game>>>>) -> Json<Vec<Game>> {
    Json((*games.lock().unwrap()).clone())
}

#[get("/")]
fn get_index() -> Response<'static> {
    let index = include_bytes!(concat!(env!("OUT_DIR"), "/index.html.br"));
    Response::build()
        .header(ContentType::HTML)
        .raw_header("Content-Encoding", "br")
        .streamed_body(&index[..])
        .finalize()
}
