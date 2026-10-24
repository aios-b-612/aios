//! JSON API of the Edge AI OS daemon: health, models, infer, benchmark, logs
//! and metrics, plus the HTML control panel at `/`.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use aios_core::{default_models_dir, gguf, pretty_bytes, sha256_hex, Registry};
use serde_json::json;

use crate::http::{Request, Response};
use crate::panel;
use crate::runtime::Runtime;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Upload state for chunked model uploads
struct UploadState {
    chunks: HashMap<(String, usize), Vec<u8>>, // (model_name, chunk_index) -> data
    expected_chunks: HashMap<String, usize>,   // model_name -> total_chunks
    sha256: HashMap<String, String>,           // model_name -> expected sha256
    received_count: HashMap<String, usize>,    // model_name -> received chunks
}

impl UploadState {
    fn new() -> Self {
        Self {
            chunks: HashMap::new(),
            expected_chunks: HashMap::new(),
            sha256: HashMap::new(),
            received_count: HashMap::new(),
        }
    }
}

/// Build the request handler for a running daemon.
pub fn handler(runtime: Arc<Runtime>) -> impl Fn(&Request) -> Response + Send + Sync + 'static {
    let upload_state = Arc::new(Mutex::new(UploadState::new()));
    move |req: &Request| handle(&runtime, &upload_state, req)
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

/// Where the previous version of a model is kept so a failed deploy can be
/// rolled back. A dot-directory keeps it out of `find_models`, which walks
/// `.gguf` files, and therefore out of the model list.
fn backup_dir(models_dir: &Path) -> PathBuf {
    models_dir.join(".backup")
}

fn backup_path(models_dir: &Path, name: &str) -> PathBuf {
    backup_dir(models_dir).join(format!("{name}.gguf"))
}

/// Reject names that could escape the models directory. `install_model`
/// validates too, but the upload path builds paths before it gets there.
fn validate_model_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("empty model name".into());
    }
    if name.contains('/') || name.contains('\\') || name == "." || name == ".." {
        return Err(format!("invalid model name {name:?}"));
    }
    Ok(())
}

fn handle(rt: &Runtime, upload_state: &Arc<Mutex<UploadState>>, req: &Request) -> Response {
    match (req.method.as_str(), req.path.as_str()) {
        ("GET", "/") => Response::html(200, panel::index()),
        ("GET", "/api/health") => health(rt),
        ("GET", "/api/models") => models(rt),
        ("POST", "/api/infer") => infer(rt, req),
        ("GET", "/api/benchmark") => benchmark(rt, req),
        ("GET", "/api/logs") => logs(rt, req),
        ("GET", "/api/metrics") => metrics(rt),
        // OpenAI-compatible endpoints
        ("POST", "/v1/chat/completions") => chat_completions(rt, req),
        ("GET", "/v1/models") => openai_models(rt),
        // Model upload endpoints (chunked multipart)
        ("POST", "/api/models/upload") => upload_chunk(upload_state, req),
        ("POST", "/api/models/upload/finalize") => upload_finalize(rt, upload_state, req),
        ("POST", "/api/models/rollback") => rollback_model(rt, req),
        (m, p) => Response::error(404, &format!("not found: {m} {p}")),
    }
}

fn health(rt: &Runtime) -> Response {
    Response::json(
        200,
        &json!({
            "status": "ok",
            "service": "edge-ai",
            "version": VERSION,
            "pid": std::process::id(),
            "uptime_s": rt.uptime_s(),
            "models_dir": default_models_dir(),
        }),
    )
}

fn models(rt: &Runtime) -> Response {
    let metas = match rt.list_models() {
        Ok(m) => m,
        Err(e) => return Response::error(500, &e),
    };
    let list: Vec<_> = metas
        .iter()
        .map(|m| {
            let arch = m
                .header
                .as_ref()
                .and_then(|h| h.string("general.architecture"))
                .unwrap_or_default();
            json!({
                "name": m.name,
                "path": m.path,
                "size_bytes": m.size_bytes,
                "size": pretty_bytes(m.size_bytes),
                "architecture": arch,
            })
        })
        .collect();
    Response::json(200, &json!({ "count": list.len(), "models": list }))
}

/// OpenAI-compatible model listing: GET /v1/models.
/// Mirrors /api/models but in the OpenAI `list.models` envelope so SDKs
/// (openai-python, langchain, litellm) can discover served models.
fn openai_models(rt: &Runtime) -> Response {
    let metas = match rt.list_models() {
        Ok(m) => m,
        Err(e) => return Response::error(500, &e),
    };
    let created = now() as i64;
    let data: Vec<_> = metas
        .iter()
        .map(|m| {
            json!({
                "id": m.name,
                "object": "model",
                "created": created,
                "owned_by": "aios",
            })
        })
        .collect();
    Response::json(200, &json!({ "object": "list", "data": data }))
}

fn infer(rt: &Runtime, req: &Request) -> Response {
    let body: serde_json::Value = match req.json() {
        Ok(v) => v,
        Err(e) => return Response::error(400, &e),
    };
    let Some(prompt) = body
        .get("prompt")
        .and_then(|v| v.as_str())
        .map(str::to_string)
    else {
        return Response::error(400, "infer: missing \"prompt\"");
    };
    let max_tokens = body
        .get("max_tokens")
        .and_then(|v| v.as_u64())
        .unwrap_or(64) as usize;
    let Some(model) = body
        .get("model")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .or_else(|| default_model_name(rt))
    else {
        return Response::error(
            503,
            "no model available (install one with 'ai install' or 'edge install')",
        );
    };

    match rt.infer(&model, &prompt, max_tokens) {
        Ok(out) => {
            rt.log(
                "info",
                format!(
                    "infer model={model} cached={} tps={:.2}",
                    out.cached, out.tps
                ),
            );
            Response::json(
                200,
                &json!({
                    "model": model,
                    "prompt": prompt,
                    "max_tokens": max_tokens,
                    "text": out.text,
                    "tokens_per_second": out.tps,
                    "load_ms": out.load_ms,
                    "cached": out.cached,
                }),
            )
        }
        Err(e) => Response::error(500, &e),
    }
}

fn default_model_name(rt: &Runtime) -> Option<String> {
    rt.list_models()
        .ok()?
        .into_iter()
        .max_by_key(|m| m.size_bytes)
        .map(|m| m.name)
}

fn benchmark(rt: &Runtime, req: &Request) -> Response {
    let model = req
        .query
        .get("model")
        .filter(|s| !s.is_empty())
        .cloned()
        .unwrap_or_else(|| default_model_name(rt).unwrap_or_default());
    let tokens = req
        .query
        .get("tokens")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(0);

    let path = match rt.resolve_model(&model) {
        Ok(p) => p,
        Err(e) => return Response::error(404, &e),
    };
    let size_bytes = match std::fs::metadata(&path) {
        Ok(md) => md.len(),
        Err(e) => return Response::error(500, &format!("metadata {path}: {e}")),
    };

    let parse_ms = {
        let start = std::time::Instant::now();
        let mut f = match std::fs::File::open(&path) {
            Ok(f) => f,
            Err(e) => return Response::error(500, &format!("open {path}: {e}")),
        };
        if let Err(e) = gguf::parse_header(&mut f) {
            return Response::error(500, &format!("gguf parse {path}: {e}"));
        }
        start.elapsed().as_millis()
    };
    let (sha256, sha_ms) = {
        let start = std::time::Instant::now();
        let f = match std::fs::File::open(&path) {
            Ok(f) => f,
            Err(e) => return Response::error(500, &format!("open {path}: {e}")),
        };
        match sha256_hex(std::io::BufReader::new(f)) {
            Ok(h) => (h, start.elapsed().as_millis()),
            Err(e) => return Response::error(500, &format!("sha256 {path}: {e}")),
        }
    };

    let mut resp = json!({
        "model": model,
        "path": path,
        "size_bytes": size_bytes,
        "size": pretty_bytes(size_bytes),
        "gguf_parse_ms": parse_ms,
        "sha256_ms": sha_ms,
        "sha256": sha256,
    });

    if tokens > 0 {
        match rt.infer(&model, "Hello", tokens) {
            Ok(out) => {
                resp["tokens_per_second"] = json!(out.tps);
                resp["tokens"] = json!(tokens);
                resp["load_ms"] = json!(out.load_ms);
                resp["cached"] = json!(out.cached);
            }
            Err(e) => {
                resp["tokens_error"] = json!(e);
            }
        }
    }
    Response::json(200, &resp)
}

fn logs(rt: &Runtime, req: &Request) -> Response {
    let tail = req
        .query
        .get("tail")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(0);
    let logs = rt.logs();
    let count = if tail > 0 {
        tail.min(logs.len())
    } else {
        logs.len()
    };
    let slice = if count == 0 {
        &logs[..]
    } else {
        &logs[logs.len() - count..]
    };
    Response::json(200, &json!({ "count": count, "logs": slice }))
}

fn metrics(rt: &Runtime) -> Response {
    let sample = rt.last_sample().unwrap_or_default();
    let stats = rt.stats();
    let history = rt.history();
    let models_count = rt.list_models().map(|m| m.len()).unwrap_or(0);
    Response::json(
        200,
        &json!({
            "ts": now(),
            "system": {
                "cpu_percent": sample.cpu_percent,
                "mem_used_mb": sample.mem_used_mb,
                "mem_total_mb": sample.mem_total_mb,
                "net_rx_kbps": sample.net_rx_kbps,
                "net_tx_kbps": sample.net_tx_kbps,
                "parallelism": crate::metrics::parallelism(),
                "uptime_s": rt.uptime_s(),
            },
            "models_count": models_count,
            "infer": {
                "requests": stats.requests,
                "errors": stats.errors,
                "tokens": stats.tokens,
                "total_ms": stats.total_ms,
                "avg_latency_ms": stats.avg_latency_ms(),
                "last_tps": stats.last_tps,
            },
            "history": history,
        }),
    )
}

/// Parse a simple multipart form field from the request body.
/// Returns the value of the first non-file field with this name.
///
/// Takes no boundary: it locates the part by its `name="..."` header, which
/// is what the daemon's chunk protocol actually needs, and the parameter was
/// unused. A boundary-aware parser would be stricter — this would also match a
/// *file* part called `model_name` — but the protocol never sends one, and
/// pretending to check the boundary here without doing so would be worse.
fn parse_multipart_field(body: &[u8], field_name: &str) -> Option<String> {
    let body_str = String::from_utf8_lossy(body);
    let field_marker = format!("name=\"{}\"\r\n\r\n", field_name);
    body_str.find(&field_marker).and_then(|pos| {
        let start = pos + field_marker.len();
        body_str[start..]
            .split_once("\r\n")
            .map(|(v, _)| v.to_string())
    })
}

/// Parse the binary chunk out of a multipart body.
///
/// The first part of every upload is the `chunk` field, so the data sits
/// between the end of that part's headers and the next `\r\n--` boundary.
/// The earlier implementation searched for `\r\n--boundary\r\n` first, which
/// only matches the separator *after* the first part, and then treated the
/// text fields that follow it as the chunk data. That is why a real upload
/// assembled a chunk that did not match the file the client sent.
fn parse_multipart_chunk(body: &[u8], _boundary: &str) -> Option<Vec<u8>> {
    let header_end = body.windows(4).position(|w| w == b"\r\n\r\n")?;
    let data_start = header_end + 4;
    let remaining = &body[data_start..];
    let end = remaining
        .windows(4)
        .position(|w| w == b"\r\n--")
        .unwrap_or(remaining.len());
    let mut chunk = remaining[..end].to_vec();
    if chunk.ends_with(b"\r\n") {
        chunk.truncate(chunk.len() - 2);
    }
    Some(chunk)
}

fn upload_chunk(upload_state: &Arc<Mutex<UploadState>>, req: &Request) -> Response {
    // The boundary lives in the request header, not in the body: a real
    // multipart body starts with `--boundary`, so reading the first body line
    // as a header always produced "missing multipart boundary".
    let content_type = req.headers.get("content-type").cloned().unwrap_or_default();

    let boundary = content_type
        .split("boundary=")
        .nth(1)
        .and_then(|s| s.split_whitespace().next())
        .unwrap_or("");

    if boundary.is_empty() {
        return Response::error(400, "missing multipart boundary");
    }

    // Parse form fields
    let model_name = parse_multipart_field(&req.body, "model_name").unwrap_or_default();
    let sha256 = parse_multipart_field(&req.body, "sha256").unwrap_or_default();
    let chunk_index = parse_multipart_field(&req.body, "chunk_index")
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let total_chunks = parse_multipart_field(&req.body, "total_chunks")
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    // Parse chunk data
    let chunk_data = parse_multipart_chunk(&req.body, boundary).unwrap_or_default();

    if model_name.is_empty() || sha256.is_empty() || total_chunks == 0 {
        return Response::error(
            400,
            "missing required fields: model_name, sha256, total_chunks",
        );
    }

    let mut state = match upload_state.lock() {
        Ok(s) => s,
        Err(_) => return Response::error(500, "upload state lock failed"),
    };

    // Initialize on first chunk
    if chunk_index == 0 {
        state
            .expected_chunks
            .insert(model_name.clone(), total_chunks);
        state.sha256.insert(model_name.clone(), sha256);
        state.received_count.insert(model_name.clone(), 0);
    }

    state
        .chunks
        .insert((model_name.clone(), chunk_index), chunk_data);
    *state.received_count.get_mut(&model_name).unwrap_or(&mut 0) += 1;

    Response::json(
        200,
        &json!({ "status": "chunk received", "chunk_index": chunk_index }),
    )
}

fn upload_finalize(
    rt: &Runtime,
    upload_state: &Arc<Mutex<UploadState>>,
    req: &Request,
) -> Response {
    let body: serde_json::Value = match req.json() {
        Ok(v) => v,
        Err(e) => return Response::error(400, &e),
    };

    let model_name = match body.get("model_name").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => return Response::error(400, "missing model_name"),
    };
    let expected_sha256 = match body.get("sha256").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => return Response::error(400, "missing sha256"),
    };
    let total_chunks = match body.get("total_chunks").and_then(|v| v.as_u64()) {
        Some(n) => n as usize,
        None => return Response::error(400, "missing total_chunks"),
    };

    let mut state = match upload_state.lock() {
        Ok(s) => s,
        Err(_) => return Response::error(500, "upload state lock failed"),
    };

    // Verify all chunks received
    let received = state.received_count.get(&model_name).copied().unwrap_or(0);
    if received != total_chunks {
        return Response::error(
            400,
            &format!("incomplete upload: {}/{} chunks", received, total_chunks),
        );
    }

    // Assemble model file
    let mut model_data = Vec::new();
    for i in 0..total_chunks {
        if let Some(chunk) = state.chunks.remove(&(model_name.clone(), i)) {
            model_data.extend_from_slice(&chunk);
        } else {
            return Response::error(500, &format!("missing chunk {}", i));
        }
    }

    // Verify SHA-256
    let computed_sha256 = match aios_core::checksum::sha256_hex(model_data.as_slice()) {
        Ok(s) => s,
        Err(e) => return Response::error(500, &format!("sha256 compute failed: {e}")),
    };

    if computed_sha256 != expected_sha256 {
        return Response::error(
            400,
            &format!(
                "sha256 mismatch: expected {} got {}",
                expected_sha256, computed_sha256
            ),
        );
    }

    // Save to a temporary file first. Writing straight to the destination and
    // then calling `install_model` on it is the same-path case that used to
    // truncate the model (fs::copy opens the destination with O_TRUNC).
    if let Err(e) = validate_model_name(&model_name) {
        return Response::error(400, &e);
    }
    let models_dir = PathBuf::from(aios_core::default_models_dir());
    if let Err(e) = std::fs::create_dir_all(&models_dir) {
        return Response::error(500, &format!("create models dir failed: {e}"));
    }
    let dest = aios_core::cache_path_for(&models_dir, &model_name);
    let temp = models_dir.join(format!(".upload-{model_name}.part"));
    if let Err(e) = std::fs::write(&temp, &model_data) {
        return Response::error(500, &format!("write model failed: {e}"));
    }

    // Keep the previous version so a failed health check can be rolled back.
    // Rename rather than copy: a 4 GB model would otherwise be duplicated on
    // a device that has little free space to begin with.
    let backup = backup_path(&models_dir, &model_name);
    let had_previous = dest.is_file();
    if had_previous {
        if let Err(e) = std::fs::create_dir_all(backup_dir(&models_dir)) {
            let _ = std::fs::remove_file(&temp);
            return Response::error(500, &format!("create backup dir failed: {e}"));
        }
        let _ = std::fs::remove_file(&backup);
        if let Err(e) = std::fs::rename(&dest, &backup) {
            let _ = std::fs::remove_file(&temp);
            return Response::error(500, &format!("backup previous model failed: {e}"));
        }
    }

    // Register in aios-core registry. `install_model` copies the temp file
    // into the cache and validates the GGUF header.
    let entry = match aios_core::install_model(&temp, &models_dir, &model_name) {
        Ok(e) => {
            let _ = std::fs::remove_file(&temp);
            e
        }
        Err(e) => {
            let _ = std::fs::remove_file(&temp);
            if had_previous {
                let _ = std::fs::rename(&backup, &dest);
            }
            return Response::error(500, &format!("registry install failed: {e}"));
        }
    };

    // Add to runtime's model cache
    if let Err(e) = rt.register_model(entry) {
        return Response::error(500, &format!("runtime register failed: {e}"));
    }

    // Cleanup upload state
    state.expected_chunks.remove(&model_name);
    state.sha256.remove(&model_name);
    state.received_count.remove(&model_name);

    Response::json(
        200,
        &json!({
            "status": "model installed",
            "model": model_name,
            "path": dest.display().to_string(),
            "size": model_data.len(),
            "sha256": computed_sha256,
            "backup": had_previous
        }),
    )
}

/// Restore the model that was replaced by the last deploy.
///
/// The daemon keeps one backup per model name (`<models>/.backup/<name>.gguf`).
/// A deploy that transfers but fails its health check leaves the device with a
/// model it cannot serve; this route puts the previous file and registry entry
/// back so the device returns to a working state.
fn rollback_model(rt: &Runtime, req: &Request) -> Response {
    let body: serde_json::Value = match req.json() {
        Ok(v) => v,
        Err(e) => return Response::error(400, &e),
    };
    let model_name = match body.get("name").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => return Response::error(400, "missing name"),
    };
    if let Err(e) = validate_model_name(&model_name) {
        return Response::error(400, &e);
    }

    let models_dir = PathBuf::from(aios_core::default_models_dir());
    let backup = backup_path(&models_dir, &model_name);
    if !backup.is_file() {
        return Response::error(
            404,
            &format!("no backup for model '{model_name}'; nothing to roll back"),
        );
    }

    let dest = aios_core::cache_path_for(&models_dir, &model_name);
    let _ = std::fs::remove_file(&dest);
    if let Ok(mut reg) = Registry::load(aios_core::default_registry_file()) {
        if reg.remove(&model_name) {
            let _ = reg.save();
        }
    }

    // Move the backup out of the way first: install_model must not see
    // src == dest (that is the same-path case that truncates the file).
    let temp = models_dir.join(format!(".rollback-{model_name}.part"));
    if let Err(e) = std::fs::rename(&backup, &temp) {
        return Response::error(500, &format!("restore backup failed: {e}"));
    }
    let entry = match aios_core::install_model(&temp, &models_dir, &model_name) {
        Ok(e) => {
            let _ = std::fs::remove_file(&temp);
            e
        }
        Err(e) => {
            let _ = std::fs::rename(&temp, &backup);
            return Response::error(500, &format!("reinstall backup failed: {e}"));
        }
    };
    if let Err(e) = rt.register_model(entry.clone()) {
        return Response::error(500, &format!("runtime register failed: {e}"));
    }

    Response::json(
        200,
        &json!({
            "status": "rolled_back",
            "model": entry.name,
            "path": entry.path,
            "sha256": entry.sha256,
            "size": entry.size_bytes
        }),
    )
}

/// OpenAI-compatible chat completions endpoint.
/// POST /v1/chat/completions
/// Body: { model, messages[], temperature?, max_tokens?, stream? }
fn chat_completions(rt: &Runtime, req: &Request) -> Response {
    let body: serde_json::Value = match req.json() {
        Ok(v) => v,
        Err(e) => return Response::error(400, &e),
    };

    let model = match body.get("model").and_then(|v| v.as_str()) {
        Some(s) => s.to_string(),
        None => return Response::error(400, "missing model"),
    };

    let messages = match body.get("messages").and_then(|v| v.as_array()) {
        Some(arr) => arr,
        None => return Response::error(400, "missing messages array"),
    };

    if messages.is_empty() {
        return Response::error(400, "messages array cannot be empty");
    }

    // Convert OpenAI messages into the chat template the model was trained
    // with. TinyLlama-1.1B-Chat (Zephyr variant) uses plain SentencePiece
    // markers as text — there are no `<|start_header_id|>` tokens in the
    // vocab: the markers are plain words that get BPE-split, and turns are
    // terminated by `</s>`. Template:
    //   <|system|>\n{system}</s>\n<|user|>\n{user}</s>\n<|assistant|>\n
    let mut prompt = String::new();
    for msg in messages {
        let role = msg.get("role").and_then(|v| v.as_str()).unwrap_or("user");
        let content = msg.get("content").and_then(|v| v.as_str()).unwrap_or("");
        match role {
            "system" => prompt.push_str(&format!("<|system|>\n{content}</s>\n")),
            "user" => prompt.push_str(&format!("<|user|>\n{content}</s>\n")),
            "assistant" => prompt.push_str(&format!("<|assistant|>\n{content}</s>\n")),
            _ => prompt.push_str(&format!("<|user|>\n{content}</s>\n")),
        }
    }
    prompt.push_str("<|assistant|>\n");

    let max_tokens = body
        .get("max_tokens")
        .and_then(|v| v.as_u64())
        .unwrap_or(256) as usize;

    // Temperature is not supported by greedy generation; ignore for now
    let _temperature = body.get("temperature").and_then(|v| v.as_f64());

    // Check if streaming is requested
    let stream = body
        .get("stream")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let created = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    if stream {
        // Streaming: the runtime iterator yields tokens as the model emits
        // them; the HTTP layer frames each as an SSE event and flushes.
        let token_iter = match rt.infer_stream(&model, &prompt, max_tokens) {
            Ok(s) => s,
            Err(e) => return Response::error(500, &e),
        };

        let id = format!("chatcmpl-{}", uuid::Uuid::new_v4().simple());
        let model = model.clone();

        let framed = token_iter.map(move |token| {
            let chunk = json!({
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [{
                    "index": 0,
                    "delta": { "content": token },
                    "finish_reason": null
                }]
            });
            chunk.to_string()
        });

        return Response::sse_stream(200, Box::new(framed));
    }

    // Non-streaming response
    let out = match rt.infer(&model, &prompt, max_tokens) {
        Ok(o) => o,
        Err(e) => return Response::error(500, &e),
    };

    let created = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    Response::json(
        200,
        &json!({
            "id": format!("chatcmpl-{}", uuid::Uuid::new_v4().simple()),
            "object": "chat.completion",
            "created": created,
            "model": model,
            "choices": [{
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": out.text
                },
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": prompt.len() / 4,
                "completion_tokens": out.text.len() / 4,
                "total_tokens": (prompt.len() + out.text.len()) / 4
            }
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gguf(tag: u8) -> Vec<u8> {
        let mut b = Vec::new();
        b.extend_from_slice(b"GGUF");
        b.extend_from_slice(&1u32.to_le_bytes());
        b.extend_from_slice(&0u64.to_le_bytes()); // tensor count
        b.extend_from_slice(&0u64.to_le_bytes()); // metadata kv count
        b.push(tag);
        b
    }

    fn request(body: &str) -> Request {
        Request {
            method: "POST".into(),
            path: "/api/models/rollback".into(),
            query: HashMap::new(),
            headers: HashMap::new(),
            body: body.as_bytes().to_vec(),
        }
    }

    #[test]
    fn validate_model_name_rejects_path_escapes() {
        for bad in ["", ".", "..", "../x", "a/b", "a\\b"] {
            assert!(
                validate_model_name(bad).is_err(),
                "{bad:?} must be rejected"
            );
        }
        assert!(validate_model_name("tinyllama-1.1b.Q4_K_M").is_ok());
    }

    #[test]
    fn rollback_restores_the_previous_model() {
        // This is the only test in this binary that reads the two env vars,
        // and no other edge-ai test touches them.
        let root = std::env::temp_dir().join(format!("aios-api-rollback-{}", std::process::id()));
        let models = root.join("models");
        std::fs::create_dir_all(&models).unwrap();
        std::env::set_var("AIOS_MODELS_DIR", &models);
        std::env::set_var("AIOS_REGISTRY", root.join("registry.tsv"));

        let name = "demo";
        let dest = aios_core::cache_path_for(&models, name);
        let previous = gguf(1);
        let replacement = gguf(2);
        std::fs::write(&dest, &previous).unwrap();

        let rt = Runtime::new();

        // No backup: the route must say so instead of pretending it rolled
        // back.
        let resp = rollback_model(&rt, &request(r#"{"name":"demo"}"#));
        assert_eq!(resp.status, 404);

        // Simulate what upload_finalize does before installing a replacement.
        std::fs::create_dir_all(backup_dir(&models)).unwrap();
        std::fs::rename(&dest, backup_path(&models, name)).unwrap();
        std::fs::write(&dest, &replacement).unwrap();

        let resp = rollback_model(&rt, &request(r#"{"name":"demo"}"#));
        assert_eq!(
            resp.status,
            200,
            "body: {}",
            String::from_utf8_lossy(&resp.body)
        );
        assert_eq!(std::fs::read(&dest).unwrap(), previous);
        assert!(!backup_path(&models, name).exists());

        let _ = std::fs::remove_dir_all(&root);
    }
}
