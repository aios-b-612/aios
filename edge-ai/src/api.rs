//! JSON API of the Edge AI OS daemon: health, models, infer, benchmark, logs
//! and metrics, plus the HTML control panel at `/`.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use aios_core::{default_models_dir, gguf, pretty_bytes, sha256_hex};
use serde_json::json;

use crate::http::{Request, Response};
use crate::panel;
use crate::runtime::Runtime;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Build the request handler for a running daemon.
pub fn handler(
    runtime: Arc<Runtime>,
) -> impl Fn(&Request) -> Response + Send + Sync + 'static {
    move |req: &Request| handle(&runtime, req)
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn handle(rt: &Runtime, req: &Request) -> Response {
    match (req.method.as_str(), req.path.as_str()) {
        ("GET", "/") => Response::html(200, panel::index()),
        ("GET", "/api/health") => health(rt),
        ("GET", "/api/models") => models(rt),
        ("POST", "/api/infer") => infer(rt, req),
        ("GET", "/api/benchmark") => benchmark(rt, req),
        ("GET", "/api/logs") => logs(rt, req),
        ("GET", "/api/metrics") => metrics(rt),
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

fn infer(rt: &Runtime, req: &Request) -> Response {
    let body: serde_json::Value = match req.json() {
        Ok(v) => v,
        Err(e) => return Response::error(400, &e),
    };
    let Some(prompt) = body.get("prompt").and_then(|v| v.as_str()).map(str::to_string) else {
        return Response::error(400, "infer: missing \"prompt\"");
    };
    let max_tokens = body.get("max_tokens").and_then(|v| v.as_u64()).unwrap_or(64) as usize;
    let Some(model) = body
        .get("model")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .or_else(|| default_model_name(rt))
    else {
        return Response::error(503, "no model available (install one with 'ai install' or 'edge install')");
    };

    match rt.infer(&model, &prompt, max_tokens) {
        Ok(out) => {
            rt.log("info", format!("infer model={model} cached={} tps={:.2}", out.cached, out.tps));
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
    let count = if tail > 0 { tail.min(logs.len()) } else { logs.len() };
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