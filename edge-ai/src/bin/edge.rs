//! `edge`: Edge AI OS CLI (Fase 5). Talks to the local daemon over HTTP.
//!
//!   edge status                 daemon health + metric summary
//!   edge models                 list installed models
//!   edge run <model>            [--prompt TEXT] [--max-tokens N] [--json]
//!   edge benchmark              [--model M] [--tokens N]
//!   edge logs                   [--tail N]
//!   edge monitor                [--json]  (ai-monitor)
//!   edge serve                  [--host H] [--port P] [--model M]
//!   edge install <file.gguf>   [name]
//!   edge remove <name>
//!   edge devices | update       (Fase 7 stubs)
//!   edge help
//!
//! Daemon address: env `EDGE_BASE_URL` or `127.0.0.1:8989`.

use std::process::exit;

use edge_ai::http::Client;
use serde_json::{json, Value};

const USAGE: &str = "\
usage:
  edge status
  edge models
  edge run <model> [--prompt TEXT] [--max-tokens N] [--json]
  edge benchmark [--model M] [--tokens N]
  edge logs [--tail N]
  edge monitor [--json]
  edge serve [--host H] [--port P] [--model M]
  edge install <file.gguf> [name]
  edge remove <name>
  edge devices
  edge update
  edge help";

fn base_url() -> String {
    std::env::var("EDGE_BASE_URL").unwrap_or_else(|_| edge_ai::DEFAULT_CLIENT_BASE.to_string())
}

fn client() -> Client {
    match Client::from_base(&base_url()) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("edge: {e}");
            exit(2);
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(|s| s.as_str()) {
        None => {
            eprintln!("{USAGE}");
            2
        }
        Some("status") => cmd_status(&args[1..]),
        Some("models") => cmd_models(&args[1..]),
        Some("run") => cmd_run(&args[1..]),
        Some("benchmark") => cmd_benchmark(&args[1..]),
        Some("logs") => cmd_logs(&args[1..]),
        Some("monitor") => cmd_monitor(&args[1..]),
        Some("serve") => cmd_serve(&args[1..]),
        Some("install") => cmd_install(&args[1..]),
        Some("remove") => cmd_remove(&args[1..]),
        Some("devices" | "update") => cmd_fase7(args[0].as_str()),
        Some("help" | "-h" | "--help") => {
            println!("{USAGE}");
            0
        }
        Some(other) => {
            eprintln!("unknown command: {other}\n{USAGE}");
            2
        }
    };
    exit(code);
}

fn get_json(c: &Client, path: &str) -> Result<Value, String> {
    let (status, body) = c.get(path)?;
    let v: Value = serde_json::from_slice(&body).map_err(|e| format!("parse response: {e}"))?;
    if status >= 400 {
        return Err(v
            .get("error")
            .and_then(|e| e.as_str())
            .unwrap_or(&format!("http {status}"))
            .to_string());
    }
    Ok(v)
}

fn cmd_status(args: &[String]) -> i32 {
    if let Some(a) = args.first() {
        if a == "--help" || a == "-h" {
            println!("usage: edge status");
            return 0;
        }
    }
    let c = client();
    match get_json(&c, "/api/health") {
        Ok(h) => {
            println!(
                "edge-ai {}  status={}  uptime={}s  pid={}",
                opt(&h["version"]),
                opt(&h["status"]),
                h["uptime_s"],
                h["pid"]
            );
            println!("models dir: {}", opt(&h["models_dir"]));
            match get_json(&c, "/api/metrics") {
                Ok(m) => {
                    let s = &m["system"];
                    print!("cpu {}%  mem {} MB", opt(&s["cpu_percent"]), opt(&s["mem_used_mb"]));
                    let inf = &m["infer"];
                    println!(
                        "   infer: req={} err={} tok={} avg={}ms last={}t/s",
                        inf["requests"], inf["errors"], inf["tokens"], opt(&inf["avg_latency_ms"]), opt(&inf["last_tps"])
                    );
                    println!("models installed: {}", m["models_count"]);
                }
                Err(e) => eprintln!("  metrics: {e}"),
            }
            0
        }
        Err(e) => {
            eprintln!("edge: daemon unreachable at {}: {e}", base_url());
            1
        }
    }
}

fn cmd_models(args: &[String]) -> i32 {
    if args.first().map(|s| s == "--help").unwrap_or(false) {
        println!("usage: edge models");
        return 0;
    }
    let c = client();
    match get_json(&c, "/api/models") {
        Ok(m) => {
            println!("{} model(s):", m["count"]);
            for mdl in m["models"].as_array().unwrap_or(&vec![]) {
                println!(
                    "  {:<24} {:<16} {}",
                    opt(&mdl["name"]),
                    opt(&mdl["architecture"]),
                    opt(&mdl["size"])
                );
            }
            if m["count"].as_u64().unwrap_or(0) == 0 {
                println!("  (none — install one with 'edge install' or 'ai install')");
            }
            0
        }
        Err(e) => {
            eprintln!("edge: {e}");
            1
        }
    }
}

fn cmd_run(args: &[String]) -> i32 {
    let Some(model) = args.first() else {
        eprintln!("usage: edge run <model> [--prompt TEXT] [--max-tokens N] [--json]");
        return 2;
    };
    if model == "--help" || model == "-h" {
        println!("usage: edge run <model> [--prompt TEXT] [--max-tokens N] [--json]");
        return 0;
    }
    let mut prompt = "Hello".to_string();
    let mut max_tokens = 64usize;
    let mut json = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--prompt" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--prompt requires a value");
                    return 2;
                }
                prompt = args[i].clone();
            }
            "--max-tokens" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--max-tokens requires a number");
                    return 2;
                }
                match args[i].parse() {
                    Ok(n) => max_tokens = n,
                    Err(_) => {
                        eprintln!("--max-tokens expects a number");
                        return 2;
                    }
                }
            }
            "--json" => json = true,
            other => {
                eprintln!("unexpected argument: {other}");
                return 2;
            }
        }
        i += 1;
    }
    let c = client();
    let body = json!({ "model": model, "prompt": prompt, "max_tokens": max_tokens });
    match c.post_json("/api/infer", &body) {
        Ok((status, resp)) => {
            let v: Value = match serde_json::from_slice(&resp) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("edge: parse response: {e}");
                    return 1;
                }
            };
            if status >= 400 {
                eprintln!(
                    "edge: {}",
                    v.get("error").and_then(|e| e.as_str()).unwrap_or("infer failed")
                );
                return 1;
            }
if json {
                println!("{}", v);
            } else {
                let tps = v["tokens_per_second"].as_f64().unwrap_or(0.0);
                println!("{}", opt(&v["text"]));
                eprintln!(
                    "==> {}  {tps:.2} tokens/s (load {} ms, cached {})",
                    opt(&v["model"]),
                    v["load_ms"],
                    v["cached"]
                );
            }
            0
        }
        Err(e) => {
            eprintln!("edge: daemon unreachable at {}: {e}", base_url());
            1
        }
    }
}

fn cmd_benchmark(args: &[String]) -> i32 {
    let mut model = String::new();
    let mut tokens = 0usize;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--model" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--model requires a value");
                    return 2;
                }
                model = args[i].clone();
            }
            "--tokens" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--tokens requires a number");
                    return 2;
                }
                match args[i].parse() {
                    Ok(n) => tokens = n,
                    Err(_) => {
                        eprintln!("--tokens expects a number");
                        return 2;
                    }
                }
            }
            "--help" | "-h" => {
                println!("usage: edge benchmark [--model M] [--tokens N]");
                return 0;
            }
            other => {
                eprintln!("unexpected argument: {other}");
                return 2;
            }
        }
        i += 1;
    }
    let mut path = "/api/benchmark?".to_string();
    let mut first = true;
    if !model.is_empty() {
        path.push_str(&format!("model={model}"));
        first = false;
    }
    if tokens > 0 {
        if !first {
            path.push('&');
        }
        path.push_str(&format!("tokens={tokens}"));
    }
    let c = client();
    match get_json(&c, &path) {
        Ok(b) => {
            println!("model:       {}", opt(&b["model"]));
            println!("size:        {}", opt(&b["size"]));
            println!("gguf parse:  {} ms", b["gguf_parse_ms"]);
            println!("sha256:      {} ms  {}", b["sha256_ms"], b["sha256"].as_str().map(|s| &s[..16]).unwrap_or(""));
            if let Some(tps) = b["tokens_per_second"].as_f64() {
                println!("infer:       {tps:.2} tokens/s ({} tok, load {} ms, cached {})", b["tokens"], b["load_ms"], b["cached"]);
            } else if let Some(e) = b["tokens_error"].as_str() {
                println!("infer:       skipped ({e})");
            }
            0
        }
        Err(e) => {
            eprintln!("edge: {e}");
            1
        }
    }
}

fn cmd_logs(args: &[String]) -> i32 {
    let mut tail = 0usize;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--tail" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--tail requires a number");
                    return 2;
                }
                match args[i].parse() {
                    Ok(n) => tail = n,
                    Err(_) => {
                        eprintln!("--tail expects a number");
                        return 2;
                    }
                }
            }
            "--help" | "-h" => {
                println!("usage: edge logs [--tail N]");
                return 0;
            }
            other => {
                eprintln!("unexpected argument: {other}");
                return 2;
            }
        }
        i += 1;
    }
    let mut path = "/api/logs".to_string();
    if tail > 0 {
        path.push_str(&format!("?tail={tail}"));
    }
    let c = client();
    match get_json(&c, &path) {
        Ok(l) => {
            if l["count"].as_u64().unwrap_or(0) == 0 {
                println!("(no log entries yet)");
                return 0;
            }
            for e in l["logs"].as_array().unwrap_or(&vec![]) {
                println!("[{}] {}", opt(&e["level"]), opt(&e["msg"]));
            }
            0
        }
        Err(e) => {
            eprintln!("edge: {e}");
            1
        }
    }
}

fn cmd_monitor(args: &[String]) -> i32 {
    let json = args.iter().any(|a| a == "--json");
    if args.iter().any(|a| a == "--help" || a == "-h") {
        println!("usage: edge monitor [--json]");
        return 0;
    }
    let c = client();
    match get_json(&c, "/api/metrics") {
        Ok(m) => {
            if json {
                println!("{}", m);
                return 0;
            }
            let s = &m["system"];
            let inf = &m["infer"];
            println!("AIOS ai-monitor  ts={}", m["ts"]);
            println!("  system:  cpu {}%   mem {} MB / {} MB", opt(&s["cpu_percent"]), opt(&s["mem_used_mb"]), opt(&s["mem_total_mb"]));
            println!("           net rx {} kb/s  tx {} kb/s   cores {}", opt(&s["net_rx_kbps"]), opt(&s["net_tx_kbps"]), s["parallelism"]);
            println!("  infer:   requests {}  errors {}  tokens {}  avg {} ms  last {} t/s", inf["requests"], inf["errors"], inf["tokens"], opt(&inf["avg_latency_ms"]), opt(&inf["last_tps"]));
            println!("  models:  {}", m["models_count"]);
            let h = m["history"].as_array().map(|a| a.len()).unwrap_or(0);
            println!("  history: {h} points");
            0
        }
        Err(e) => {
            eprintln!("edge: {e}");
            1
        }
    }
}

fn cmd_serve(args: &[String]) -> i32 {
    let mut host = edge_ai::DEFAULT_BIND.to_string();
    let mut port = edge_ai::DEFAULT_PORT;
    let mut model: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--host" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--host requires a value");
                    return 2;
                }
                host = args[i].clone();
            }
            "--port" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--port requires a number");
                    return 2;
                }
                match args[i].parse() {
                    Ok(p) => port = p,
                    Err(_) => {
                        eprintln!("--port expects a number");
                        return 2;
                    }
                }
            }
            "--model" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--model requires a value");
                    return 2;
                }
                model = Some(args[i].clone());
            }
            "--help" | "-h" => {
                println!("usage: edge serve [--host H] [--port P] [--model M]");
                return 0;
            }
            other => {
                eprintln!("unexpected argument: {other}");
                return 2;
            }
        }
        i += 1;
    }
    if let Err(e) = edge_ai::daemon::run(&host, port, model.as_deref(), 5) {
        eprintln!("edge: {e}");
        return 1;
    }
    0
}

fn cmd_install(args: &[String]) -> i32 {
    let Some(src) = args.first() else {
        eprintln!("usage: edge install <file.gguf> [name]");
        return 2;
    };
    if src == "--help" || src == "-h" {
        println!("usage: edge install <file.gguf> [name]");
        return 0;
    }
    let name = args.get(1).cloned().unwrap_or_else(|| {
        aios_core::default_name_for(std::path::Path::new(src))
    });
    let models_dir = aios_core::default_models_dir();
    let dir = std::path::Path::new(&models_dir);
    match aios_core::install_model(std::path::Path::new(src), dir, &name) {
        Ok(entry) => {
            let mut reg = match aios_core::Registry::load(aios_core::default_registry_file()) {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("edge: registry: {e}");
                    return 1;
                }
            };
            reg.add(entry.clone());
            if let Err(e) = reg.save() {
                eprintln!("edge: registry save: {e}");
                return 1;
            }
            println!("installed '{}' ({} bytes)", entry.name, entry.size_bytes);
            0
        }
        Err(e) => {
            eprintln!("edge: {e}");
            1
        }
    }
}

fn cmd_remove(args: &[String]) -> i32 {
    let Some(name) = args.first() else {
        eprintln!("usage: edge remove <name>");
        return 2;
    };
    if name == "--help" || name == "-h" {
        println!("usage: edge remove <name>");
        return 0;
    }
    let models_dir = aios_core::default_models_dir();
    let cache = std::path::Path::new(&models_dir);
    let mut reg = match aios_core::Registry::load(aios_core::default_registry_file()) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("edge: registry: {e}");
            return 1;
        }
    };
    let Some(entry) = reg.find(name).cloned() else {
        eprintln!("edge: model '{name}' not in the registry");
        return 1;
    };
    if let Err(e) = aios_core::remove_model(&entry, cache) {
        eprintln!("edge: {e}");
        return 1;
    }
    reg.remove(name);
    if let Err(e) = reg.save() {
        eprintln!("edge: registry save: {e}");
        return 1;
    }
    println!("removed '{name}'");
    0
}

fn cmd_fase7(name: &str) -> i32 {
    eprintln!(
        "edge: 'edge {name}' requires Fase 7 (deployment registry/transfer), not implemented yet."
    );
    1
}

fn opt(v: &Value) -> String {
    match v {
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        Value::Null => "–".to_string(),
        Value::Bool(b) => b.to_string(),
        _ => "?".to_string(),
    }
}