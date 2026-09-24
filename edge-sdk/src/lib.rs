//! AIOS edge SDK: exposes `ai::load` / `model.generate`-style API for edge
//! applications. Thin facade over aios-core. `load` is functional in Fase 3
//! (resolves a model from the local registry/cache); `generate` becomes real
//! with the Fase 4 inference backend.

use std::fs;
use std::path::Path;

pub use aios_core::*;

/// A model resolved by [`load`]: path, size and integrity info.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadedModel {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub sha256: String,
    /// Whether the model is tracked in the registry (installed via `ai install`).
    pub registered: bool,
}

/// Resolve a model by name: prefers the registry, falls back to a plain
/// `<cache>/<name>.gguf` file. Fails if neither exists (or the registry
/// cannot be read).
pub fn load(name: &str) -> aios_core::Result<LoadedModel> {
    let reg = match Registry::load(default_registry_file()) {
        Ok(r) => r,
        Err(e) => return Err(e),
    };
    if let Some(e) = reg.find(name) {
        if fs::metadata(&e.path).is_ok() {
            return Ok(LoadedModel {
                name: name.to_string(),
                path: e.path.clone(),
                size_bytes: e.size_bytes,
                sha256: e.sha256.clone(),
                registered: true,
            });
        }
        return Err(Error::Msg(format!(
            "model '{name}' is registered but missing on disk: {}",
            e.path
        )));
    }

    let guess = cache_path_for(Path::new(&default_models_dir()), name);
    if guess.is_file() {
        let size_bytes = fs::metadata(&guess)?.len();
        return Ok(LoadedModel {
            name: name.to_string(),
            path: guess.display().to_string(),
            size_bytes,
            sha256: String::new(),
            registered: false,
        });
    }

    Err(Error::Msg(format!(
        "model '{name}' not found in registry or in {}",
        guess.display()
    )))
}

/// Generate a completion for `prompt`. (Placeholder: real loading arrives
/// with the CPU backend in Fase 4.)
pub fn generate(_loaded: &LoadedModel, prompt: &str) -> aios_core::Result<String> {
    Ok(format!("[placeholder] echo: {prompt}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn gguf_bytes() -> Vec<u8> {
        let mut b = Vec::new();
        b.extend_from_slice(b"GGUF");
        b.extend_from_slice(&1u32.to_le_bytes());
        b.extend_from_slice(&0u64.to_le_bytes());
        b.extend_from_slice(&0u64.to_le_bytes());
        b
    }

    fn setup() -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("aios-sdk-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn load_via_registry() {
        let dir = setup();
        let cache = dir.join("models");
        fs::create_dir_all(&cache).unwrap();
        let src = cache.join("m.gguf");
        fs::write(&src, gguf_bytes()).unwrap();

        let reg_path = dir.join("registry.tsv");
        let entry = aios_core::install_model(&src, &cache, "demo").unwrap();
        let mut reg = aios_core::Registry::load(reg_path.as_path()).unwrap();
        reg.add(entry);
        reg.save().unwrap();

        std::env::set_var("AIOS_REGISTRY", reg_path.as_path());
        std::env::set_var("AIOS_MODELS_DIR", cache.as_path());

        let m = load("demo").expect("load via registry");
        assert_eq!(m.name, "demo");
        assert!(m.registered);
        assert_eq!(m.size_bytes, 24);
        assert_eq!(m.sha256.len(), 64);
    }

    #[test]
    fn load_via_cache_file() {
        let dir = setup();
        let cache = dir.join("models");
        fs::create_dir_all(&cache).unwrap();
        fs::write(cache.join("tiny.gguf"), gguf_bytes()).unwrap();

        std::env::set_var("AIOS_MODELS_DIR", cache.as_path());
        std::env::set_var("AIOS_REGISTRY", dir.join("empty.tsv").as_path());

        let m = load("tiny").expect("load via cache file");
        assert_eq!(m.name, "tiny");
        assert!(!m.registered);
        assert_eq!(m.sha256, "");
    }

    #[test]
    fn load_missing_model_fails() {
        let dir = setup();
        std::env::set_var("AIOS_MODELS_DIR", dir.join("models").as_path());
        std::env::set_var("AIOS_REGISTRY", dir.join("empty.tsv").as_path());
        assert!(load("nope").is_err());
    }

    #[test]
    fn generate_placeholder() {
        let m = LoadedModel {
            name: "x".into(),
            path: "/dev/null".into(),
            size_bytes: 0,
            sha256: String::new(),
            registered: false,
        };
        let out = generate(&m, "hi").unwrap();
        assert!(out.contains("hi"));
    }
}