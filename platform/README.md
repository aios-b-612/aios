# AIOS — meta-repo

Orquestra a construção das imagens **Developer OS** e **Edge AI OS** a partir do
Redox OS upstream, sem modificar o kernel ou o userspace upstream.

```
platform/
├── Makefile
├── upstream.lock          pin do upstream Redox (repo + commit + kernel pkg)
├── config/
│   ├── x86_64/ai-developer.toml
│   └── aarch64/ai-edge.toml
└── scripts/
    ├── bootstrap.sh       materializar o upstream pinado
    ├── build.sh           construir imagens
    ├── run-qemu.sh        rodar no QEMU
    ├── test.sh            smoke-test de boot headless
    ├── release.sh         artefatos + checksums + manifesto de proveniência
    └── debug-qemu.sh      attach gdb (kernel/userspace)
```

## Pré-requisitos (host)

- `git`, `make`, `bash`, `python3`, `timeout`
- Compilador Rust (`rustc`/`cargo`)
- `qemu-system-x86_64` (x86_64) e/ou `qemu-system-aarch64` (arm)
- Para build nativo: `gcc`, `g++`, `cmake`, `curl`, `wget`, `pkg-config`
  (ver `redox-os/native_bootstrap.sh` para a lista completa)
- **OU** `podman` para build containerizado (não testado com docker)

**Aviso**: o primeiro build baixa toolchains/pacotes e consome vários GB.
Com `PREFIX_BINARY=1 REPO_BINARY=1` (padrão) baixa binários pré-compilados do
upstream em vez de compilar cada pacote.

## Uso

```sh
# 1. materializar o upstream pinado (idempotente; ~1 GB)
make -C platform bootstrap

# Developer OS (x86_64)
./scripts/build.sh -a x86_64 -c ai-developer
./scripts/run-qemu.sh -a x86_64 -c ai-developer

# Edge AI OS (aarch64)
./scripts/build.sh -a aarch64 -c ai-edge
./scripts/run-qemu.sh -a aarch64 -c ai-edge

# Smoke test de boot (CI)
./scripts/test.sh -a x86_64 -c ai-developer
./scripts/debug-qemu.sh -a x86_64 -c ai-developer

# Release: artefatos + checksums + manifesto de proveniência
./scripts/release.sh --test          # em platform/dist/
```

O upstream fica em `../redox-os` (clone pinado por `bootstrap.sh`, revisão em
`upstream.lock`). Para apontar para outro checkout:
`REDOX_SOURCE=/caminho ./scripts/build.sh ...`. Para conferir o pin:
`./scripts/bootstrap.sh --verify`.

## Como funciona

O `scripts/build.sh` chama `redox-os/build.sh` passando o nosso
`FILESYSTEM_CONFIG` (`-f`), que faz `include` dos perfis upstream (`server.toml`)
e adiciona pacotes/caminhos específicos da plataforma (ex.: `/var/lib/ai/models`).

Nenhum arquivo do `redox-os/` é modificado.