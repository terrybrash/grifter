use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::HashSet;
use ureq::post;

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
    Auth(u16, String),
}

const IGDB_ENDPOINT: &str = "https://api.igdb.com/v4";
const IGDB_QUERY_LIMIT: usize = 500;

pub fn get_games<T>(client_id: &str, access_token: &str, slugs: &[T]) -> Result<Vec<Game>, Error>
where
    T: std::fmt::Display,
{
    if slugs.is_empty() {
        Ok(vec![])
    } else if slugs.len() > IGDB_QUERY_LIMIT {
        let head = get_games(client_id, access_token, &slugs[0..IGDB_QUERY_LIMIT]);
        let tail = get_games(client_id, access_token, &slugs[IGDB_QUERY_LIMIT..]);
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
            limit = IGDB_QUERY_LIMIT
        );

        let response = post(&format!("{}/games", IGDB_ENDPOINT))
            .set("client-id", client_id)
            .auth_kind("Bearer", access_token)
            .send_string(&query);

        handle_response(response)
    }
}

pub fn get_genres(client_id: &str, access_token: &str) -> Result<Vec<Genre>, Error> {
    let response = post(&format!("{}/genres", IGDB_ENDPOINT))
        .set("client-id", client_id)
        .auth_kind("Bearer", access_token)
        .send_string(&format!(
            "fields id, name, slug; limit {};",
            IGDB_QUERY_LIMIT
        ));

    handle_response(response)
}

pub fn get_themes(client_id: &str, access_token: &str) -> Result<Vec<Theme>, Error> {
    let response = post(&format!("{}/themes", IGDB_ENDPOINT))
        .set("client-id", client_id)
        .auth_kind("Bearer", access_token)
        .send_string(&format!(
            "fields id, name, slug; limit {};",
            IGDB_QUERY_LIMIT
        ));

    handle_response(response)
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct IgdbAuthError {
    message: String,
}

#[derive(Deserialize)]
struct IgdbQueryError {
    pub title: String,
    pub status: u16,
    pub cause: String,
}

fn handle_response<T>(response: ureq::Response) -> Result<T, Error>
where
    T: DeserializeOwned,
{
    if response.status() == 401 || response.status() == 403 {
        let code = response.status();
        let error = response.into_json_deserialize::<IgdbAuthError>();
        let message = match error {
            Ok(error) => error.message,
            Err(_) => String::new(),
        };
        return Err(Error::Auth(code, message));
    }

    if response.status() == 400 {
        // 400 from IGDB means there's syntax errors in the query. We shouldn't try to 
        // gracefully handle this. The syntax errors should just be fixed as soon as possible.
        let errors = response.into_json_deserialize::<Vec<IgdbQueryError>>().unwrap();
        panic!(errors);
    }

    Ok(response.into_json_deserialize().unwrap())
}
