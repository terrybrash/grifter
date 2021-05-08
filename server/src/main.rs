#![feature(proc_macro_hygiene)]
#![feature(decl_macro)]
#![feature(drain_filter)]

use config::Config;

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

    let (config, warnings) = Config::from_file("grifter.toml")?;
    for warning in warnings {
        println!("Warning: {}", warning);
    }

    let (games, warnings) = game::games_from_config(&config)?;
    for warning in warnings {
        println!("Warning: {}", warning);
    }

    println!("Indexed {} games.", games.len());

    api::start(&config, games);
    Ok(())
}
