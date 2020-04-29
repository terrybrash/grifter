#![feature(proc_macro_hygiene)]
#![feature(decl_macro)]

use rocket::State;
use rocket::{get, routes};
use rocket_contrib::json::Json;
use rocket_contrib::serve::StaticFiles;
use rocket_cors::{AllowedOrigins, CorsOptions};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::iter::FromIterator;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use unicode_normalization::UnicodeNormalization;
mod igdb;
use rocket::response::content::Content;
use std::fs;

#[derive(Debug, Serialize, Clone)]
struct Game {
    // INFO
    pub name: String,
    pub slug: String,
    pub search_names: Vec<String>,
    pub cover: Option<String>,
    pub genres: Vec<u64>,
    pub themes: Vec<u64>,
    pub game_modes: Vec<u64>,
    pub max_players_offline: u32,
    pub max_players_online: u32,

    // DISTRIBUTION
    pub path: PathBuf,
    pub size_bytes: u64,
    pub version: Option<String>,
}

fn game(igdb: igdb::Game, distribution: GameDistribution, metadata: fs::Metadata) -> Game {
    let pc_multiplayer = match igdb.multiplayer_modes {
        Some(multiplayer_modes) => multiplayer_modes
            .into_iter()
            .find(|mode| mode.platform == Some(6) || mode.platform == None),
        None => None,
    };
    let search_names = {
        let alternative_names = igdb
            .alternative_names
            .map(|names| names.iter().map(|n| n.name.clone()).collect())
            .unwrap_or(vec![]);
        let is_alphanumeric = |c: &char| "abcdefghijklmnopqrstuvwxyz1234567890 ".contains(*c);
        std::iter::once(igdb.name.clone())
            .chain(alternative_names)
            .map(|n| {
                n.nfkd()
                    .filter(char::is_ascii)
                    .flat_map(char::to_lowercase)
                    .filter(is_alphanumeric)
                    .fold(String::new(), |mut s, c| {
                        let is_another_space = c == ' ' && s.chars().last() == Some(' ');
                        if !is_another_space {
                            s.push(c);
                        }
                        s
                    })
                    .trim()
                    .to_string()
            })
            .filter(|s| !s.is_empty())
            .collect()
    };
    Game {
        name: igdb.name,
        slug: igdb.slug,
        search_names,
        cover: igdb.cover.map(|cover| {
            format!(
                "https://images.igdb.com/igdb/image/upload/t_cover_big/{}.png",
                cover.image_id
            )
        }),
        genres: igdb.genres.unwrap_or_default(),
        themes: igdb.themes.unwrap_or_default(),
        game_modes: igdb.game_modes.unwrap_or_default(),
        max_players_offline: pc_multiplayer
            .as_ref()
            .and_then(|mode| mode.offlinemax)
            .unwrap_or(1),
        max_players_online: pc_multiplayer
            .as_ref()
            .and_then(|mode| mode.onlinemax)
            .unwrap_or(1),

        size_bytes: metadata.len(),
        version: {
            match title_and_version(&distribution.path.to_string_lossy()) {
                Some((_, version)) => version,
                None => None,
            }
        },
        path: PathBuf::from("/games").join(distribution.path),
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct GameDistribution {
    pub path: PathBuf,
    pub slug: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct GamesConfig {
    pub root: PathBuf,
    pub igdb_key: String,
    pub games: Vec<GameDistribution>,
}

fn update(config: &GamesConfig) -> Option<Vec<Game>> {
    // Sanity check for missing root directory.
    match config.root.metadata() {
        Err(_) => {
            eprintln!(
                "Error: games root directory doesn't exist: {:?}",
                config.root
            );
            return None;
        }
        Ok(metadata) => {
            if !metadata.is_dir() {
                eprintln!(
                    "Error: games root isn't a valid directory: {:?}",
                    config.root
                );
                return None;
            }
        }
    }

    let mut games = config.games.clone();
    let root = &config.root;
    games.retain(|g| {
        // Sanity check for missing executables.
        let path = PathBuf::from_iter([&config.root, &g.path].iter());
        if !path.exists() {
            eprintln!("Warning: game path doesn't exist {:?}", path);
            return false;
        } else {
            return true;
        }
    });

    let (unique_games, duplicate_games) = split_conflicting_games(&games);
    games = unique_games;
    for (slug, count) in duplicate_games {
        eprintln!(
            "Warning: found {} games with the same slug {:?}",
            count, slug
        );
    }

    let igdb_games = {
        let slugs: Vec<&str> = config.games.iter().map(|g| g.slug.as_str()).collect();
        igdb::get_games(&config.igdb_key, &slugs).unwrap()
    };

    // Sanity check for missing slugs. This would typically be caused by
    // a misspelled slug.
    games.retain(|g| {
        if igdb_games.iter().find(|i| i.slug == g.slug).is_none() {
            eprintln!("Warning: {:?} doesn't exist on IGDB", g.slug);
            return false;
        } else {
            return true;
        }
    });

    let mut games: Vec<Game> = games
        .into_iter()
        .map(|g| {
            let igdb_game = igdb_games.iter().find(|i| i.slug == g.slug).unwrap();
            let metadata = std::fs::metadata(PathBuf::from_iter([root, &g.path].iter())).unwrap();
            game(igdb_game.clone(), g, metadata)
        })
        .collect();
    games.sort_by(|a, b| a.name.cmp(&b.name));

    Some(games)
}

fn split_conflicting_games(
    games: &[GameDistribution],
) -> (Vec<GameDistribution>, Vec<(String, usize)>) {
    enum Similarity {
        Unique(GameDistribution),
        Conflicting(Vec<GameDistribution>),
    }
    let mut similarities: HashMap<&str, Similarity> = HashMap::new();
    for g in games {
        similarities
            .entry(g.slug.as_str())
            .and_modify(|game| match game {
                Similarity::Unique(unique_game) => {
                    *game = Similarity::Conflicting(vec![unique_game.clone(), g.clone()]);
                }
                Similarity::Conflicting(games) => {
                    games.push(g.clone());
                }
            })
            .or_insert(Similarity::Unique(g.clone()));
    }

    let mut unique_games = Vec::new();
    let mut conflicting_games = Vec::new();
    for (slug, similarity) in similarities.into_iter() {
        match similarity {
            Similarity::Unique(game) => {
                unique_games.push(game);
            }
            Similarity::Conflicting(games) => {
                conflicting_games.push((slug.to_owned(), games.len()));
            }
        }
    }

    (unique_games, conflicting_games)
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
fn get_index() -> Content<&'static str> {
    let index = include_str!(concat!(env!("OUT_DIR"), "/index.html"));
    Content(rocket::http::ContentType::HTML, index)
}

fn main() {
    let mut config: GamesConfig = {
        let text = match std::fs::read_to_string("games.toml") {
            Ok(text) => text,
            Err(_) => {
                eprintln!("Error: config file doesn't exist: \"games.toml\"");
                panic!()
            }
        };
        toml::from_str(&text).unwrap()
    };

    for game in config.games.iter_mut() {}

    let allowed_origins = AllowedOrigins::All;
    let cors = CorsOptions {
        allowed_origins,
        ..Default::default()
    }
    .to_cors()
    .unwrap();

    let games: Arc<Mutex<Vec<Game>>> = Arc::new(Mutex::new(vec![]));
    if let Some(new_games) = update(&config) {
        *games.lock().unwrap() = new_games;
    }
    let genres = Arc::new(Mutex::new(igdb::get_genres(&config.igdb_key).unwrap()));
    genres.lock().unwrap().sort_by(|a, b| a.name.cmp(&b.name));
    let themes = Arc::new(Mutex::new(igdb::get_themes(&config.igdb_key).unwrap()));
    themes.lock().unwrap().sort_by(|a, b| a.name.cmp(&b.name));
    rocket::ignite()
        .attach(cors)
        .manage(games.clone())
        .manage(genres.clone())
        .manage(themes.clone())
        .mount("/games", StaticFiles::from(config.root))
        .mount("/", routes![get_index, get_games, get_genres, get_themes])
        .launch();
}

// TODO: Add a check for files that exist in the games folder that aren't registered.
// fn read_games() -> std::io::Result<Vec<Game>> {
//     fs::read_dir("/mnt/media1000/Games").map(|entries| {
//         entries
//             .filter_map(Result::ok)
//             .map(game_from_dir_entry)
//             .filter_map(|g| g)
//             .collect()
//     })
// }

// fn game_from_dir_entry(entry: DirEntry) -> Option<Game> {
//     let metadata = entry.metadata().ok()?;

//     if metadata.is_dir() {
//         return None;
//     }

//     entry
//         .path()
//         .file_stem()
//         .and_then(OsStr::to_str)
//         .and_then(title_and_version)
//         .map(|(title, version)| Game {
//             title,
//             version,
//             bytes: metadata.len(),
//             path: PathBuf::from("/games").join(entry.file_name()),
//         })
// }

fn title_and_version(string: &str) -> Option<(String, Option<String>)> {
    let mut parts = string.split(|c| c == '(' || c == ')');
    let title = parts.next();
    let version = parts.next();
    match title {
        Some(title) => Some((title.trim().into(), version.map(Into::into))),
        None => None,
    }
}
