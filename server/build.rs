use std::ffi::OsStr;
use std::fmt::Write;
use std::io::ErrorKind::NotFound;
use std::path::PathBuf;
use std::process::{exit, Command};
use std::{env, fs};
use walkdir::WalkDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client_path = PathBuf::from("../client-web");

    //
    // Tell cargo that if any web files change, the build needs to be rerun.
    //

    for entry in WalkDir::new(&client_path) {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let path = entry.path();
        let extension = match path.extension() {
            Some(extension) => extension.to_ascii_lowercase(),
            None => continue,
        };
        let should_check = ["elm", "json", "js", "svg", "css", "txt", "png", "ico"]
            .iter()
            .any(|&e| e == extension);
        if should_check {
            if let Some(path) = path.to_str() {
                println!("cargo:rerun-if-changed={}", path);
            }
        }
    }

    //
    // Build the Elm application.
    //

    let is_release = match env::var("PROFILE")?.as_str() {
        "debug" => false,
        "release" => true,
        profile => panic!("unknown profile: {}", profile),
    };
    let elm_output = Command::new(ELM)
        .current_dir(&client_path)
        .args(&[
            "make",
            "src/Main.elm",
            if is_release { "--optimize" } else { "--debug" },
            "--output=elm.js",
        ])
        .output()
        .map_err(|e| match e.kind() {
            NotFound => {
                print_how_to_install_elm();
                exit(1);
            }
            _ => e,
        })?;
    if !elm_output.status.success() {
        eprintln!("{}", String::from_utf8_lossy(&elm_output.stdout));
        eprintln!("{}", String::from_utf8_lossy(&elm_output.stderr));
        panic!("Elm failed to compile. Fix the errors and try rebuilding.");
    }
    if is_release {
        // Additional javascript minification. This follows the advice given here:
        // https://guide.elm-lang.org/optimization/asset_size.html
        Command::new(UGLIFYJS)
            .current_dir(&client_path)
            .args(&["elm.js", "--compress", r##"'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe'"##, "--output=elm.js"])
            .output()
            .map_err(|e| {
                match e.kind() {
                    NotFound => {
                        print_how_to_install_uglifyjs();
                        exit(1);
                    }
                    _ => e
                }
            })?;
        Command::new(UGLIFYJS)
            .current_dir(&client_path)
            .args(&["elm.js", "--mangle", "--output=elm.js"])
            .output()
            .map_err(|e| match e.kind() {
                NotFound => {
                    print_how_to_install_uglifyjs();
                    exit(1);
                }
                _ => e,
            })?;
    }

    //
    // Copy all static assets to the output dir.
    //

    let out_dir = PathBuf::from(env::var("OUT_DIR")?).join("client-web");
    let options = fs_extra::dir::CopyOptions {
        overwrite: true,
        skip_exist: false,
        buffer_size: 64_000,
        copy_inside: true,
        content_only: true,
        depth: 0,
    };
    fs_extra::dir::copy(client_path.join("assets"), out_dir.join("assets"), &options)?;
    fs::copy(client_path.join("index.html"), out_dir.join("index.html"))?;
    fs::copy(client_path.join("robots.txt"), out_dir.join("robots.txt"))?;
    fs::copy(client_path.join("favicon.ico"), out_dir.join("favicon.ico"))?;
    // TODO: if the program throws an exception here, elm.js is left in client_web

    // Copy elm app
    let elm_path = client_path.join("elm.js");
    fs::copy(&elm_path, out_dir.join("assets/elm.js"))?;
    fs::remove_file(&elm_path)?;

    //
    // Build client_web.rs
    //

    let assets: Vec<PathBuf> = WalkDir::new(&out_dir)
        .into_iter()
        .filter_map(|entry| {
            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => return None,
            };
            let path = entry.path();
            if path.is_dir() {
                return None;
            }
            Some(path.to_path_buf())
        })
        .collect();

    let mut client_web = String::new();
    writeln!(
        &mut client_web,
        "pub const CLIENT_WEB: [(&str, &[u8]); {}] = [",
        assets.len()
    )?;
    for asset in assets.iter() {
        let url = PathBuf::from("/")
            .join(asset.strip_prefix(&out_dir)?)
            .to_str()
            .unwrap()
            .chars()
            .map(|c| if c == '\\' { '/' } else { c })
            .collect::<String>();

        writeln!(
            &mut client_web,
            r##"    ("{url}", include_bytes!(concat!(env!("OUT_DIR"), "/client-web{url}"))),"##,
            url = url,
        )?;
    }
    writeln!(&mut client_web, "];")?;
    fs::write("src/client_web.rs", client_web)?;

    Ok(())
}

fn print_how_to_install_uglifyjs() {
    eprintln!("I tried to run 'uglifyjs' but couldn't find it!");
    eprintln!("The quickest way to fix this is to install it from npm using this command:");
    eprintln!("$ npm install --global uglify-js");
}

fn print_how_to_install_elm() {
    eprintln!("I tried to run 'elm' but couldn't find it!");
    eprintln!("Elm is really easy to install. It's just a single binary.");
    eprintln!("Go to the link below and either download the binary, or run the installer.");
    eprintln!("https://github.com/elm/compiler/releases/tag/0.19.1");
}

pub const ELM: &str = "elm";

#[cfg(windows)]
pub const UGLIFYJS: &str = "uglifyjs.cmd"; // Assuming UglifyJS is installed via npm.
#[cfg(not(windows))]
pub const UGLIFYJS: &str = "uglifyjs";
