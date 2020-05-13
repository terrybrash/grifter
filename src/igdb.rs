use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use ureq::get;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Cover {
    pub id: u64,
    pub image_id: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct GameMode {
    pub id: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Genre {
    pub id: u64,
    pub name: String,
    pub slug: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Theme {
    pub id: u64,
    pub name: String,
    pub slug: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct MultiplayerMode {
    pub id: u64,
    pub campaigncoop: bool,
    pub dropin: bool,
    pub game: u64,
    pub lancoop: bool,
    pub offlinecoop: bool,
    pub offlinecoopmax: Option<u32>, // exists if offlinecoop is true
    pub offlinemax: Option<u32>,
    pub onlinecoop: bool,
    pub onlinecoopmax: Option<u32>, // exists if onlinecoop is true
    pub onlinemax: Option<u32>,
    pub platform: Option<u64>,
    pub splitscreen: bool,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Screenshot {
    pub id: u64,
    pub image_id: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Video {
    pub id: u64,
    pub video_id: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AlternativeName {
    pub id: u64,
    pub name: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Game {
    pub id: u64,
    pub slug: String,
    pub name: String,
    #[serde(default)]
    pub alternative_names: Vec<AlternativeName>,
    pub updated_at: u64,
    pub summary: Option<String>,
    pub cover: Option<Cover>,
    #[serde(default)]
    pub game_modes: Vec<u64>,
    #[serde(default)]
    pub genres: Vec<u64>,
    #[serde(default)]
    pub themes: Vec<u64>,
    #[serde(default)]
    pub keywords: HashSet<u64>,
    #[serde(default)]
    pub multiplayer_modes: Vec<MultiplayerMode>,
    pub screenshots: Option<Vec<Screenshot>>,
    pub videos: Option<Vec<Video>>,
}

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    Json(serde_json::error::Error),
}

const IGDB_MAX_LIMIT: usize = 500;

pub fn get_games<T>(user_key: &str, slugs: &[T]) -> Result<Vec<Game>, Error>
where
    T: std::fmt::Display,
{
    if slugs.is_empty() {
        Ok(vec![])
    } else if slugs.len() > IGDB_MAX_LIMIT {
        let head = get_games(user_key, &slugs[0..IGDB_MAX_LIMIT]);
        let tail = get_games(user_key, &slugs[IGDB_MAX_LIMIT..]);
        match (head, tail) {
            (Ok(head), Ok(tail)) => Ok([head, tail].concat()),
            (err @ Err(_), _) | (_, err @ Err(_)) => err,
        }
    } else {
        let conditions = slugs
            .iter()
            .map(|s| format!("slug = \"{}\"", &s))
            .collect::<Vec<String>>()
            .join(" | ");
        let fields = [
            "id",
            "slug",
            "name",
            "updated_at",
            "cover.image_id",
            "videos.video_id",
            "screenshots.image_id",
            "summary",
            "multiplayer_modes.*",
            "game_modes",
            "genres",
            "themes",
            "keywords",
            "alternative_names.name",
        ];
        let query = format!(
            "fields {fields}; where {conditions}; limit {limit};",
            fields = fields.join(", "),
            conditions = conditions,
            limit = IGDB_MAX_LIMIT
        );
        let response = get("https://api-v3.igdb.com/games")
            .set("user-key", user_key)
            .send_string(&query)
            .into_string()
            .map_err(Error::Io)?;

        serde_json::from_str(&response).map_err(Error::Json)
    }
}

pub fn get_genres(user_key: &str) -> Result<Vec<Genre>, Error> {
    let response = get("https://api-v3.igdb.com/genres")
        .set("user-key", user_key)
        .send_string(&format!("fields id, name, slug; limit {};", IGDB_MAX_LIMIT))
        .into_string()
        .map_err(Error::Io)?;

    serde_json::from_str(&response).map_err(Error::Json)
}

pub fn get_themes(user_key: &str) -> Result<Vec<Theme>, Error> {
    let response = get("https://api-v3.igdb.com/themes")
        .set("user-key", user_key)
        .send_string(&format!("fields id, name, slug; limit {};", IGDB_MAX_LIMIT))
        .into_string()
        .map_err(Error::Io)?;

    serde_json::from_str(&response).map_err(Error::Json)
}
