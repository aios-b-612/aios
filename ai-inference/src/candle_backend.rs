//! Candle CPU backend (ADR-003). Loads Llama-architecture quantized GGUFs
//! through candle-transformers `quantized_llama` and runs greedy generation
//! on the Candle CPU device. Tokenizer is a companion `tokenizer.json`.

use aios_core::{ComputeBackend, Error, Result};
use candle_core::{quantized::gguf_file, DType, Device, Tensor};
use candle_transformers::models::quantized_llama as qllama;
use std::path::Path;
use std::time::Instant;

/// Companion tokenizer file resolvers, tried in order relative to the GGUF.
const TOKENIZER_CANDIDATES: [&str; 2] = ["{dir}/{stem}.tokenizer.json", "{dir}/tokenizer.json"];

pub struct CandleBackend {
    device: Device,
    model_name: String,
    model_path: String,
    llama: Option<qllama::ModelWeights>,
    tokenizer: Option<tokenizers::Tokenizer>,
    last_tps: f64,
    load_time: std::time::Duration,
}

fn resolve_tokenizer(model_path: &Path) -> Option<std::path::PathBuf> {
    let dir = model_path.parent().unwrap_or_else(|| Path::new("."));
    let stem = model_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("model");
    for tmpl in TOKENIZER_CANDIDATES {
        let candidate = tmpl
            .replace("{dir}", &dir.display().to_string())
            .replace("{stem}", stem);
        let p = Path::new(&candidate);
        if p.is_file() {
            return Some(p.to_path_buf());
        }
    }
    None
}

impl CandleBackend {
    pub fn new() -> Result<Self> {
        let device = Device::Cpu;
        Ok(Self {
            device,
            model_name: String::new(),
            model_path: String::new(),
            llama: None,
            tokenizer: None,
            last_tps: 0.0,
            load_time: std::time::Duration::ZERO,
        })
    }
}

impl ComputeBackend for CandleBackend {
    fn name(&self) -> &'static str {
        "candle-cpu"
    }

    fn device(&self) -> &'static str {
        "CPU (Candle core)"
    }

    fn load_model(&mut self, path: &str) -> Result<()> {
        let path = Path::new(path);
        let tokenizer_path = resolve_tokenizer(path).ok_or_else(|| {
            Error::Msg(format!(
                "no tokenizer.json found next to {} (expected {}.tokenizer.json or tokenizer.json in the same dir)",
                path.display(),
                path.file_stem().and_then(|s| s.to_str()).unwrap_or("model")
            ))
        })?;

        let tokenizer = tokenizers::Tokenizer::from_file(&tokenizer_path)
            .map_err(|e| Error::Msg(format!("tokenizer: {e}")))?;

        let start = Instant::now();
        let mut file = std::fs::File::open(path)?;
        let content = gguf_file::Content::read(&mut file)
            .map_err(|e| Error::Msg(format!("gguf: {e}")))?;
        let llama = qllama::ModelWeights::from_gguf(content, &mut file, &self.device)
            .map_err(|e| Error::Msg(format!("llama: {e}")))?;
        self.load_time = start.elapsed();

        self.model_name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("model")
            .to_string();
        self.model_path = path.display().to_string();
        self.llama = Some(llama);
        self.tokenizer = Some(tokenizer);
        self.last_tps = 0.0;
        Ok(())
    }

    fn is_loaded(&self) -> bool {
        self.llama.is_some() && self.tokenizer.is_some()
    }

    fn generate(&mut self, prompt: &str, max_tokens: usize) -> Result<String> {
        let llama = self.llama.as_mut().ok_or_else(|| Error::Msg("no model loaded".into()))?;
        let tokenizer = self.tokenizer.as_ref().ok_or_else(|| Error::Msg("no tokenizer loaded".into()))?;

        let prompt_ids = tokenizer
            .encode(prompt, true)
            .map_err(|e| Error::Msg(format!("encode: {e}")))?
            .get_ids()
            .to_vec();
        let mut all: Vec<u32> = prompt_ids;
        let eos = tokenizer.token_to_id("</s>");
        let start = Instant::now();

        let mut out = String::new();
        let mut index_pos = 0usize;
        let mut generated = 0usize;
        for i in 0..max_tokens.max(1) {
            let context = if i > 0 { 1 } else { all.len() };
            let start_pos = all.len().saturating_sub(context);
            let ctxt = &all[start_pos..all.len()];
            let input = Tensor::new(ctxt, &self.device)
                .map_err(|e| Error::Msg(format!("tensor: {e}")))?
                .unsqueeze(0)
                .map_err(|e| Error::Msg(format!("unsqueeze: {e}")))?;
            let logits = llama
                .forward(&input, index_pos)
                .map_err(|e| Error::Msg(format!("forward: {e}")))?
                .squeeze(0)
                .map_err(|e| Error::Msg(format!("squeeze: {e}")))?
                .to_dtype(DType::F32)
                .map_err(|e| Error::Msg(format!("dtype: {e}")))?;
            let next_token = logits
                .argmax(0)
                .map_err(|e| Error::Msg(format!("argmax: {e}")))?
                .to_scalar::<u32>()
                .map_err(|e| Error::Msg(format!("scalar: {e}")))?;
            index_pos += ctxt.len();

            let prev_len = all.len();
            all.push(next_token);
            generated += 1;
            let fresh = &all[prev_len..all.len()];
            let text = tokenizer
                .decode(fresh, true)
                .map_err(|e| Error::Msg(format!("decode: {e}")))?;
            out.push_str(&text);

            if let Some(eos) = eos {
                if next_token == eos {
                    break;
                }
            }
        }
        self.last_tps = generated as f64 / start.elapsed().as_secs_f64();
        Ok(out)
    }

    fn tokens_per_second(&self) -> f64 {
        self.last_tps
    }
}

impl Default for CandleBackend {
    fn default() -> Self {
        CandleBackend::new().unwrap()
    }
}

/// Load time for the current model (last `load_model` call).
pub fn load_time(backend: &CandleBackend) -> std::time::Duration {
    backend.load_time
}

/// Model file currently loaded.
pub fn model_path(backend: &CandleBackend) -> &str {
    &backend.model_path
}

/// Model name (GGUF file stem) currently loaded.
pub fn model_name(backend: &CandleBackend) -> &str {
    &backend.model_name
}