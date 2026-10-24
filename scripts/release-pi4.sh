#!/usr/bin/env bash
# release-pi4.sh — servidor HTTP estático + geração de hash para update do AIOS Edge Pi 4
#
# Uso:
#   ./scripts/release-pi4.sh                    # serve a imagem atual na porta 8080
#   ./scripts/release-pi4.sh --port 8080        # porta customizada
#   ./scripts/release-pi4.sh --dir /path/to/img # diretório customizado
#   ./scripts/release-pi4.sh --gen-hash         # só gera hash da imagem

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "${HERE}/.." && pwd)"
ROOT="${WS}/redox-os"
BUILD="${ROOT}/build/aarch64/pi4"
IMG="${BUILD}/aios-edge-pi4-sd.img"

PORT=8080
SERVE_DIR="${BUILD}"
GEN_HASH_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --dir) SERVE_DIR="$2"; IMG="${SERVE_DIR}/aios-edge-pi4-sd.img"; shift 2 ;;
    --gen-hash) GEN_HASH_ONLY=true; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

[ -f "$IMG" ] || { echo "erro: imagem não encontrada: $IMG" >&2; exit 1; }

# Gera hash SHA256
HASH=$(sha256sum "$IMG" | awk '{print $1}')
SIZE=$(stat -c%s "$IMG")
HASH_FILE="${IMG}.sha256"
echo "$HASH  $(basename "$IMG")" > "$HASH_FILE"

echo "=== AIOS Edge Pi 4 Release ==="
echo "Imagem:     $IMG"
echo "Tamanho:    $SIZE bytes ($(numfmt --to=iec "$SIZE"))"
echo "SHA256:     $HASH"
echo "Hash file:  $HASH_FILE"

if [ "$GEN_HASH_ONLY" = true ]; then
  echo "Hash gerado em $HASH_FILE"
  exit 0
fi

# Verifica se python3 está disponível
if ! command -v python3 >/dev/null 2>&1; then
  echo "erro: python3 não encontrado" >&2
  exit 1
fi

echo ""
echo "=== Servidor HTTP em http://0.0.0.0:${PORT}/ ==="
echo "Endpoints:"
echo "  GET /aios-edge-pi4-sd.img        → imagem completa (2 GiB)"
echo "  GET /aios-edge-pi4-sd.img.sha256 → hash SHA256"
echo ""
echo "No Pi (via canal ctl):"
echo "  echo \"update http://<IP_DO_PC>:${PORT}/aios-edge-pi4-sd.img ${HASH}\" > /scheme/network.genet/ctl"
echo "  echo \"apply\" > /scheme/network.genet/ctl"
echo ""
echo "Pressione Ctrl+C para parar"
echo ""

cd "$SERVE_DIR"
exec python3 -m http.server "$PORT"