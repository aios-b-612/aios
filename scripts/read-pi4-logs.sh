#!/usr/bin/env bash
# read-pi4-logs.sh — lê o logdump cru (LBA fora das partições) do cartão SD do Pi 4
#
# Uso:
#   ./scripts/read-pi4-logs.sh                 # tenta /dev/sda
#   ./scripts/read-pi4-logs.sh /dev/sdb
#   sudo ./scripts/read-pi4-logs.sh /dev/sda   # se não estiver no grupo disk
#
# O driver bcm2835-sdhcid grava periodicamente em LBA 4259840
# (64 MiB após o fim da imagem GPT de 2 GiB), com magic AIOS-SDHCI-LOGDUMP.

set -euo pipefail

DEV="${1:-/dev/sda}"
LOG_LBA=4259840
LOG_BLOCKS=257   # 1 header + 128 KiB payload
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "${HERE}/.." && pwd)"
OUT_DIR="${WS}/docs/evidence/pi4"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
OUT_RAW="${OUT_DIR}/logdump-${STAMP}.bin"
OUT_LOG="${OUT_DIR}/logdump-${STAMP}.log"
OUT_META="${OUT_DIR}/logdump-${STAMP}.meta.txt"

mkdir -p "$OUT_DIR"

if [ ! -b "$DEV" ] && [ ! -f "$DEV" ]; then
  echo "erro: dispositivo/arquivo não encontrado: $DEV" >&2
  exit 1
fi

echo "=== Lendo logdump de $DEV (LBA $LOG_LBA) ==="

if dd if="$DEV" of="$OUT_RAW" bs=512 skip="$LOG_LBA" count="$LOG_BLOCKS" status=none 2>/dev/null; then
  :
else
  echo "dd falhou (precisa de root?). Tentando via python/UDisks…" >&2
  python3 - "$DEV" "$OUT_RAW" "$LOG_LBA" "$LOG_BLOCKS" <<'PY'
import dbus, sys
dev, out, lba, blocks = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
# /dev/sda → sda
name = dev.rsplit("/", 1)[-1]
bus = dbus.SystemBus()
path = f"/org/freedesktop/UDisks2/block_devices/{name}"
block = dbus.Interface(bus.get_object("org.freedesktop.UDisks2", path), "org.freedesktop.UDisks2.Block")
fd = block.OpenDevice("r", {}).take()
with open(fd, "rb") as src, open(out, "wb") as dst:
    src.seek(lba * 512)
    dst.write(src.read(blocks * 512))
print("ok via udisks", out)
PY
fi

python3 - "$OUT_RAW" "$OUT_LOG" "$OUT_META" "$DEV" "$LOG_LBA" <<'PY'
import re, sys
from pathlib import Path
raw_path, log_path, meta_path, dev, lba = sys.argv[1:6]
raw = Path(raw_path).read_bytes()
header = raw[:512].split(b"\0", 1)[0].decode("ascii", "replace")
payload = raw[512:]
m = re.search(r"len=(\d+)", header)
n = int(m.group(1)) if m else len(payload)
body = payload[:n]
Path(log_path).write_bytes(body)
Path(meta_path).write_text(header + f"\nsource={dev}\nLBA={lba}\nbytes={n}\n")
print(header)
print(f"saved log:  {log_path} ({n} bytes)")
print(f"saved meta: {meta_path}")
if not header.startswith("AIOS-SDHCI-LOGDUMP"):
    print("AVISO: magic AIOS-SDHCI-LOGDUMP não encontrado — cartão sem dump (boot não chegou no sdhcid).")
    sys.exit(2)
# quick hits
text = body.decode("utf-8", "replace")
keys = ("genetd", "redoxfs", "disk.mmc", "panicked", "UNHANDLED", "switchroot", "failed to execute", "logdump:")
print("--- hits ---")
for i, line in enumerate(text.splitlines()):
    if any(k in line for k in keys):
        print(f"{i}: {line[:180]}")
PY

echo ""
echo "=== Fim ==="
echo "Log completo: $OUT_LOG"
