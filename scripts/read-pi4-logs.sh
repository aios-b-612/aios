#!/usr/bin/env bash
# read-pi4-logs.sh — lê logs de boot do cartão SD do Pi 4 após boot
# Uso: sudo ./read-pi4-logs.sh /dev/sda

set -euo pipefail

DEV="${1:-/dev/sda}"

if [ "$EUID" -ne 0 ]; then
    echo "Precisa rodar como root: sudo $0 $DEV"
    exit 1
fi

echo "=== Lendo logs do cartão SD: $DEV ==="
echo ""

# 1. Logdump cru (LBA 4259840 = 64 MiB após fim da imagem 2GiB)
LOG_LBA=4259840
LOG_BLOCKS=256  # 128 KiB
echo "--- 1. Logdump cru (LBA $LOG_LBA, $((LOG_BLOCKS*512/1024)) KiB) ---"
dd if="$DEV" bs=512 skip=$LOG_LBA count=$LOG_BLOCKS 2>/dev/null | strings | head -80
echo ""

# 2. Tentar montar partição 3 (RedoxFS) e ler breadcrumbs
echo "--- 2. Breadcrumbs em /var/lib/ai/ (requer montar RedoxFS) ---"
# RedoxFS não monta nativamente no Linux. Alternativas:
# a) Usar qemu com a imagem para ler
# b) Comparar imagem com original (detecta escritas)

# 3. Comparação com imagem mestre (detecta se boot avançou)
MASTER_IMG="/home/fasr/SSD_BACKUP/Workspace/aios/redox-os/build/aarch64/pi4/aios-edge-pi4-sd.img"
if [ -f "$MASTER_IMG" ]; then
    echo "--- 3. Comparação com imagem mestre ($MASTER_IMG) ---"
    echo "Comparando primeiros 2 GiB..."
    if cmp -s <(dd if="$DEV" bs=4M count=512 2>/dev/null) <(dd if="$MASTER_IMG" bs=4M count=512 2>/dev/null); then
        echo "IDÊNTICO — boot NÃO escreveu no cartão (parou antes de montar RedoxFS)"
    else
        echo "DIFERENTE — boot ESCREVEU no cartão (avançou até montar RedoxFS)"
        echo "Diff ranges:"
        # Encontrar ranges diferentes
        python3 -c "
import sys
with open('$DEV', 'rb') as f1, open('$MASTER_IMG', 'rb') as f2:
    chunk = 16*1024*1024  # 16 MiB
    diffs = []
    pos = 0
    while True:
        b1 = f1.read(chunk)
        b2 = f2.read(chunk)
        if not b1 and not b2:
            break
        if b1 != b2:
            # Encontrar bytes diferentes dentro do chunk
            for i in range(min(len(b1), len(b2))):
                if b1[i] != b2[i]:
                    diffs.append(pos + i)
                    break
        pos += chunk
        if len(diffs) > 20:
            break
    for d in diffs:
        print(f'  Offset {d} (0x{d:x}) = {d//1024//1024} MiB')
"
    fi
else
    echo "Imagem mestre não encontrada: $MASTER_IMG"
fi

echo ""
echo "=== Fim ==="