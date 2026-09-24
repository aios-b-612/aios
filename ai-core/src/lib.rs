//! aios-core: AIOS shared AI core (runtime abstraction, model metadata,
//! GGUF parsing, cache, checksum, registry).
//!
//! Design contracts (see docs/DECISIONS.md ADR-011): pure Rust, no OS-UI
//! dependencies; platform-specific bits live behind feature gates. This
//! initial version is dependency-free so it cross-compiles cleanly for the
//! `*-unknown-redox` targets.

pub mod cache;
pub mod checksum;
pub mod error;
pub mod gguf;
pub mod model;
pub mod registry;

pub use cache::{list_installed, find_models, DEFAULT_MODELS_DIR};
pub use checksum::{sha256_hex, Sha256};
pub use error::{Error, Result};
pub use gguf::{GgufHeader, Value, ValueType};
pub use model::{pretty_bytes, ModelMeta};
pub use registry::{Registry, RegistryEntry, DEFAULT_REGISTRY_FILE};