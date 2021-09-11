#![feature(proc_macro_hygiene)]
#![feature(decl_macro)]
#![feature(drain_filter)]

use config::Config;
use std::fs;
use std::io::Write;

mod api;
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
            let mut file = fs::File::create(config_filename)?;
            file.write_all(config::EXAMPLE_CONFIG.as_bytes())?;

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
    };

    let mut last_request = std::time::Instant::now();
    let (games, warnings) = game::games_from_config(&config, &mut last_request)?;
    for warning in warnings {
        println!("Warning: {}", warning);
    }

    println!("Indexed {} games.", games.len());

    api::start(&config, &mut last_request, games).unwrap();
    Ok(())
}
