use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::OsString;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub enum Warning {
    ConflictingGames(Vec<Game>),
    MissingExe(Game),
    UnusedExe(OsString),
}

impl fmt::Display for Warning {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Warning::ConflictingGames(games) => write!(
                f,
                "{} games with conflicting slug {:?}",
                games.len(),
                games[0]
            ),
            Warning::MissingExe(game) => write!(f, "game path {:?} doesn't exist", game.path),
            Warning::UnusedExe(path) => write!(f, "{:?} exists in root dir but isn't used", path),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Game {
    pub path: PathBuf,
    pub slug: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub root: PathBuf,
    pub igdb_key: String,
    pub games: Vec<Game>,
}

impl Config {
    pub fn from_file<P>(path: P) -> Result<(Self, Vec<Warning>), Box<dyn std::error::Error>>
    where
        P: AsRef<Path>,
    {
        let text = fs::read_to_string(&path).unwrap_or_else(|_| panic!("Read {:?}", path.as_ref()));
        let mut config: Config =
            toml::from_str(&text).unwrap_or_else(|_| panic!("Parse {:?}", path.as_ref()));

        // Check for executables that exist but aren't listed in the config file.
        let unused_executables = fs::read_dir(&config.root)
            .unwrap_or_else(|_| panic!("Expected root to be a valid directory."))
            .filter_map(|dir_entry| match dir_entry.map(|entry| entry.file_name()) {
                Ok(file_name) => {
                    if !config.games.iter().any(|game| game.path == file_name) {
                        Some(file_name)
                    } else {
                        None
                    }
                }
                Err(_) => panic!(),
            })
            .map(Warning::UnusedExe)
            .collect();

        // Check for missing executables.
        let root = &mut config.root;
        let missing_games = config
            .games
            .drain_filter(|g| !root.join(&g.path).exists())
            .map(Warning::MissingExe)
            .collect::<Vec<_>>();

        // Check for duplicate game entries.
        let conflicting_games = drain_duplicates(&mut config.games)
            .into_iter()
            .map(Warning::ConflictingGames)
            .collect();

        let warnings = [unused_executables, conflicting_games, missing_games].concat();
        Ok((config, warnings))
    }
}

fn drain_duplicates(games: &mut Vec<Game>) -> Vec<Vec<Game>> {
    let mut slugs_by_count: HashMap<String, usize> = HashMap::new();
    for g in games.iter() {
        slugs_by_count
            .entry(g.slug.clone())
            .and_modify(|c| *c += 1)
            .or_insert(1);
    }

    let conflicting_slugs =
        slugs_by_count
            .into_iter()
            .filter_map(|(slug, count)| if count > 1 { Some(slug) } else { None });

    conflicting_slugs
        .map(|slug| {
            games
                .drain_filter(|game| slug == game.slug.as_str())
                .collect()
        })
        .collect()
}
