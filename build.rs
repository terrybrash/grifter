use std::env;
use std::io::ErrorKind::NotFound;
use std::path::PathBuf;
use std::process::{exit, Command};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    Command::new(ELM)
        .current_dir("ui")
        .args(&["make", "src/Main.elm", "--optimize", "--output=elm.js"])
        .output()
        .map_err(missing_command("elm"))?;

    // Additional javascript minification. This follows the advice given here:
    // https://guide.elm-lang.org/optimization/asset_size.html
    Command::new(UGLIFYJS)
        .current_dir("ui")
        .args(&["elm.js", "--compress", r##"'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe'"##, "--output=elm.js"])
        .output()
        .map_err(missing_command("uglifyjs"))?;
    Command::new(UGLIFYJS)
        .current_dir("ui")
        .args(&["elm.js", "--mangle", "--output=elm.js"])
        .output()
        .map_err(missing_command("uglifyjs"))?;

    // Insert the compiled elm app into an html file ready to be served.
    let elm = std::fs::read_to_string("ui/elm.js")?;
    let index = format!(
        r##"
        <!DOCTYPE HTML>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Grifter</title>
            <style>body {{ padding: 0; margin: 0; }}</style>
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
    std::fs::remove_file("ui/elm.js")?;

    Ok(())
}

#[cfg(windows)]
pub const ELM: &'static str = "elm.cmd"; // Assuming Elm is installed via npm.
#[cfg(not(windows))]
pub const ELM: &'static str = "elm";

#[cfg(windows)]
pub const UGLIFYJS: &'static str = "uglifyjs.cmd"; // Assuming UglifyJS is installed via npm.
#[cfg(not(windows))]
pub const UGLIFYJS: &'static str = "uglifyjs";

/// Maps a `NotFound` error into a nicer error message explaining what's missing.
fn missing_command(command: &'static str) -> impl Fn(std::io::Error) -> std::io::Error {
    move |e| match e.kind() {
        NotFound => {
            eprintln!(
                "\"{}\" wasn't found on the system. Did you forget to install it?",
                command
            );
            exit(1)
        }
        _ => e,
    }
}
