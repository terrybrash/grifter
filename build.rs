use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    Command::new("elm")
        .current_dir("ui")
        .args(&["make", "src/Main.elm", "--optimize", "--output=elm.js"])
        .output()
        .unwrap();

    // Additional javascript minification. This follows the advice given here:
    // https://guide.elm-lang.org/optimization/asset_size.html
    Command::new("uglifyjs")
        .current_dir("ui")
        .args(&["elm.js", "--compress", r##"'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe'"##, "--output=elm.js"])
        .output()
        .unwrap();
    Command::new("uglifyjs")
        .current_dir("ui")
        .args(&["elm.js", "--mangle", "--output=elm.js"])
        .output()
        .unwrap();

    // Insert the final compiled/minified elm file into a barebons html file ready to be served.
    let elm = std::fs::read_to_string("ui/elm.js").unwrap();
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
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    std::fs::write(out_dir.join("index.html"), index).unwrap();

    // Cleanup
    std::fs::remove_file("ui/elm.js").unwrap();
}
