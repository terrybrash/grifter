use crate::client_web;
use crate::config::Config;
use crate::game::Game;
use crate::igdb;
use crate::twitch;
use crossbeam_channel::{bounded, Receiver, Sender};
use flate2::write::GzEncoder;
use image::GenericImageView;
use rouille::{extension_to_mime, router, Request, Response, Server};
use serde::Serialize;
use std::collections::HashMap;
use std::ffi::OsStr;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub fn gzip(bytes: &[u8]) -> io::Result<Vec<u8>> {
    let mut encoder = GzEncoder::new(Vec::new(), flate2::Compression::best());
    encoder.write_all(bytes)?;
    encoder.finish()
}

#[derive(Clone)]
struct Model {
    catalog: Catalog,
    catalog_gz: Vec<u8>,
    assets_gz: HashMap<&'static str, GzippedAsset>,
}

#[derive(Clone)]
struct GzippedAsset {
    mime: &'static str,
    bytes: Vec<u8>,
}

#[derive(Clone, Serialize)]
struct Catalog {
    games: Vec<Game>,
    genres: Vec<igdb::Genre>,
    themes: Vec<igdb::Theme>,
}

pub fn start(
    config: &Config,
    last_request: &mut std::time::Instant,
    games: Vec<Game>,
) -> std::io::Result<()> {
    let access_token = twitch::authenticate(&config.twitch_client_id, &config.twitch_client_secret)
        .unwrap()
        .access_token;

    let mut genres =
        igdb::get_genres(&config.twitch_client_id, &access_token, last_request).unwrap();
    for genre in genres.iter_mut() {
        // The names for some of these genres are ugly/verbose. Manually fixing them here.
        match genre.id {
            25 => genre.name = "Hack and slash".to_string(),
            16 => genre.name = "Turn-based strategy".to_string(),
            11 => genre.name = "Real Time Strategy".to_string(),
            _ => {}
        }
    }
    genres.drain_filter(|genre| !games.iter().any(|game| game.genres.contains(&genre.id)));
    genres.sort_by(|a, b| a.name.cmp(&b.name));

    let mut themes =
        igdb::get_themes(&config.twitch_client_id, &access_token, last_request).unwrap();
    themes.drain_filter(|theme| !games.iter().any(|game| game.themes.contains(&theme.id)));
    themes.sort_by(|a, b| a.name.cmp(&b.name));

    let model = {
        let mut assets_gz = HashMap::new();
        for (url, uncompressed) in client_web::CLIENT_WEB {
            let compressed = gzip(uncompressed).unwrap();
            let mime = PathBuf::from(url)
                .extension()
                .and_then(OsStr::to_str)
                .map(extension_to_mime)
                .unwrap_or("application/octet-stream");
            let asset = GzippedAsset {
                mime,
                bytes: compressed,
            };
            assets_gz.insert(url, asset);
        }

        let catalog = Catalog {
            games,
            genres,
            themes,
        };
        let catalog_json = serde_json::to_vec(&catalog).unwrap();
        let catalog_gz = gzip(&catalog_json).unwrap();

        Model {
            catalog,
            catalog_gz,
            assets_gz,
        }
    };

    if config.https {
        // Since we're going to start an https server, we'll want to redirect all http traffic
        // to https. So we'll start an http server whose sole purpose is to redirect to the
        // https server.
        let http_port = config.http_port;
        let https_port = config.https_port;
        let address = config.address.clone();
        std::thread::spawn(move || {
            rouille::start_server((address, http_port), move |request| {
                match request.header("host") {
                    Some(host) => {
                        let host_without_port: String =
                            host.chars().take_while(|&c| c != ':').collect();
                        let destination = if https_port == 443 {
                            format!("https://{}{}", host_without_port, request.raw_url())
                        } else {
                            format!(
                                "https://{}:{}{}",
                                host_without_port,
                                https_port,
                                request.raw_url()
                            )
                        };
                        Response::redirect_301(destination)
                    }
                    None => Response::empty_400(),
                }
            });
        });
    }

    let is_https_enabled = config.https;

    use std::sync::atomic::{AtomicUsize, Ordering};
    let requests = AtomicUsize::new(0);
    let handler = move |request: &Request| -> Response {
        let id = requests.fetch_add(1, Ordering::Relaxed);
        println!(
            "[Request  #{id}] {origin} to {protocol}://{host}{path}",
            id = id,
            origin = request.remote_addr().ip(),
            host = request.header("host").unwrap_or(""),
            protocol = if is_https_enabled { "https" } else { "http" },
            path = request.raw_url()
        );

        let _handler = |request: &Request| -> Response {
            match model.assets_gz.get(request.raw_url()) {
                Some(asset) => return assets(asset),
                None => {}
            }

            router!(request,
                (GET) ["/api/catalog"] => {catalog(&model, request)},
                (GET) ["/api/download/{slug}", slug: String] => {download(&model, request, &slug)},
                (GET) ["/api/image/{id}", id: String] => {image(&model, request, &id)},
                (GET) ["/"] => {index(&model, request)},
                _ => index(&model, request),
            )
        };
        let response = _handler(request);
        println!("[Response #{id}] {status}", id = id, status = response.status_code);
        response
    };

    if config.https {
        let certificate = fs::read(&config.ssl_certificate).unwrap();
        let private_key = fs::read(&config.ssl_private_key).unwrap();
        println!(
            "Grifter started on https://{}:{}",
            config.address, config.https_port
        );
        Server::new_ssl(
            (config.address.as_str(), config.https_port),
            handler,
            certificate,
            private_key,
        )
        .expect("Failed to start server")
        .pool_size(8 * num_cpus::get())
        .run()
    } else {
        println!(
            "Grifter started on http://{}:{}",
            config.address, config.http_port
        );
        Server::new((config.address.as_str(), config.http_port), handler)
            .expect("Failed to start server")
            .pool_size(8 * num_cpus::get())
            .run();
    };

    // Will only reach here if the server crashes.
    panic!("The server closed unexpectedly");
}

fn index(model: &Model, _: &Request) -> Response {
    let index = match model.assets_gz.get("/index.html") {
        Some(index) => index,
        None => return Response::empty_404(),
    };

    let csp = [
        "default-src 'none'",
        "font-src https://fonts.gstatic.com",
        "img-src 'self' https://i.ytimg.com",
        "connect-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "frame-ancestors 'none'",
        "frame-src https://www.youtube-nocookie.com/",
        "base-uri 'none'",
        "require-trusted-types-for 'script'",
        "form-action 'none'",
    ];
    Response::from_data(index.mime, index.bytes.clone())
        .with_unique_header("content-encoding", "gzip")
        .with_unique_header("content-security-policy", csp.join("; "))
        .with_unique_header("referrer-policy", "no-referrer")
        .with_unique_header("x-content-type-options", "nosniff")
        .with_unique_header("x-frame-options", "deny")
        .with_unique_header("x-xss-protection", "1; mode=block")
}

fn assets(asset: &GzippedAsset) -> Response {
    Response::from_data(asset.mime, asset.bytes.clone())
        .with_unique_header("content-encoding", "gzip")
}

fn download(model: &Model, _: &Request, slug: &str) -> Response {
    let game = match model.catalog.games.iter().find(|game| game.slug == slug) {
        Some(game) => game,
        None => {
            println!("Download failed: slug doesn't exist {:?}", slug);
            return Response::empty_404();
        }
    };

    let file = match File::open(&game.path) {
        Ok(file) => file,
        Err(_) => {
            println!("Download failed: file doesn't exist {:?}", game.path);
            return Response::empty_404();
        }
    };

    let save_as = game
        .path
        .file_name()
        .and_then(|f| f.to_str())
        .unwrap_or(slug);
    Response::from_file("application/octet-stream", file).with_unique_header(
        "content-disposition",
        format!("attachment; filename=\"{}\"", save_as),
    )
}

fn catalog(model: &Model, _: &Request) -> Response {
    Response::from_data(extension_to_mime("json"), model.catalog_gz.clone())
        .with_unique_header("content-encoding", "gzip")
}

enum ImageSize {
    Thumbnail,
    Original,
}

fn image(_: &Model, request: &Request, image_id: &str) -> Response {
    let size = match request.get_param("size").as_deref() {
        Some("Thumbnail") => ImageSize::Thumbnail,
        Some("Original") => ImageSize::Original,
        _ => return Response::empty_404(),
    };

    let path = match size {
        ImageSize::Thumbnail => image_cache(image_id).join("thumbnail.jpeg"),
        ImageSize::Original => image_cache(image_id).join("original.jpeg"),
    };

    match std::fs::File::open(path) {
        Ok(image) => Response::from_file("image/jpeg", image)
            .with_unique_header("cache-control", "max-age=10368000, immutable"), // 10368000 seconds = 120 days
        Err(_) => Response::empty_404(),
    }
}

fn image_cache(image_id: &str) -> PathBuf {
    let cache_root = Path::new("./cache");
    if let Err(e) = fs::create_dir(cache_root) {
        match e.kind() {
            io::ErrorKind::AlreadyExists => { /* this is fine */ }
            _ => panic!("failed to create cache directory"),
        }
    }
    let image_dir = cache_root.join(image_id);
    if let Err(e) = fs::create_dir(&image_dir) {
        match e.kind() {
            io::ErrorKind::AlreadyExists => { /* this is fine */ }
            _ => panic!("failed to create cache directory"),
        }
    }

    image_dir
}

struct JobThread {
    is_busy: bool,
    sender: Sender<String>,
}

pub fn image_prefetch_pool(thread_count: usize, jobs: Receiver<String>) {
    let mut threads = Vec::with_capacity(thread_count);
    let (on_complete, job_finished) = bounded(thread_count);
    for thread in 0..thread_count {
        let (s, r) = bounded(1);
        let on_complete = on_complete.clone();
        std::thread::spawn(move || image_prefetch_worker(thread, r, on_complete));
        threads.push(JobThread {
            is_busy: false,
            sender: s,
        });
    }

    for job in jobs.into_iter() {
        let free_thread = threads.iter_mut().find(|thread| !thread.is_busy);
        match free_thread {
            Some(thread) => {
                thread.is_busy = true;
                thread.sender.send(job).unwrap();
            }
            None => {
                // now we wait for a thread
                let thread_index = job_finished.recv().unwrap();
                threads[thread_index].sender.send(job).unwrap(); // no rest, get back to work lmao
            }
        }
    }
}

fn image_prefetch_worker(thread: usize, receiver: Receiver<String>, on_complete: Sender<usize>) {
    for image_id in receiver.into_iter() {
        let cache = image_cache(&image_id);
        let original_path = cache.join("original.jpeg");
        let original = match image::open(&original_path) {
            Ok(original) => original,
            Err(_) => {
                let image = igdb::get_image(&image_id).unwrap();
                let original =
                    image::load_from_memory_with_format(&image.bytes[..], image.format).unwrap();
                original
                    .save_with_format(&original_path, image::ImageFormat::Jpeg)
                    .unwrap();
                original
            }
        };

        let thumbnail_path = cache.join("thumbnail.jpeg");
        let _thumbnail = match image::open(&thumbnail_path) {
            Ok(thumbnail) => thumbnail,
            Err(_) => {
                let (tw, th) = max_dimensions(original.dimensions(), (None, Some(200)));
                let thumbnail = original.thumbnail(tw, th);
                thumbnail
                    .save_with_format(&thumbnail_path, image::ImageFormat::Jpeg)
                    .unwrap();
                thumbnail
            }
        };
        println!("Loaded: {}", image_id);
        on_complete.send(thread).unwrap();
    }
}

fn max_dimensions(dimensions: (u32, u32), max: (Option<u32>, Option<u32>)) -> (u32, u32) {
    let (mut width, mut height) = dimensions;
    let (max_width, max_height) = max;
    if let Some(max_width) = max_width {
        width = u32::min(width, max_width);
    }
    if let Some(max_height) = max_height {
        height = u32::min(height, max_height);
    }
    (width, height)
}
