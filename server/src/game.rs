use crate::config::{self, Config};
use crate::igdb;
use crate::twitch;
use serde::Serialize;
use std::fmt;
use std::fs;
use std::path::PathBuf;
use unicode_normalization::UnicodeNormalization;

type Error = Box<dyn std::error::Error>;
type Result<T> = std::result::Result<T, Error>;

#[derive(Clone)]
pub enum Warning {
    MissingSlug(String),
}

impl fmt::Display for Warning {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Warning::MissingSlug(slug) => write!(f, "slug \"{}\" doesn't exist on IGDB", slug),
        }
    }
}

pub fn games_from_config(
    config: &Config,
    last_request: &mut std::time::Instant,
) -> Result<(Vec<Game>, Vec<Warning>)> {
    let access_token = twitch::authenticate(&config.twitch_client_id, &config.twitch_client_secret)
        .unwrap()
        .access_token;

    let slugs: Vec<&str> = config.games.iter().map(|g| g.slug.as_str()).collect();
    let igdb_games = igdb::get_games(
        &config.twitch_client_id,
        &access_token,
        last_request,
        &slugs,
    )
    .unwrap();

    let mut games: Vec<Game> = igdb_games
        .into_iter()
        .map(|igdb_game| {
            let g = config
                .games
                .iter()
                .find(|i| i.slug == igdb_game.slug)
                .unwrap();
            let metadata = fs::metadata(config.root.join(&g.path)).unwrap();
            game(igdb_game, g, metadata, config)
        })
        .collect();

    games.sort_by(|a, b| a.name.cmp(&b.name));

    let warnings = config
        .games
        .iter()
        .filter_map(|a| {
            if games.iter().any(|b| a.slug == b.slug) {
                None
            } else {
                Some(Warning::MissingSlug(a.slug.to_owned()))
            }
        })
        .collect();

    Ok((games, warnings))
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
pub struct Image {
    pub id: String,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Serialize, Clone)]
pub struct Game {
    // INFO
    pub name: String,
    pub slug: String,
    pub search_names: Vec<String>,
    pub summary: Option<String>,
    pub genres: Vec<u64>,
    pub themes: Vec<u64>,

    // MULTIPLAYER
    pub has_single_player: bool,
    pub has_coop_campaign: bool,
    pub offline_coop: Multiplayer,
    pub offline_pvp: Multiplayer,
    pub online_coop: Multiplayer,
    pub online_pvp: Multiplayer,

    // MEDIA
    pub cover: Option<Image>,
    pub screenshots: Vec<Image>,
    pub videos: Vec<String>,
    pub graphics: Graphics,

    // STORES
    pub steam: Option<String>,
    pub gog: Option<String>,
    pub itch: Option<String>,
    pub epic: Option<String>,
    pub google_play: Option<String>,
    pub apple_phone: Option<String>,
    pub apple_pad: Option<String>,

    // FILE INFO
    pub path: PathBuf,
    pub size_bytes: u64,
    pub version: Option<String>,
}

fn game(
    game: igdb::Game,
    distribution: &config::Game,
    metadata: fs::Metadata,
    config: &config::Config,
) -> Game {
    const PLATFORM_WINDOWS: u64 = 6;
    let pc_multiplayer = game
        .multiplayer_modes
        .iter()
        .find(|mode| mode.platform == Some(PLATFORM_WINDOWS) || mode.platform == None);

    const GAME_MODE_SINGLE_PLAYER: u64 = 1;
    const GAME_MODE_MULTIPLAYER: u64 = 2;
    const GAME_MODE_COOP: u64 = 3;
    let has_single_player = game.game_modes.contains(&GAME_MODE_SINGLE_PLAYER);
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
            offline_coop = if game.game_modes.contains(&GAME_MODE_COOP) {
                Multiplayer::Some
            } else {
                Multiplayer::None
            };
            offline_pvp = if game.game_modes.contains(&GAME_MODE_MULTIPLAYER) {
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
    let keywords = game.keywords;
    let has_pixel_art_keyword = PIXEL_ART_KEYWORDS
        .iter()
        .any(|keyword| keywords.contains(keyword));
    let graphics = if has_pixel_art_keyword {
        Graphics::Pixelated
    } else {
        Graphics::Smooth
    };

    let search_names = {
        let alternative_names: Vec<String> = game
            .alternative_names
            .iter()
            .map(|n| n.name.clone())
            .collect();
        let is_alphanumeric = |c: &char| "abcdefghijklmnopqrstuvwxyz1234567890 ".contains(*c);
        std::iter::once(game.name.clone())
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

    let mut steam = None;
    let mut gog = None;
    let mut itch = None;
    let mut epic = None;
    let mut google_play = None;
    let mut apple_phone = None;
    let mut apple_pad = None;
    for site in game.websites {
        if !site.trusted {
            continue;
        }
        match site.category {
            igdb::WEBSITE_STEAM => steam = Some(site.url),
            igdb::WEBSITE_GOG => gog = Some(site.url),
            igdb::WEBSITE_ITCH => itch = Some(site.url),
            igdb::WEBSITE_EPIC_GAMES => epic = Some(site.url),
            igdb::WEBSITE_GOOGLE_PLAY => google_play = Some(site.url),
            igdb::WEBSITE_APPLE_PHONE => apple_phone = Some(site.url),
            igdb::WEBSITE_APPLE_PAD => apple_pad = Some(site.url),
            _ => {}
        }
    }

    Game {
        name: game.name,
        slug: game.slug,
        search_names,
        cover: game.cover.map(|cover| Image {
            id: cover.image_id,
            width: cover.width,
            height: cover.height,
        }),
        genres: game.genres,
        themes: game.themes,
        has_coop_campaign,
        has_single_player,
        offline_coop,
        offline_pvp,
        online_coop,
        online_pvp,
        summary: game.summary,
        steam,
        gog,
        itch,
        epic,
        google_play,
        apple_phone,
        apple_pad,
        videos: game
            .videos
            .iter()
            .map(|v| {
                format!(
                    "https://www.youtube-nocookie.com/embed/{}?modestbranding=1",
                    v.video_id
                )
            })
            .collect(),
        screenshots: game
            .screenshots
            .iter()
            .map(|screenshot| Image {
                id: screenshot.image_id.clone(),
                width: screenshot.width,
                height: screenshot.height,
            })
            .collect(),
        graphics,

        size_bytes: metadata.len(),
        version: {
            match title_and_version(&distribution.path.to_string_lossy()) {
                GameName::TitleAndVersion(_, version) => Some(version),
                _ => None,
            }
        },
        path: config.root.join(&distribution.path),
    }
}

enum GameName {
    None,
    Title(String),
    TitleAndVersion(String, String),
}

fn title_and_version(string: &str) -> GameName {
    let mut parts = string.split(|c| c == '(' || c == ')');
    let title = match parts.next().map(|t| t.trim()) {
        Some(title) => title,
        None => return GameName::None,
    };

    let version = parts.next();
    match version {
        Some(version) => GameName::TitleAndVersion(title.to_string(), version.to_string()),
        None => GameName::Title(title.to_string()),
    }
}
