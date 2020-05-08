#![feature(proc_macro_hygiene)]
#![feature(decl_macro)]
#![feature(drain_filter)]

use config::Config;

mod api;
mod config;
mod game;
mod igdb;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (config, problems) = Config::from_file("grifter.toml")?;
    for problem in problems {
        println!("Warning: {}", problem);
    }

    let (games, problems) = game::games_from_config(&config)?;
    for problem in problems {
        println!("Warning: {}", problem);
    }

    println!("Indexed {} games.", games.len());

    api::start(&config, games);
    Ok(())
}
