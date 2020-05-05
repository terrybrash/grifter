use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    Command::new("elm")
        .current_dir("ui")
        .args(&["make", "src/Main.elm", "--optimize"])
        .output()
        .unwrap();
    std::fs::rename("ui/index.html", out_dir.join("index.html")).unwrap();
}
