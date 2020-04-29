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

fn game(igdb: igdb::Game, distribution: GameDistribution) -> Game {
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

        size_bytes: std::fs::metadata(format!(
            "/mnt/media1000/Games/{}",
            distribution.path.to_string_lossy()
        ))
        .unwrap()
        .len(),
        version: {
            match title_and_version(&distribution.path.to_string_lossy()) {
                Some((_, version)) => version,
                None => None,
            }
        },
        path: distribution.path,
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
    let mut games = config.games.clone();

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

    // Sanity check for duplicate slugs.
    let mut unique_slugs = HashSet::new();
    let mut duplicate_slugs: HashMap<String, u32> = HashMap::new();
    games.retain(|g| {
        if unique_slugs.contains(&g.slug) {
            if let Some(duplicates) = duplicate_slugs.get_mut(&g.slug) {
                *duplicates += 1;
            } else {
                duplicate_slugs.insert(g.slug.clone(), 2);
            }
            return false;
        } else {
            unique_slugs.insert(g.slug.clone());
            return true;
        }
    });
    for (slug, count) in duplicate_slugs {
        eprintln!(
            "Warning: found {} games with the same slug {:?}",
            count, slug
        );
    }

    // Sanity check for missing executables.
    let root = &config.root;
    games.retain(|g| {
        let path = PathBuf::from_iter([root, &g.path].iter());
        if !path.exists() {
            eprintln!("Warning: game path doesn't exist {:?}", path);
            return false;
        } else {
            return true;
        }
    });

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
            game(igdb_game.clone(), g)
        })
        .collect();
    games.sort_by(|a, b| a.name.cmp(&b.name));

    Some(games)
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

fn main() {
    let config: GamesConfig = {
        let text = match std::fs::read_to_string("games.toml") {
            Ok(text) => text,
            Err(_) => {
                eprintln!("Error: config file doesn't exist: \"games.toml\"");
                panic!()
            }
        };
        toml::from_str(&text).unwrap()
    };

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
        .mount("/games", StaticFiles::from("/mnt/media1000/Games"))
        .mount("/", routes![get_games, get_genres, get_themes])
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
