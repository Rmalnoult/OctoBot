use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use walkdir::WalkDir;

fn main() -> Result<()> {
    println!("cargo:rerun-if-changed=assets/python");
    println!("cargo:rerun-if-env-changed=PYEMBED_PAYLOAD");

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?);
    let assets_python = manifest_dir.join("assets").join("python");
    if !assets_python.exists() {
        return Ok(());
    }

    let lib_dir = assets_python.join("python").join("lib");
    if lib_dir.exists() {
        println!("cargo:rustc-link-search=native={}", lib_dir.display());
    }

    // On macOS, ensure the binary can find libpython at runtime.
    if cfg!(target_os = "macos") {
        let rpath = "@executable_path/python/python/lib";
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", rpath);
    }

    let target_dir = env::var("CARGO_TARGET_DIR").unwrap_or_else(|_| "target".to_string());
    let profile = env::var("PROFILE")?;

    let out_python = manifest_dir.join(target_dir).join(profile).join("python");
    if out_python.exists() {
        fs::remove_dir_all(&out_python).context("remove existing python dir")?;
    }
    copy_dir(&assets_python, &out_python)?;

    write_embedded_payload(&manifest_dir)?;

    Ok(())
}

fn write_embedded_payload(manifest_dir: &Path) -> Result<()> {
    let out_file = manifest_dir.join("src").join("embedded_payload.rs");
    if let Ok(payload_path) = env::var("PYEMBED_PAYLOAD") {
        let payload_path = PathBuf::from(payload_path);
        println!("cargo:rerun-if-changed={}", payload_path.display());
        let payload_name = payload_path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("python-payload.tar.zst");

        let contents = format!(
            "pub const EMBEDDED_PAYLOAD: &[u8] = include_bytes!(r#\"{}\"#);\n\
pub const EMBEDDED_PAYLOAD_NAME: &str = \"{}\";\n",
            payload_path.display(),
            payload_name
        );
        fs::write(out_file, contents)?;
    } else {
        let contents = "pub const EMBEDDED_PAYLOAD: &[u8] = &[];\n\
pub const EMBEDDED_PAYLOAD_NAME: &str = \"\";\n";
        fs::write(out_file, contents)?;
    }
    Ok(())
}

fn copy_dir(src: &Path, dst: &Path) -> Result<()> {
    for entry in WalkDir::new(src) {
        let entry = entry?;
        let rel = entry.path().strip_prefix(src)?;
        let dest_path = dst.join(rel);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&dest_path)?;
        } else {
            if let Some(parent) = dest_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(entry.path(), &dest_path)
                .with_context(|| format!("copy {}", entry.path().display()))?;
        }
    }
    Ok(())
}
