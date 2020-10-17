use serde::Deserialize;
use ureq::post;

#[derive(Debug, Deserialize)]
pub struct Authentication {
    pub access_token: String,
    pub expires_in: u32,
    pub token_type: String,
}

#[derive(Debug, Deserialize)]
pub struct AuthenticationError {
    message: String,
}

#[derive(Debug)]
pub enum Error {
    ClientError(u16, String),
    Other(u16),
}

pub fn authenticate(client_id: &str, client_secret: &str) -> Result<Authentication, Error> {
    let mut request = post("https://id.twitch.tv/oauth2/token");
    request
        .query("client_id", client_id)
        .query("client_secret", client_secret)
        .query("grant_type", "client_credentials");

    let response = request.call();
    if response.client_error() {
        let status = response.status();
        let error = response
            .into_json_deserialize::<AuthenticationError>()
            .unwrap();
        Err(Error::ClientError(status, error.message))
    } else if response.error() {
        Err(Error::Other(response.status()))
    } else {
        let auth = response.into_json_deserialize::<Authentication>().unwrap();
        Ok(auth)
    }
}
