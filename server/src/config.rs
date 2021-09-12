use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::OsString;
use std::fmt;
use std::fs;
use std::path::PathBuf;
use thiserror::Error;

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

#[derive(Error, Debug)]
pub enum Error {
    #[error("failed to parse toml")]
    BadToml(toml::de::Error),

    #[error("bad root")]
    BadRoot(std::io::Error),

    #[error("not finished setting up")]
    NotFinishedSettingUp,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Game {
    pub path: PathBuf,
    pub slug: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub im_finished_setting_up: bool,
    pub root: PathBuf,
    pub twitch_client_id: String,
    pub twitch_client_secret: String,
    #[serde(default)]
    pub games: Vec<Game>,
    pub address: String,
    pub port: u16,
}

impl Config {
    pub fn from_str(text: &str) -> Result<(Self, Vec<Warning>), Error> {
        let mut config: Config = toml::from_str(text).map_err(Error::BadToml)?;

        if !config.im_finished_setting_up {
            return Err(Error::NotFinishedSettingUp);
        }

        // Check for executables that exist but aren't listed in the config file.
        let root = fs::read_dir(&config.root).map_err(Error::BadRoot)?;
        let unused_executables = root
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
            .collect::<Vec<_>>();

        let warnings = [unused_executables, conflicting_games, missing_games].concat();
        Ok((config, warnings))
    }
}

pub const EXAMPLE_CONFIG: &str =
    "# Read through this entire config to get set up. When you're done, set this to true!\n\
    # This config file is written in TOML. You can get familiar with the syntax of TOML here: https://toml.io/\n\
    im_finished_setting_up = false\n\
    \n\
    # This is the folder containing your games.\n\
    root = '/path/to/all/my/games'\n\
    \n\
    # Create a new Twitch application and get the client id and secret.\n\
    # Go here to learn how to do that: https://api-docs.igdb.com/#account-creation\n\
    twitch_client_id = '11b084af98ea18caafcae608a9a0e89c' # This is totally fake. Replace it! \n\
    twitch_client_secret = '11b084af98ea18caafcae608a9a0e89c' # This is totally fake. Replace it! \n\
    \n\
    # These are optional server settings. You don't have to configure them; the defaults will work just fine.\n\
    address = \"0.0.0.0\"\n\
    port = 39090\n\
    \n\
    # Now, list all of your games below, each beginning with a `[[games]]` and\n\
    # containing both the \"path\" and the \"slug\" for each game.\n\
    # - \"path\" is the filename of the game, relative to \"root\". It can be nested within a folder.\n\
    # - \"slug\" is the IGDB id, otherwise known as a slug.\n\
    \n\
    # Here are three example games:\n\
    [[games]]\n\
    path = 'Cave Story.zip'\n\
    slug = 'cave-story'\n\
    \n\
    [[games]]\n\
    path = 'Diablo 2, Lord of Destruction.exe'\n\
    slug = 'diablo-ii'\n\
    \n\
    [[games]]\n\
    path = 'The Witness.zip'\n\
    slug = 'the-witness'\n\
    ";

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
