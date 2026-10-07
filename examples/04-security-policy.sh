#!/usr/bin/env bash
# Politica de seguranca de um modelo: criar, inspecionar, checar decisao e
# autorizar. O ponto e o "fail closed": tudo que nao esta na politica e negado,
# inclusive coisa que você esperaria poder fazer.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEC="$REPO/target/release/aios-security"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFALHOU: %s\033[0m\n' "$1" >&2; exit 1; }
ok() { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

[[ -x "$SEC" ]] || fail "CLI nao encontrada; rode: cargo build -p aios-security --release"

# O registry de politicas vive em config_dir()/aios/policies.toml (via a crate
# `dirs`), ou seja $XDG_CONFIG_HOME/aios/policies.toml. Sem isolar o XDG, o
# script registraria politicas no seu ~/.config de verdade.
export XDG_CONFIG_HOME="$WORK/config"
mkdir -p "$XDG_CONFIG_HOME"
echo "registry de politicas isolado em: $XDG_CONFIG_HOME/aios/policies.toml"

MODEL="tinyllama-1.1b-chat-v1.0.Q4_K_M"

# ---- estado inicial: fail closed ------------------------------------------
step "policies (estado inicial: nada registrado, tudo negado)"
"$SEC" policies || fail "policies"

# ---- cria a politica do modelo ---------------------------------------------
step "create-ai-model $MODEL"
"$SEC" create-ai-model "$MODEL" || fail "create-ai-model"
ok "politica registrada com default Deny e 6 regras"

step "describe (as regras de facto, com prioridade)"
"$SEC" describe "$MODEL" || fail "describe"

# ---- decisao: o permitido ---------------------------------------------------
step "check filesystem read em /var/lib/ai/models -> deve permitir"
OUT=$("$SEC" check "$MODEL" filesystem read --scope /var/lib/ai/models) || fail "check allow"
echo "$OUT"
echo "$OUT" | grep -q "Decision: Allow" || fail "esperava Allow em /var/lib/ai/models"
ok "leitura do diretorio de modelos: permitida"

# ---- decisao: o negado ------------------------------------------------------
step "check filesystem read em /etc/shadow -> deve negar"
OUT=$("$SEC" check "$MODEL" filesystem read --scope /etc/shadow) || true
echo "$OUT"
echo "$OUT" | grep -q "Decision: Deny" || fail "esperava Deny em /etc/shadow"
ok "leitura fora do escopo: negada (fail closed)"

step "check network write -> deve negar (o modelo so le em 8989)"
OUT=$("$SEC" check "$MODEL" network write) || true
echo "$OUT"
echo "$OUT" | grep -q "Decision: Deny" || fail "esperava Deny em network write"
ok "escrita de rede: negada"

step "check compute em device -> deve negar (isolado por contain)"
OUT=$("$SEC" check "$MODEL" device execute) || true
echo "$OUT"
echo "$OUT" | grep -q "Decision: Deny" || fail "esperava Deny em device execute"
ok "acesso a device: negado"

# ---- authorize: a mesma decisao, com a regra casada -------------------------
step "authorize filesystem read em /var/lib/ai/models (mostra a regra casada)"
"$SEC" authorize "$MODEL" filesystem read --scope /var/lib/ai/models || fail "authorize"
ok "authorize casa a regra e devolve o id dela"

# ---- contain: o perfil de isolamento ---------------------------------------
step "contain-profiles e contain-plan (a camada de isolamento)"
"$SEC" contain-profiles || fail "contain-profiles"
"$SEC" contain-plan ai-model "$MODEL" || true

step "describe nao mostra contain"
"$SEC" describe "$MODEL" | grep -i "contain" || echo "(policy describe nao mostra contain; use contain-plan)"

# ---- limpeza ---------------------------------------------------------------
step "remove"
"$SEC" remove "$MODEL" || fail "remove"
"$SEC" policies

printf '\n\033[32mOK\033[0m politica criada, checada (allow e deny) e removida.\n'
echo
echo "Limite honesto: o 'contain' acima e uma camada userspace. O isolamento"
echo "de verdade no kernel do Redox ainda nao existe (docs/gotchas/"
echo "security-isolation.md), entao 'isolated: yes' nao significa sandbox real."
