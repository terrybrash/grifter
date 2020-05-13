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
pub enum Multiplayer {
    None,
    Some,
    Limited(u32),
}

#[derive(Debug, Serialize, Clone)]
pub enum Graphics {
    Pixelated,
    Smooth,
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
    pub has_single_player: bool,
    pub has_coop_campaign: bool,
    pub offline_coop: Multiplayer,
    pub offline_pvp: Multiplayer,
    pub online_coop: Multiplayer,
    pub online_pvp: Multiplayer,
    pub screenshots: Vec<String>,
    pub videos: Vec<String>,
    pub graphics: Graphics,

    // DISTRIBUTION
    pub path: PathBuf,
    pub size_bytes: u64,
    pub version: Option<String>,
}

fn game(igdb: igdb::Game, distribution: &config::Game, metadata: fs::Metadata) -> Game {
    const PLATFORM_WINDOWS: u64 = 6;
    let pc_multiplayer = igdb
        .multiplayer_modes
        .iter()
        .find(|mode| mode.platform == Some(PLATFORM_WINDOWS) || mode.platform == None);

    const GAME_MODE_SINGLE_PLAYER: u64 = 1;
    const GAME_MODE_MULTIPLAYER: u64 = 2;
    const GAME_MODE_COOP: u64 = 3;
    let has_single_player = igdb.game_modes.contains(&GAME_MODE_SINGLE_PLAYER);
    let has_coop_campaign;
    let offline_coop;
    let offline_pvp;
    let online_coop;
    let online_pvp;
    match pc_multiplayer {
        Some(multiplayer) => {
            has_coop_campaign = multiplayer.campaigncoop;
            offline_coop = match (multiplayer.offlinecoop, multiplayer.offlinecoopmax) {
                (_, Some(0)) => Multiplayer::None,
                (_, Some(max)) => Multiplayer::Limited(max),
                (true, None) => Multiplayer::Some,
                (false, None) => Multiplayer::None,
            };
            offline_pvp = match multiplayer.offlinemax {
                Some(0) => Multiplayer::None,
                Some(max) => Multiplayer::Limited(max),
                None => Multiplayer::None,
            };
            online_coop = match (multiplayer.onlinecoop, multiplayer.onlinecoopmax) {
                (_, Some(0)) => Multiplayer::None,
                (_, Some(max)) => Multiplayer::Limited(max),
                (true, None) => Multiplayer::Some,
                (false, None) => Multiplayer::None,
            };
            online_pvp = match multiplayer.onlinemax {
                Some(0) => Multiplayer::None,
                Some(max) => Multiplayer::Limited(max),
                None => Multiplayer::None,
            };
        }
        None => {
            has_coop_campaign = false;
            offline_coop = if igdb.game_modes.contains(&GAME_MODE_COOP) {
                Multiplayer::Some
            } else {
                Multiplayer::None
            };
            offline_pvp = if igdb.game_modes.contains(&GAME_MODE_MULTIPLAYER) {
                Multiplayer::Some
            } else {
                Multiplayer::None
            };
            online_coop = Multiplayer::None;
            online_pvp = Multiplayer::None;
        }
    }

    const PIXEL_ART_KEYWORDS: [u64; 6] = [
        891,   // pixel
        1263,  // pixelated
        1705,  // pixel-art
        1780,  // pixel-graphics
        1952,  // pixels
        16700, // pixelart
    ];
    let keywords = igdb.keywords;
    let has_pixel_art_keyword = PIXEL_ART_KEYWORDS
        .iter()
        .any(|keyword| keywords.contains(keyword));
    let graphics = if has_pixel_art_keyword {
        Graphics::Pixelated
    } else {
        Graphics::Smooth
    };

    let search_names = {
        let alternative_names: Vec<String> = igdb
            .alternative_names
            .iter()
            .map(|n| n.name.clone())
            .collect();
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
        genres: igdb.genres,
        themes: igdb.themes,
        has_coop_campaign,
        has_single_player,
        offline_coop,
        offline_pvp,
        online_coop,
        online_pvp,
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
        graphics,

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
