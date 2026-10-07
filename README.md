# AIOS - AI Operating System

AIOS is a AIOS operating system based on Redox OS, designed for edge AI deployment and model inference.

## Quick Start

```bash
# Build the project
cargo build --target x86_64-unknown-redox

# Run the CLI
aios-deploy add mydevice 192.168.1.100
aios-security create-ai-model mymodel

# Edge AI CLI
edge status
edge run mymodel

# Developer tools
aios-dev new myproject --template ai-model
aios-dev check
```

## Crates

- `aios-core`: Core functionality - GGUF parsing, checksums, model registry
- `edge-sdk`: Edge SDK with model loading and inference
- `edge-ai`: Edge AI daemon (local HTTP API)
- `ai-cli`: Model CLI (list, install, remove, info, inspect, verify, benchmark, run, task)
- `deploy`: Fase 7 Deployment - device registry and model deployment protocol
- `security`: Fase 8 Security - AI model isolation and permissions using Redox `contain` scheme
- `security-dev`: Developer CLI (`aios-dev`) for project scaffolding and environment checks

## Architecture

```
                    REDOX OS (upstream kernel + userspace)
                          │
                          │ ai-core (base)
                          ▼
                ┌─────────────────────┐
                │   AIOS OS         │
                │ (project layer)   │
                │  edge-ai daemon   │  ← HTTP API on :8989
                │  deploy protocol  │
                │  security policies│
                └─────────────────────┘
                          │
                          ▼
                ┌─────────────────────┐
                │   Edge AI OS      │  ← inference runtime
                │  (project layer)  │
                └─────────────────────┘
```

## Installation

```bash
# Clone the repository
git clone https://github.com/aios/aios.git
cd aios

# Build the project
cargo build --all

# Or build individual components:
cargo build --bin ai          # Model CLI
cargo run --bin edge          # Start edge AI daemon
cargo run --bin aios-deploy   # Deploy tools
cargo run --bin aios-security # Security tools
cargo run --bin dev           # Developer CLI
```

## License

MIT OR Apache-2.0