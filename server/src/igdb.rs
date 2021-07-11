use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::HashSet;
use std::time::{Duration, Instant};
use surf::{get, post};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Image {
    pub id: u64,
    pub image_id: String,
    pub width: u32,
    pub height: u32,
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

// pub const WEBSITE_OFFICIAL: u64 = 1;
// pub const WEBSITE_WIKIA: u64 = 2;
// pub const WEBSITE_WIKIPEDIA: u64 = 3;
// pub const WEBSITE_FACEBOOK: u64 = 4;
// pub const WEBSITE_TWITTER: u64 = 5;
// pub const WEBSITE_TWITCH: u64 = 6;
// pub const WEBSITE_INSTAGRAM: u64 = 8;
// pub const WEBSITE_YOUTUBE: u64 = 9;
pub const WEBSITE_APPLE_PHONE: u64 = 10;
pub const WEBSITE_APPLE_PAD: u64 = 11;
pub const WEBSITE_GOOGLE_PLAY: u64 = 12;
pub const WEBSITE_STEAM: u64 = 13;
// pub const WEBSITE_REDDIT: u64 = 14;
pub const WEBSITE_ITCH: u64 = 15;
pub const WEBSITE_EPIC_GAMES: u64 = 16;
pub const WEBSITE_GOG: u64 = 17;
// pub const WEBSITE_DISCORD: u64 = 18;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Website {
    pub category: u64,
    pub trusted: bool,
    pub url: String,
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
    pub cover: Option<Image>,
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
    #[serde(default)]
    pub websites: Vec<Website>,
    #[serde(default)]
    pub screenshots: Vec<Image>,
    #[serde(default)]
    pub videos: Vec<Video>,
}

#[derive(Debug)]
pub enum Error {
    Auth(surf::StatusCode, String),
}

const IGDB_ENDPOINT: &str = "https://api.igdb.com/v4";
const IGDB_QUERY_LIMIT: usize = 500; // https://api-docs.igdb.com/#pagination
const IGDB_REQUEST_COOLDOWN: u64 = 250; // https://api-docs.igdb.com/#rate-limits

pub async fn get_games<T>(
    client_id: &str,
    access_token: &str,
    last_request: &mut Instant,
    slugs: &[T],
) -> Result<Vec<Game>, Error>
where
    T: std::fmt::Display,
{
    let mut requests = 0;
    let mut games: Vec<Game> = Vec::with_capacity(slugs.len());
    while requests * IGDB_QUERY_LIMIT < slugs.len() {
        let start = requests * IGDB_QUERY_LIMIT;
        let end = usize::min((requests + 1) * IGDB_QUERY_LIMIT, slugs.len());
        let conditions = slugs[start..end]
            .iter()
            .map(|s| format!("slug = \"{}\"", &s))
            .collect::<Vec<String>>()
            .join(" | ");
        let fields = [
            "id",
            "slug",
            "name",
            "updated_at",
            "cover.*",
            "videos.video_id",
            "screenshots.*",
            "summary",
            "multiplayer_modes.*",
            "game_modes",
            "genres",
            "themes",
            "keywords",
            "alternative_names.name",
            "websites.category",
            "websites.trusted",
            "websites.url",
        ];
        let query = format!(
            "fields {fields}; where {conditions}; limit {limit};",
            fields = fields.join(", "),
            conditions = conditions,
            limit = IGDB_QUERY_LIMIT
        );
        sleep_for_cooldown(last_request).await;
        let mut response = post(&format!("{}/games", IGDB_ENDPOINT))
            .header("client-id", client_id)
            .header("authorization", format!("Bearer {}", access_token))
            .body(query)
            .send()
            .await
            .unwrap();

        *last_request = Instant::now();
        let mut queried_games: Vec<Game> = handle_response(&mut response).await?;
        games.append(&mut queried_games);
        requests += 1;
    }

    Ok(games)
}

pub async fn get_genres(
    client_id: &str,
    access_token: &str,
    last_request: &mut Instant,
) -> Result<Vec<Genre>, Error> {
    sleep_for_cooldown(last_request).await;
    let query = format!("fields id, name, slug; limit {};", IGDB_QUERY_LIMIT);
    let mut response = post(&format!("{}/genres", IGDB_ENDPOINT))
        .header("client-id", client_id)
        .header("authorization", format!("Bearer {}", access_token))
        .body(query)
        .send()
        .await
        .unwrap();

    *last_request = Instant::now();
    handle_response(&mut response).await
}

pub async fn get_themes(
    client_id: &str,
    access_token: &str,
    last_request: &mut Instant,
) -> Result<Vec<Theme>, Error> {
    sleep_for_cooldown(last_request).await;
    let query = format!("fields id, name, slug; limit {};", IGDB_QUERY_LIMIT);
    let mut response = post(&format!("{}/themes", IGDB_ENDPOINT))
        .header("client-id", client_id)
        .header("authorization", format!("Bearer {}", access_token))
        .body(query)
        .send()
        .await
        .unwrap();

    *last_request = Instant::now();
    handle_response(&mut response).await
}

pub enum ImageData {
    Jpeg(Vec<u8>),
    Png(Vec<u8>),
    Webp(Vec<u8>),
    Gif(Vec<u8>),
    Unsupported(String),
    Unknown,
}

pub async fn get_image(id: &str) -> Result<ImageData, Error> {
    let url = format!(
        "https://images.igdb.com/igdb/image/upload/t_original/{}.xxx",
        id
    );
    let mut response = get(url).send().await.unwrap();
    let content_type = response
        .header("content-type")
        .and_then(|values| values.get(0))
        .map(|value| value.as_str());
    match content_type {
        Some("image/jpeg") => Ok(ImageData::Jpeg(response.body_bytes().await.unwrap())),
        Some("image/png") => Ok(ImageData::Png(response.body_bytes().await.unwrap())),
        Some("image/gif") => Ok(ImageData::Gif(response.body_bytes().await.unwrap())),
        Some("image/webp") => Ok(ImageData::Webp(response.body_bytes().await.unwrap())),
        Some(format) => Ok(ImageData::Unsupported(format.to_owned())),
        None => Ok(ImageData::Unknown),
    }
}

async fn sleep_for_cooldown(last_request: &Instant) {
    let cooldown = Duration::from_millis(IGDB_REQUEST_COOLDOWN);
    let elapsed = last_request.elapsed();
    if cooldown > elapsed {
        async_std::task::sleep(cooldown - elapsed).await;
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct IgdbAuthError {
    message: String,
}

#[derive(Debug, Deserialize)]
struct IgdbQueryError {
    pub title: String,
    pub status: u16,
    pub cause: String,
}

async fn handle_response<T>(response: &mut surf::Response) -> Result<T, Error>
where
    T: DeserializeOwned,
{
    let code = response.status();
    let body = response.body_string().await.unwrap();

    if code == 401 || code == 403 {
        let error: serde_json::Result<IgdbAuthError> = serde_json::from_str(&body);
        let message = match error {
            Ok(error) => error.message,
            Err(_) => String::new(),
        };
        Err(Error::Auth(code, message))
    } else if code == 400 {
        // 400 from IGDB means there's syntax errors in the query. We shouldn't try to
        // gracefully handle this. The syntax errors should just be fixed as soon as possible.
        let errors: Vec<IgdbQueryError> = serde_json::from_str(&body).unwrap();
        panic!("{:?}", errors);
    } else {
        let data: serde_json::Result<T> = serde_json::from_str(&body);
        match data {
            Ok(data) => Ok(data),
            Err(err) => {
                println!("{}", err);
                println!();
                for line in body.lines().skip(err.line()).take(10) {
                    println!("{}", line);
                }
                panic!()
            }
        }
    }
}
