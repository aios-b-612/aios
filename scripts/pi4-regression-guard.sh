#!/usr/bin/env bash
# Guarda de regressão Pi 4 — corre no CI (contratos) e localmente (fonte Redox).
#
# Falha se:
#   - os testes `pi4-contract` não passam
#   - com `redox-os/` presente: path default do genetd volta a registar NetworkScheme
#     sem feature `network-scheme`, ou logdump volta a ser spawnado, ou RING_CFG
#     usa o shift errado.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> cargo test -p pi4-contract"
cargo test -p pi4-contract --verbose

GENET_MAIN="redox-os/recipes/core/base/source/drivers/net/bcmgenetd/src/main.rs"
GENET_RS="redox-os/recipes/core/base/source/drivers/net/bcmgenetd/src/genet.rs"
SDHCI_MAIN="redox-os/recipes/core/base/source/drivers/storage/bcm2835-sdhcid/src/main.rs"

if [[ ! -d redox-os ]]; then
  echo "==> redox-os/ ausente (CI sem tree) — só contratos Rust OK"
  exit 0
fi

echo "==> checagens na árvore redox-os/"

# 1) Path default = beacon-only M1 (sem NetworkScheme::new no main)
if grep -n 'NetworkScheme::new' "$GENET_MAIN" >/dev/null 2>&1; then
  if ! grep -n 'feature *= *"network-scheme"\|cfg(feature = "network-scheme")' "$GENET_MAIN" >/dev/null; then
    echo "FAIL: NetworkScheme::new sem feature gate network-scheme em $GENET_MAIN"
    echo "      M2 hangou no HW (2026-11-04). Manter beacon-only como default."
    exit 1
  fi
fi

if ! grep -q 'beacon-only M1' "$GENET_MAIN"; then
  echo "FAIL: marcador 'beacon-only M1' ausente em $GENET_MAIN"
  exit 1
fi

# 2) logdump não pode ser spawnado no boot
if grep -n 'logdump::spawn' "$SDHCI_MAIN" >/dev/null 2>&1; then
  echo "FAIL: logdump::spawn ainda chamado em $SDHCI_MAIN (abort redoxfs no Pi)"
  exit 1
fi
if ! grep -q 'logdump DISABLED' "$SDHCI_MAIN"; then
  echo "FAIL: esperado 'logdump DISABLED' em $SDHCI_MAIN"
  exit 1
fi

# 3) DMA_RING_CFG usa bit DEFAULT_Q (não q+SHIFT)
# Aceita literal `1 << (DEFAULT_Q as u32)` nas linhas RING_CFG.
if grep -n 'TDMA_CTRL_BASE + DMA_RING_CFG' -A1 "$GENET_RS" | grep -E 'DEFAULT_Q as u32 \+ DMA_RING_BUF_EN_SHIFT|DEFAULT_Q \+ DMA_RING_BUF_EN_SHIFT' >/dev/null; then
  echo "FAIL: DMA_RING_CFG ainda usa shift de CTRL em $GENET_RS"
  exit 1
fi
if ! grep -n 'TDMA_CTRL_BASE + DMA_RING_CFG' -A2 "$GENET_RS" | grep -q '1 << (DEFAULT_Q as u32)'; then
  echo "FAIL: esperado RING_CFG = 1 << DEFAULT_Q em $GENET_RS"
  exit 1
fi

echo "OK pi4-regression-guard"
