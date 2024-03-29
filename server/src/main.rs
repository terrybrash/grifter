#![feature(proc_macro_hygiene)]
#![feature(decl_macro)]
#![feature(drain_filter)]

use config::Config;
use std::fs;

mod api;
mod client_web;
mod config;
mod game;
mod igdb;
mod twitch;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    const VERSION: &str = env!("CARGO_PKG_VERSION_MINOR");
    println!("         _ ___ _           ");
    println!(" ___ ___|_|  _| |_ ___ ___ ");
    println!("| . |  _| |  _|  _| -_|  _|");
    println!("|_  |_| |_|_| |_| |___|_|  ");
    println!("|___|{:>20}", format!("version {}", VERSION));
    println!();

    let config_filename = "grifter.toml";
    let config_text = match fs::read_to_string(config_filename) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            fs::write(config_filename, config::EXAMPLE_CONFIG)?;
            println!("It looks like this is the first time you're running grifter. Nice!!");
            println!("I've created a \"grifter.toml\" file for you. Read it to get set up.");
            println!("When you're done, run grifter again.");
            return Ok(());
        }
        Err(err) => return Err(Box::new(err)),
    };
    let config = match Config::from_str(&config_text) {
        Ok((config, warnings)) => {
            for warning in warnings {
                println!("Warning: {}", warning);
            }
            config
        }
        Err(crate::config::Error::BadRoot(_)) => {
            println!(
                "There was a problem. The \"root\" folder specified in your config doesn't exist."
            );
            return Ok(());
        }
        Err(crate::config::Error::BadToml(err)) => {
            println!("There was a problem. The config file couldn't be parsed.");
            println!("  {}: {}", config_filename, err);
            println!();
            println!("The toml docs are really helpful, check them out: https://toml.io/");
            return Ok(());
        }
        Err(crate::config::Error::NotFinishedSettingUp) => {
            println!(
                "The server can't be started until you're finished configuring \"grifter.toml\"."
            );
            println!(
                "When you're done, change the first value in that file to: im_finished_setting_up = true"
            );
            return Ok(());
        }
        Err(crate::config::Error::BadSsl {
            missing_certificate,
            missing_private_key,
        }) => {
            println!("You have SSL enabled in \"grifter.toml\" but some files are missing:");
            println!(
                "  Certificate: {}",
                if missing_certificate {
                    "NOT FOUND"
                } else {
                    "Found! This one's ok."
                }
            );
            println!(
                "  Private Key: {}",
                if missing_private_key {
                    "NOT FOUND"
                } else {
                    "Found! This one's ok."
                }
            );
            println!("Either disable https, or fix the missing files.");
            return Ok(());
        }
    };

    let mut last_request = std::time::Instant::now();
    let (games, warnings) = game::games_from_config(&config, &mut last_request)?;
    for warning in warnings {
        println!("Warning: {}", warning);
    }
    println!("Indexed {} games.", games.len());

    let (sender, receiver) = crossbeam_channel::unbounded();
    let prefetch_threads = config
        .prefetch_threads
        .map(|threads| num_cpus::get() * threads)
        .unwrap_or_else(num_cpus::get);
    std::thread::spawn(move || {
        api::image_prefetch_pool(prefetch_threads, receiver);
    });
    for game in &games {
        for screenshot in &game.screenshots {
            sender.send(screenshot.id.clone()).unwrap();
        }
        if let Some(cover) = &game.cover {
            sender.send(cover.id.clone()).unwrap();
        }
    }

    api::start(&config, &mut last_request, games).unwrap();
    Ok(())
}
