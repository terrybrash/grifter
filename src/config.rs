use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone)]
pub enum Problem {
    ConflictingGames(Vec<Game>),
    MissingExe(Game),
    UnusedExe(PathBuf),
}

impl fmt::Display for Problem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Problem::ConflictingGames(games) => write!(
                f,
                "{} games with conflicting slug {:?}",
                games.len(),
                games[0]
            ),
            Problem::MissingExe(game) => write!(f, "game path {:?} doesn't exist", game.path),
            Problem::UnusedExe(path) => write!(f, "{:?} exists in root dir but isn't used", path),
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
    pub fn from_file<P>(path: P) -> Result<(Self, Vec<Problem>), Box<dyn std::error::Error>>
    where
        P: AsRef<Path>,
    {
        let text = fs::read_to_string(&path).expect(&format!("Read {:?}", path.as_ref()));
        let mut config: Config =
            toml::from_str(&text).expect(&format!("Parse {:?}", path.as_ref()));

        // Check for missing or unusable root directory.
        if !config.root.metadata()?.is_dir() {
            return Err("Root is expected to be a directory".into());
        }

        // Check for missing executables.
        let root = &mut config.root;
        let missing_games = config
            .games
            .drain_filter(|g| !root.join(&g.path).exists())
            .map(Problem::MissingExe)
            .collect::<Vec<_>>();

        // Check for duplicate game entries.
        let conflicting_games = drain_duplicates(&mut config.games)
            .into_iter()
            .map(Problem::ConflictingGames)
            .collect();

        let problems = [conflicting_games, missing_games].concat();
        Ok((config, problems))
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
