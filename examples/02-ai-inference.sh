#!/usr/bin/env bash
# Inferencia real com Candle em CPU: ai run, ai benchmark e ai task.
#
# Precisa de um GGUF de verdade. Nao baixa nada (638 MiB nao e coisa para um
# exemplo), mas diz o comando exato para baixar. Se MODEL_FILE apontar para um
# .gguf seu, o script usa o seu.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI="$REPO/target/release/ai"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export AIOS_MODELS_DIR="$WORK/models"
export AIOS_REGISTRY="$WORK/registry.tsv"
export AIOS_TASKS_FILE="$WORK/tasks.json"
mkdir -p "$AIOS_MODELS_DIR"

BASE="https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0/resolve/main"
MODEL_NAME="tinyllama-1.1b-chat-v1.0.Q4_K_M"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFALHOU: %s\033[0m\n' "$1" >&2; exit 1; }

[[ -x "$AI" ]] || fail "CLI nao encontrada; rode: cargo build -p aios-cli --release"

# ---- localiza modelo + tokenizer ------------------------------------------
# Por padrao procura em varios lugares comuns antes de desistir. Se mais de um
# .gguf existir, prefere aquele que tem tokenizer.json ao lado: um .gguf sem
# tokenizer nao roda, e o primeiro achado costuma ser o do proprio repo, que
# foi baixado a mao e nunca ganhou o tokenizer.
MODEL_FILE="${MODEL_FILE:-}"
if [[ -z "$MODEL_FILE" ]]; then
  for cand in \
    "$REPO/models/$MODEL_NAME.gguf" \
    "$REPO/$MODEL_NAME.gguf" \
    "/tmp/opencode/models/$MODEL_NAME.gguf" \
    "/var/lib/ai/models/$MODEL_NAME.gguf"
  do
    [[ -f "$cand" ]] || continue
    if [[ -f "$(dirname "$cand")/tokenizer.json" ]]; then
      MODEL_FILE="$cand"
      break
    fi
    # sem tokenizer: guarda como plano B, ainda pode ser o unico
    MODEL_FILE="${MODEL_FILE:-$cand}"
  done
fi


if [[ -z "$MODEL_FILE" || ! -f "$MODEL_FILE" ]]; then
  cat <<EOF

\033[33mPULADO: nenhum modelo encontrado.\033[0m

Este exemplo precisa de um GGUF real e do tokenizer.json do mesmo modelo ao
lado. Baixe os dois (1.1B, Q4_K_M, ~638 MiB) e rode de novo:

  mkdir -p ~/aios-models && cd ~/aios-models
  curl -L -o $MODEL_NAME.gguf $BASE/$MODEL_NAME.gguf
  curl -L -o tokenizer.json $BASE/tokenizer.json
  MODEL_FILE=~/aios-models/$MODEL_NAME.gguf $0

O tokenizer precisa estar no MESMO diretorio do .gguf. Sem ele o backend
Candle e pulado e a saida diz "skipped", o que parece falta de suporte
em vez de arquivo faltando.

EOF
  exit 0
fi

echo "modelo:  $MODEL_FILE ($(stat -c%s "$MODEL_FILE") bytes)"
TOKENIZER="$(dirname "$MODEL_FILE")/tokenizer.json"
if [[ ! -f "$TOKENIZER" ]]; then
  fail "falta o tokenizer.json ao lado do modelo. Baixe de $BASE/tokenizer.json"
fi
echo "tokenizer: $TOKENIZER"

# ---- inspect: o que o backend vai encontrar --------------------------------
step "ai inspect (cabecalho, arquitetura, contexto, vocab)"
"$AI" inspect "$MODEL_FILE" || fail "inspect"

# ---- benchmark: metadados, checksum e throughput --------------------------
step "ai benchmark (parse do GGUF + SHA-256 + geracao Candle)"
"$AI" benchmark "$MODEL_FILE" --iter 200 || fail "benchmark"

# ---- run: geracao de verdade ------------------------------------------------
# O texto gerado vai para stdout e o resumo "==> N tokens/s" para stderr, entao
# os dois streams precisam ser unidos para checar o resultado.
step "ai run (geracao de 32 tokens)"
OUT=$("$AI" run "$MODEL_FILE" --prompt "Hello" --max-tokens 32 2>&1) || fail "run"
echo "$OUT"
# o throughput sai em "==> N.NN tokens/s"
echo "$OUT" | grep -qE '[0-9.]+ tokens/s' || fail "run nao reportou throughput"
echo "--> $(echo "$OUT" | grep -oE '[0-9.]+ tokens/s' | tail -1)"

# ---- task: roteamento declarativo -> mesmo backend -------------------------
step "ai task --list (roteamento declarativo)"
"$AI" task --list || fail "task --list"

step "ai task classify --text (rota classify -> mesmo modelo)"
"$AI" task classify --model "$MODEL_FILE" --text "I loved this, it works great" \
  --max-tokens 16 || fail "task classify"

step "ai task summarize --json (mesma rota, saida estruturada)"
"$AI" task summarize --model "$MODEL_FILE" --json \
  --text "Redox is a Unix-like OS written in Rust. AIOS builds it with an AI runtime." \
  --max-tokens 32 || fail "task summarize"

printf '\n\033[32mOK\033[0m inferencia real, via ai run e via ai task.\n'
echo "Estes sao numeros de CPU. Nao ha coluna acelerada: a Fase 9 esta"
echo "bloqueada por falta de driver de GPU/NPU no Redox (docs/ROADMAP.md)."
