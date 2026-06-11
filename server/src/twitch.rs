use serde::Deserialize;

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
    let agent = ureq::Agent::new_with_config(
        ureq::Agent::config_builder()
            .http_status_as_error(false)
            .build(),
    );
    let mut response = agent
        .post("https://id.twitch.tv/oauth2/token")
        .query("client_id", client_id)
        .query("client_secret", client_secret)
        .query("grant_type", "client_credentials")
        .send_empty()
        .unwrap();

    let body = response.body_mut().read_to_string().unwrap();
    match response.status().as_u16() {
        200 => {
            let auth = serde_json::from_str::<Authentication>(&body).unwrap();
            Ok(auth)
        }
        status => {
            let error = serde_json::from_str::<AuthenticationError>(&body).unwrap();
            Err(Error::ClientError(status, error.message))
        }
    }
}
