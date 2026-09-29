#!/usr/bin/env bash
# Ciclo de vida de um modelo no cache: inspect -> verify -> install -> list ->
# info -> remove.
#
# Não baixa nada. Fabrica um GGUF mínimo de 24 bytes, que tem cabeçalho válido
# (magic "GGUF", versão 1, zero tensores, zero KV) e por isso passa por toda a
# camada de catálogo, metadados e checksum. Ele NÃO serve para inferência —
# ver 02-ai-inference.sh para isso.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI="$REPO/target/release/ai"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export AIOS_MODELS_DIR="$WORK/models"
export AIOS_REGISTRY="$WORK/registry.tsv"
mkdir -p "$AIOS_MODELS_DIR"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFALHOU: %s\033[0m\n' "$1" >&2; exit 1; }

[[ -x "$AI" ]] || fail "CLI nao encontrada; rode: cargo build -p aios-cli --release"

# ---- fabrico o GGUF minimo -------------------------------------------------
MODEL="$WORK/tiny-demo.gguf"
python3 - "$MODEL" <<'PY'
import struct, sys
# magic | version(u32) | n_tensors(u64) | n_kv(u64)
with open(sys.argv[1], "wb") as f:
    f.write(b"GGUF" + struct.pack("<I", 1) + struct.pack("<Q", 0) * 2)
PY
[[ -s "$MODEL" ]] || fail "nao consegui fabricar o GGUF minimo"
echo "GGUF sintetico: $(stat -c%s "$MODEL") bytes em $MODEL"

# ---- inspect: metadados do arquivo, sem tocar no cache --------------------
step "ai inspect (le o header GGUF direto do arquivo)"
"$AI" inspect "$MODEL" || fail "inspect"

# ---- verify: SHA-256 do arquivo -------------------------------------------
step "ai verify (checksum)"
SUM=$("$AI" verify "$MODEL") || fail "verify"
echo "sha256 = $SUM"
[[ "$SUM" =~ ^[0-9a-f]{64}$ ]] || fail "verify nao devolveu um sha256 de 64 hex"

# ---- install: copia pro cache e registra ----------------------------------
step "ai install (copia pro cache + registry.tsv)"
"$AI" install "$MODEL" || fail "install"
[[ -f "$AIOS_MODELS_DIR/tiny-demo.gguf" ]] || fail "install nao colocou o modelo no cache"
[[ -s "$AIOS_REGISTRY" ]] || fail "install nao escreveu o registry"

# ---- list: o que esta no cache --------------------------------------------
step "ai list"
"$AI" list || fail "list"

# ---- info: entrada do registry, com checksum e presenca em disco ----------
step "ai info (vem do registry, nao so do disco)"
"$AI" info tiny-demo || fail "info"
"$AI" info tiny-demo | grep -q "Registered: *yes" || fail "info nao viu o registro"

# ---- remove: apaga do disco e do registry ---------------------------------
step "ai remove"
"$AI" remove tiny-demo || fail "remove"
[[ ! -f "$AIOS_MODELS_DIR/tiny-demo.gguf" ]] || fail "remove deixou o arquivo no cache"
echo "removido do cache e do registry"

printf '\n\033[32mOK\033[0m ciclo completo de vida de modelo.\n'
echo "Fora do guest voce precisou de AIOS_MODELS_DIR e AIOS_REGISTRY porque"
echo "/var/lib/ai e root-only no host. No Redox sao os caminhos reais."
