//! AIOS edge SDK: exposes `ai::load` / `model.generate`-style API for edge
//! applications. Thin facade over aios-core (placeholder for Phase Fase 4
//! runtime backend).

pub use aios_core::*;

/// Load a model by name from the local cache to the given runtime slot.
/// (Placeholder: real loading arrives with the CPU backend in Fase 4.)
pub fn load(name: &str) -> aios_core::Result<String> {
    Ok(format!("[placeholder] loaded {name}"))
}

pub fn generate(_loaded: &str, prompt: &str) -> aios_core::Result<String> {
    Ok(format!("[placeholder] echo: {prompt}"))
}