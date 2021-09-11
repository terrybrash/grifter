use serde::Deserialize;
use ureq::post;

#[derive(Debug, Deserialize)]
pub struct Authentication {
    pub access_token: String,
    pub expires_in: u32,
    pub token_type: String,
}

#[derive(Debug)]
pub enum Error {
    ClientError(u16, String),
    Other(u16),
}

#[derive(Debug, Deserialize)]
pub struct AuthenticationError {
    message: String,
}

pub fn authenticate(client_id: &str, client_secret: &str) -> Result<Authentication, Error> {
    let response = post("https://id.twitch.tv/oauth2/token")
        .query("client_id", client_id)
        .query("client_secret", client_secret)
        .query("grant_type", "client_credentials")
        .call()
        .unwrap();

    match response.status() {
        200 => {
            let auth = response.into_string().unwrap();
            let auth = serde_json::from_str::<Authentication>(&auth).unwrap();
            Ok(auth)
        }
        status => {
            let error = response.into_string().unwrap();
            let error = serde_json::from_str::<AuthenticationError>(&error).unwrap();
            Err(Error::ClientError(status, error.message))
        }
    }
}
