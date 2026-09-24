//! AIOS `ai` CLI.
//!
//! Subcommands:
//!   list     - list installed models (cache dir + registry)
//!   inspect  - print GGUF header of a model file (magic, version, tensors, metadata KV)
//!   verify   - compute and print the SHA-256 of a model file
//!   doctor   - environment checks (toolchain, cache dir, registry)

use aios_core::cache::DEFAULT_MODELS_DIR;
use aios_core::gguf::ValueType;
use aios_core::{self, find_models, list_installed, pretty_bytes, Registry};
use std::path::Path;

const USAGE: &str = "\
AIOS ai - model cache and inspection CLI

Usage:
  ai list  [--dir DIR]
  ai inspect <file.gguf>
  ai verify <file.gguf>
  ai doctor
";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("{USAGE}");
        std::process::exit(2);
    }
    let code = match args[0].as_str() {
        "list" => cmd_list(&args[1..]),
        "inspect" => cmd_inspect(&args[1..]),
        "verify" => cmd_verify(&args[1..]),
        "doctor" => cmd_doctor(),
        "help" | "-h" | "--help" => {
            eprintln!("{USAGE}");
            0
        }
        other => {
            eprintln!("unknown command: {other}\n{USAGE}");
            2
        }
    };
    std::process::exit(code);
}

fn cmd_list(args: &[String]) -> i32 {
    let mut dir = DEFAULT_MODELS_DIR.to_string();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--dir" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--dir requires a path");
                    return 2;
                }
                dir = args[i].clone();
            }
            other => {
                eprintln!("unexpected argument: {other}");
                return 2;
            }
        }
        i += 1;
    }

    println!("Models in {dir}:");
    match list_installed(Path::new(&dir)) {
        Ok(models) => {
            if models.is_empty() {
                println!("  (none)");
            }
            for m in &models {
                let kind = if m.is_gguf() {
                    "gguf"
                } else {
                    "unknown/unreadable"
                };
                println!(
                    "  {:<28} {:>10}  {}",
                    m.name, m.size_pretty(), kind
                );
            }

            match Registry::load(aios_core::registry::DEFAULT_REGISTRY_FILE) {
                Ok(reg) => {
                    if !reg.entries().is_empty() {
                        println!("\nRegistry ({}):", aios_core::registry::DEFAULT_REGISTRY_FILE);
                        for e in reg.entries() {
                            println!("  {:<28} {:<20} {}", e.name, e.sha256[..10.min(e.sha256.len())].to_string(), pretty_bytes(e.size_bytes));
                        }
                    }
                }
                Err(e) => eprintln!("warning: registry: {e}"),
            }
            0
        }
        Err(e) => {
            eprintln!("error: {e}");
            1
        }
    }
}

fn cmd_inspect(args: &[String]) -> i32 {
    let Some(path) = args.first() else {
        eprintln!("usage: ai inspect <file.gguf>");
        return 2;
    };
    let model = match aios_core::ModelMeta::from_path(Path::new(path)) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };
    println!("Path:        {}", model.path);
    println!("Name:        {}", model.name);
    println!("Size:        {}", model.size_pretty());

    match &model.header {
        None => {
            println!("Format:      not GGUF");
            1
        }
        Some(h) => {
            println!("Format:      GGUF");
            println!("Version:     {}", h.version);
            println!("Tensors:     {}", h.tensor_count);
            println!("Metadata:    {} entries", h.metadata.len());
            println!("\nMetadata:");
            for m in &h.metadata {
                println!(
                    "  {:<32} {:<12} {}",
                    m.key,
                    type_name(m.value_type),
                    m.value.brief()
                );
            }
            0
        }
    }
}

fn cmd_verify(args: &[String]) -> i32 {
    let Some(path) = args.first() else {
        eprintln!("usage: ai verify <file.gguf>");
        return 2;
    };
    let file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };
    println!("{}", aios_core::checksum::sha256_hex(file).unwrap_or_else(|e| format!("error: {e}")));
    0
}

fn cmd_doctor() -> i32 {
    fn present(name: &str, path: &str) {
        let ok = std::process::Command::new(path)
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);
        println!("  {name:12} {path:<24} [{}]", if ok { "OK" } else { "missing" });
    }

    println!("AIOS doctor");
    println!("\nToolchain:");
    present("rustc", "rustc");
    present("cargo", "cargo");
    present("gcc", "gcc");

    println!("\nCache:");
    let dir = Path::new(DEFAULT_MODELS_DIR);
    println!("  models dir {DEFAULT_MODELS_DIR:24} [{}]", if dir.is_dir() { "OK" } else { "missing" });
    match find_models(dir) {
        Ok(list) => println!("  found {} model(s)", list.len()),
        Err(e) => println!("  error scanning: {e}"),
    }

    println!("\nFilesystem:");
    match std::thread::available_parallelism() {
        Ok(n) => println!("  parallelism:           {}", n.get()),
        Err(e) => println!("  parallelism:           <n/a: {e}>"),
    }
    0
}

fn type_name(vt: ValueType) -> String {
    match vt {
        ValueType::Array => "array".to_string(),
        ValueType::Bool => "bool".to_string(),
        ValueType::Float32 => "f32".to_string(),
        ValueType::Float64 => "f64".to_string(),
        ValueType::Int8 => "i8".to_string(),
        ValueType::Int16 => "i16".to_string(),
        ValueType::Int32 => "i32".to_string(),
        ValueType::Int64 => "i64".to_string(),
        ValueType::Uint8 => "u8".to_string(),
        ValueType::Uint16 => "u16".to_string(),
        ValueType::Uint32 => "u32".to_string(),
        ValueType::Uint64 => "u64".to_string(),
        ValueType::String => "string".to_string(),
        ValueType::Unknown(t) => format!("type{t}"),
    }
}