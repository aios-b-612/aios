//! Model cache: discovery of installed GGUF models in a directory tree.

use crate::error::Result;
use crate::model::ModelMeta;
use std::path::{Path, PathBuf};

/// Default cache location baked into the AIOS images (see config/*.toml,
/// `/var/lib/ai/models`) and reused on the host for development.
pub const DEFAULT_MODELS_DIR: &str = "/var/lib/ai/models";

/// Recursively find `.gguf` files under `dir`.
pub fn find_models(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    if !dir.exists() {
        return Ok(out);
    }
    walk(dir, &mut out)?;
    Ok(out)
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            walk(&path, out)?;
        } else if path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.eq_ignore_ascii_case("gguf"))
            .unwrap_or(false)
        {
            out.push(path);
        }
    }
    Ok(())
}

/// Convenience wrapper: list installed models (metadata read from disk).
pub fn list_installed(dir: &Path) -> Result<Vec<ModelMeta>> {
    let mut out = Vec::new();
    for path in find_models(dir)? {
        match ModelMeta::from_path(&path) {
            Ok(m) => out.push(m),
            Err(e) => {
                // Broken file: surface it so users can clean up.
                out.push(ModelMeta {
                    name: path
                        .file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or("?")
                        .to_string(),
                    path: path.display().to_string(),
                    size_bytes: 0,
                    header: None,
                });
                let _ = e;
            }
        }
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}