use crate::config::{self, Config};
use crate::igdb;
use serde::Serialize;
use std::fmt;
use std::fs;
use std::path::PathBuf;
use unicode_normalization::UnicodeNormalization;

type Error = Box<dyn std::error::Error>;
type Result<T> = std::result::Result<T, Error>;

#[derive(Clone)]
pub enum Problem {
    MissingSlug(String),
}

impl fmt::Display for Problem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Problem::MissingSlug(slug) => write!(f, "slug \"{}\" doesn't exist on IGDB", slug),
        }
    }
}

pub fn games_from_config(config: &Config) -> Result<(Vec<Game>, Vec<Problem>)> {
    let slugs: Vec<&str> = config.games.iter().map(|g| g.slug.as_str()).collect();
    let mut games: Vec<Game> = igdb::get_games(&config.igdb_key, &slugs)
        .unwrap()
        .into_iter()
        .map(|igdb_game| {
            let g = config
                .games
                .iter()
                .find(|i| i.slug == igdb_game.slug)
                .unwrap();
            let metadata = fs::metadata(config.root.join(&g.path)).unwrap();
            game(igdb_game, g, metadata)
        })
        .collect();
    games.sort_by(|a, b| a.name.cmp(&b.name));

    let problems = config
        .games
        .iter()
        .filter_map(|a| {
            if games.iter().any(|b| a.slug == b.slug) {
                None
            } else {
                Some(Problem::MissingSlug(a.slug.to_owned()))
            }
        })
        .collect();

    Ok((games, problems))
}

#[derive(Debug, Serialize, Clone)]
pub struct Game {
    // INFO
    pub name: String,
    pub slug: String,
    pub search_names: Vec<String>,
    pub cover: Option<String>,
    pub summary: Option<String>,
    pub genres: Vec<u64>,
    pub themes: Vec<u64>,
    pub game_modes: Vec<u64>,
    pub max_players_offline: u32,
    pub max_players_online: u32,
    pub screenshots: Vec<String>,
    pub videos: Vec<String>,

    // DISTRIBUTION
    pub path: PathBuf,
    pub size_bytes: u64,
    pub version: Option<String>,
}

fn game(igdb: igdb::Game, distribution: &config::Game, metadata: fs::Metadata) -> Game {
    let pc_multiplayer = match igdb.multiplayer_modes {
        Some(multiplayer_modes) => multiplayer_modes
            .into_iter()
            .find(|mode| mode.platform == Some(6) || mode.platform == None),
        None => None,
    };

    let search_names = {
        let alternative_names: Vec<String> = igdb
            .alternative_names
            .map(|names| names.iter().map(|n| n.name.clone()).collect())
            .unwrap_or_default();
        let is_alphanumeric = |c: &char| "abcdefghijklmnopqrstuvwxyz1234567890 ".contains(*c);
        std::iter::once(igdb.name.clone())
            .chain(alternative_names)
            .map(|n| {
                n.nfkd()
                    .filter(char::is_ascii)
                    .flat_map(char::to_lowercase)
                    .filter(is_alphanumeric)
                    .fold(String::new(), |mut s, c| {
                        let is_another_space = c == ' ' && s.ends_with(' ');
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
        summary: igdb.summary,
        videos: igdb
            .videos
            .map(|videos| {
                videos
                    .iter()
                    .map(|v| format!("https://www.youtube.com/embed/{}", v.video_id))
                    .collect()
            })
            .unwrap_or_default(),
        screenshots: igdb
            .screenshots
            .map(|screenshots| {
                screenshots
                    .iter()
                    .map(|ss| {
                        format!(
                            "https://images.igdb.com/igdb/image/upload/t_original/{}.jpg",
                            ss.image_id
                        )
                    })
                    .collect()
            })
            .unwrap_or_default(),

        size_bytes: metadata.len(),
        version: {
            match title_and_version(&distribution.path.to_string_lossy()) {
                Some((_, version)) => version,
                None => None,
            }
        },
        path: PathBuf::from("games").join(&distribution.path),
    }
}

fn title_and_version(string: &str) -> Option<(String, Option<String>)> {
    let mut parts = string.split(|c| c == '(' || c == ')');
    let title = parts.next();
    let version = parts.next();
    match title {
        Some(title) => Some((title.trim().into(), version.map(Into::into))),
        None => None,
    }
}
