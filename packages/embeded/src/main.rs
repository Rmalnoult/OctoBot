use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use dirs::cache_dir;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList};
use serde::Deserialize;
use tar::Archive;
use zstd::stream::read::Decoder as ZstdDecoder;

mod embedded_payload;

#[derive(Deserialize)]
struct PyEmbedConfig {
    python_home: String,
    python_path: Vec<String>,
}

fn main() -> Result<()> {
    let exe_path = env::current_exe().context("resolve current_exe")?;
    let exe_dir = exe_path
        .parent()
        .context("resolve exe parent directory")?;

    let python_root = ensure_python_root(exe_dir)?;

    let cfg_path = python_root.join("pyembed.json");
    let cfg = load_config(&cfg_path)?;

    let python_home = resolve_path(&python_root, &cfg.python_home);
    let python_path = resolve_paths(&python_root, &cfg.python_path);

    env::set_var("PYTHONHOME", &python_home);
    env::set_var("PYTHONPATH", join_paths(&python_path)?);
    // Python 3.12+ removed stdlib distutils; ensure setuptools provides it.
    env::set_var("SETUPTOOLS_USE_DISTUTILS", "local");

    pyo3::prepare_freethreaded_python();

    Python::with_gil(|py| -> Result<()> {
        let sys = py.import("sys")?;
        let argv = build_argv(py)?;
        sys.setattr("argv", argv)?;

        // Keep sys.path aligned with the embedded Python layout.
        let path_list = PyList::new(py, &python_path)?;
        sys.setattr("path", path_list)?;

        // Ensure .pth files in site-packages are processed (needed for distutils shim).
        let site = py.import("site")?;
        for p in &python_path {
            if p.to_string_lossy().ends_with("site-packages") {
                site.call_method1("addsitedir", (p,))?;
            }
        }

        let module = env::var("OCTOBOT_PY_MODULE").unwrap_or_else(|_| "octobot.cli".to_string());
        let func = env::var("OCTOBOT_PY_FUNC").unwrap_or_else(|_| "main".to_string());

        if func.is_empty() {
            let runpy = py.import("runpy")?;
            let kwargs = PyDict::new(py);
            kwargs.set_item("run_name", "__main__")?;
            kwargs.set_item("alter_sys", true)?;
            runpy.call_method("run_module", (module,), Some(&kwargs))?;
        } else {
            let module = py.import(module.as_str())?;
            let entry = module.getattr(func.as_str())?;
            entry.call0()?;
        }
        Ok(())
    })?;

    Ok(())
}

fn ensure_python_root(exe_dir: &Path) -> Result<PathBuf> {
    let python_root = exe_dir.join("python");
    if python_root.exists() {
        return Ok(python_root);
    }

    if embedded_payload::EMBEDDED_PAYLOAD.is_empty() {
        anyhow::bail!(
            "embedded Python not found at {} (expected a 'python' folder next to the binary)",
            python_root.display()
        );
    }

    let base_dir = if let Ok(dir) = env::var("PYEMBED_EXTRACT_DIR") {
        PathBuf::from(dir)
    } else {
        cache_dir()
            .unwrap_or_else(|| exe_dir.to_path_buf())
            .join("octobot-pyembed")
    };

    let target_dir = base_dir.join(embedded_payload::EMBEDDED_PAYLOAD_NAME);
    let marker = target_dir.join(".pyembed.ok");

    if !marker.exists() {
        if target_dir.exists() {
            fs::remove_dir_all(&target_dir).context("remove stale payload dir")?;
        }
        fs::create_dir_all(&target_dir).context("create payload dir")?;
        extract_payload(&target_dir)?;
        fs::write(&marker, b"ok").context("write marker")?;
    }

    let extracted_python = target_dir.join("python");
    if !extracted_python.exists() {
        anyhow::bail!(
            "embedded payload extracted but python folder missing at {}",
            extracted_python.display()
        );
    }

    Ok(extracted_python)
}

fn extract_payload(target_dir: &Path) -> Result<()> {
    let decoder = ZstdDecoder::with_buffer(embedded_payload::EMBEDDED_PAYLOAD)?;
    let mut archive = Archive::new(decoder);
    archive.unpack(target_dir).context("unpack embedded payload")?;
    Ok(())
}

fn load_config(path: &Path) -> Result<PyEmbedConfig> {
    let data = fs::read_to_string(path)
        .with_context(|| format!("read config {}", path.display()))?;
    let cfg: PyEmbedConfig = serde_json::from_str(&data)
        .with_context(|| format!("parse config {}", path.display()))?;
    Ok(cfg)
}

fn resolve_path(root: &Path, rel_or_abs: &str) -> PathBuf {
    let candidate = PathBuf::from(rel_or_abs);
    if candidate.is_absolute() {
        candidate
    } else {
        root.join(candidate)
    }
}

fn resolve_paths(root: &Path, entries: &[String]) -> Vec<PathBuf> {
    entries.iter().map(|p| resolve_path(root, p)).collect()
}

fn join_paths(paths: &[PathBuf]) -> Result<String> {
    env::join_paths(paths)
        .context("join PYTHONPATH")
        .map(|s| s.to_string_lossy().to_string())
}

fn build_argv(py: Python<'_>) -> Result<pyo3::Bound<'_, PyList>> {
    let args: Vec<String> = env::args().collect();
    Ok(PyList::new(py, args)?)
}
