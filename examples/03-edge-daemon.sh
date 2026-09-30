#!/usr/bin/env bash
# O daemon edge-ai: subir em loopback, ver status/ modelos, rodar inferencia
# pelo endpoint HTTP e ler os logs. Depois derruba.
#
# Nao baixa nada: usa os modelos que ja estiverem em AIOS_MODELS_DIR. Sem
# nenhum modelo, ainda mostra status e models vazio — o daemon e a interface
# que interessam aqui, nao a inferencia (isso e 02-ai-inference.sh).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE="$REPO/target/release/edge"
PORT="${EDGE_PORT:-8989}"
WORK="$(mktemp -d)"

# Loopback explicito: o default do daemon e 0.0.0.0, e o endpoint HTTP nao tem
# autenticacao. Nao exponha isso na rede do seu escritorio.
HOST="127.0.0.1"
LOG="$WORK/edge.log"
PID=""

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFALHOU: %s\033[0m\n' "$1" >&2; exit 1; }

[[ -x "$EDGE" ]] || fail "CLI nao encontrada; rode: cargo build -p edge-ai --release"

export AIOS_MODELS_DIR="${AIOS_MODELS_DIR:-$WORK/models}"
export AIOS_REGISTRY="${AIOS_REGISTRY:-$WORK/registry.tsv}"
mkdir -p "$AIOS_MODELS_DIR"

# O cliente (status/models/run) fala sempre com 127.0.0.1:8989 e nao aceita
# --port; se o daemon estiver em outra porta, o cliente precisa do env.
export EDGE_BASE_URL="$HOST:$PORT"

step "edge serve --host $HOST --port $PORT"
"$EDGE" serve --host "$HOST" --port "$PORT" >"$LOG" 2>&1 &
PID=$!

# Espera o endpoint responder em vez de dormir um tempo arbitrario.
for _ in $(seq 1 50); do
  grep -q "listening on" "$LOG" && break
  kill -0 "$PID" 2>/dev/null || { cat "$LOG"; fail "daemon morreu ao subir"; }
  sleep 0.2
done
grep -q "listening on" "$LOG" || { cat "$LOG"; fail "daemon nao reportou listen em ${PORT}"; }
echo "pid=$PID  $(tail -1 "$LOG")"

step "edge status (saude, uptime, uso de CPU/mem, contadores de inferencia)"
"$EDGE" status || fail "status"

step "edge models (o que o daemon enxerga no cache)"
"$EDGE" models || fail "models"

step "edge run (inferencia pelo endpoint HTTP do daemon)"
MODEL_REF="$("$EDGE" models | awk '/llama/ {print $1; exit}')"
if [[ -z "$MODEL_REF" ]]; then
  echo "nenhum modelo llama no cache — pulando edge run."
  echo "ponha um .gguf em AIOS_MODELS_DIR para ver inferencia pelo daemon."
else
  echo "modelo: $MODEL_REF"
  "$EDGE" run "$MODEL_REF" --prompt "Hello" --max-tokens 16 || fail "edge run"
fi

step "edge benchmark"
if [[ -n "$MODEL_REF" ]]; then
  "$EDGE" benchmark --model "$MODEL_REF" --tokens 16 || fail "edge benchmark"
else
  "$EDGE" benchmark || true   # sem modelo, o daemon responde; o exit code e dele
fi

step "edge logs"
"$EDGE" logs --tail 20 || fail "edge logs"

step "derrubando o daemon (nao existe 'edge stop': mate o processo)"
kill "$PID"
wait "$PID" 2>/dev/null || true
PID=""
echo "daemon parado"

printf '\n\033[32mOK\033[0m daemon edge no ar, em loopback, e derrubado.\n'
echo "Lembre: sem --host o daemon escuta em 0.0.0.0 e o endpoint nao tem"
echo "autenticacao. 'edge devices' foi omitido de proposito: ele bloqueia em"
echo "descoberta de rede e nao termina sozinho."
