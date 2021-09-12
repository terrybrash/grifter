use std::env;
use std::io::ErrorKind::NotFound;
use std::path::PathBuf;
use std::process::{exit, Command};
use walkdir::WalkDir;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let is_release = match env::var("PROFILE")?.as_str() {
        "debug" => false,
        "release" => true,
        profile => panic!("unknown profile: {}", profile),
    };

    for entry in WalkDir::new("../client-web") {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let path = entry.path();
        let extension = match path.extension() {
            Some(extension) => extension,
            None => continue,
        };
        if extension == "elm" || extension == "json" {
            if let Some(path) = path.to_str() {
                println!("cargo:rerun-if-changed={}", path);
            }
        }
    }

    let elm_output = Command::new(ELM)
        .current_dir("../client-web")
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
            .current_dir("../client-web")
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
            .current_dir("../client-web")
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

    // Insert the compiled elm app into an html file ready to be served.
    let elm = std::fs::read_to_string("../client-web/elm.js")?;
    let index = format!(
        r##"
        <!DOCTYPE HTML>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Grifter</title>
            <style>body {{ padding: 0; margin: 0; background-color: #fcfbf9; }}</style>
        </head>
        <body>
            <div id="main"></div>
            <script>{}</script>
            <script>var app = Elm.Main.init({{ node: document.getElementById("main") }});</script>
        </body>"##,
        elm
    );
    let out_dir = PathBuf::from(env::var("OUT_DIR")?);
    std::fs::write(out_dir.join("index.html"), index)?;

    // Cleanup
    std::fs::remove_file("../client-web/elm.js")?;

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
