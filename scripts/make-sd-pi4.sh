#!/usr/bin/env bash
# make-sd-pi4.sh — prepara (e opcionalmente grava) a imagem SD do AIOS Edge OS
# para o Raspberry Pi 4B a partir da imagem validada do build.
#
# Uso:
#   scripts/make-sd-pi4.sh                          # prepara a imagem SD
#   scripts/make-sd-pi4.sh --output /caminho.img    # saída customizada
#   scripts/make-sd-pi4.sh --write /dev/sdX         # prepara e GRAVA no cartão
#
# O que faz:
#   1. copia redox-os/build/aarch64/pi4/harddrive.img  ->  aios-edge-pi4-sd.img
#      (GPT: p1 BIOS-boot, p2 EFI FAT, p3 RedoxFS)
#   2. injeta na partição EFI (offset 1 MiB) os arquivos de boot do Pi 4:
#      kernel8.img (u-boot), start4.elf, fixup4.dat, bcm2711-rpi-4-b.dtb,
#      overlays/disable-bt.dtbo e config.txt (pasta config/aarch64/raspi4bp/boot)
#   3. com --write: grava o resultado no cartão com dd (pede confirmação e
#      recusa discos do sistema/montados)
#
# Não precisa de root para preparar (usa mtools com offset "IMG@@1048576").
# Requer o build feito antes:  CI=1 ARCH=aarch64 BOARD=raspi4bp CONFIG_NAME=pi4 \
#                              PODMAN_BUILD=0 make all

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="$(cd "${HERE}/.." && pwd)"
ROOT="${WS}/redox-os"
BUILD="${ROOT}/build/aarch64/pi4"
SRC_IMG="${BUILD}/harddrive.img"
BOOT_SRC="${ROOT}/config/aarch64/raspi4bp/boot"
OUT="${BUILD}/aios-edge-pi4-sd.img"
EFI_OFFSET=1048576   # partição EFI = setor 2048 = 1 MiB
WRITE_DEV=""
FILES="config.txt kernel8.img start4.elf fixup4.dat bcm2711-rpi-4-b.dtb"

while [ $# -gt 0 ]; do
  case "$1" in
    --output) OUT="$2"; shift 2 ;;
    --write)  WRITE_DEV="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1 (use --help)" >&2; exit 2 ;;
  esac
done

# mtools: do sistema, ou do pacote extraído em build/tools/mtools
MT=""
if command -v mcopy >/dev/null 2>&1; then MT="$(dirname "$(command -v mcopy)")"; fi
if [ -z "$MT" ] && [ -x "${ROOT}/build/tools/mtools/bin/mcopy" ]; then
  MT="${ROOT}/build/tools/mtools/bin"
fi
[ -n "$MT" ] || { echo "erro: mtools não encontrado (apt install mtools)" >&2; exit 1; }
export MTOOLS_SKIP_CHECK=1

[ -f "$SRC_IMG" ] || { echo "erro: imagem não encontrada: $SRC_IMG" >&2; echo "      rode o build antes (make image com ARCH=aarch64 BOARD=raspi4bp CONFIG_NAME=pi4)" >&2; exit 1; }
for f in $FILES; do
  [ -f "$BOOT_SRC/$f" ] || { echo "erro: faltando $BOOT_SRC/$f" >&2; exit 1; }
done

echo "== 1/4 copiando a imagem base =="
echo "   $SRC_IMG -> $OUT"
cp --reflink=auto "$SRC_IMG" "$OUT"
chmod u+w "$OUT"

echo "== 2/4 injetando arquivos de boot do Pi 4 na partição EFI =="
FAT="$OUT@@${EFI_OFFSET}"
for f in $FILES; do
  "$MT/mcopy" -o -i "$FAT" "$BOOT_SRC/$f" "::/$f"
done
"$MT/mmd" -i "$FAT" ::/overlays 2>/dev/null || true
"$MT/mcopy" -o -i "$FAT" "$BOOT_SRC/overlays/disable-bt.dtbo" "::/overlays/disable-bt.dtbo"

echo "== 3/4 verificando conteúdo da partição EFI =="
"$MT/mdir" -i "$FAT" ::        | sed 's/^/   /'
"$MT/mdir" -i "$FAT" ::/overlays | sed 's/^/   /'
"$MT/mdir" -i "$FAT" ::/EFI/BOOT | sed 's/^/   /'
ls -la "$OUT"

if [ -z "$WRITE_DEV" ]; then
  echo
  echo "Imagem SD pronta: $OUT"
  echo "Depois, para gravar num cartão:  $0 --write /dev/sdX"
  exit 0
fi

echo
echo "== 4/4 gravando em $WRITE_DEV =="
[ -b "$WRITE_DEV" ] || { echo "erro: $WRITE_DEV não é um dispositivo de bloco" >&2; exit 1; }
if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; else SUDO=; fi
DEVSZ=$($SUDO blockdev --getsize64 "$WRITE_DEV")

# Trava 1: nunca gravar em disco que contém o sistema
for m in / /home /boot /boot/efi; do
  src="$(findmnt -no SOURCE -T "$m" 2>/dev/null || true)"
  pk="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
  if [ -n "$pk" ] && [ "/dev/$pk" = "$WRITE_DEV" ]; then
    echo "erro: $WRITE_DEV contém $m — NUNCA grave no disco do sistema" >&2; exit 1
  fi
done

# Trava 2: nada montado a partir do cartão
if [ -n "$(lsblk -no MOUNTPOINTS "$WRITE_DEV" 2>/dev/null | tr -d '[:space:]')" ]; then
  echo "erro: $WRITE_DEV (ou suas partições) está montado; desmonte antes" >&2; exit 1
fi

DEVSZ=$($SUDO blockdev --getsize64 "$WRITE_DEV")
[ "$DEVSZ" -ge 2147483648 ] || { echo "erro: cartão menor que 2 GiB (imagem tem 2 GiB)" >&2; exit 1; }

echo "Cartão: $WRITE_DEV ($(( DEVSZ / 1024 / 1024 )) MiB)"
$SUDO lsblk -o NAME,SIZE,TYPE,TRAN,MODEL "$WRITE_DEV" | sed 's/^/   /'
echo
echo "!!! Isto APAGA TODO o conteúdo de $WRITE_DEV !!!"
read -r -p "Digite GRAVAR para confirmar: " resp
[ "$resp" = "GRAVAR" ] || { echo "cancelado."; exit 1; }

$SUDO dd if="$OUT" of="$WRITE_DEV" bs=4M conv=fsync status=progress
$SUDO sync
echo
echo "Gravação concluída. Agora:"
echo "  1. remova o cartão do leitor e insira no Raspberry Pi 4 (desligado);"
echo "  2. conecte o adaptador UART (GND=pino 6, RX->pino 8, TX->pino 10, 115200 8N1);"
echo "  3. ligue o Pi e acompanhe:  picocom -b 115200 /dev/ttyUSB0"
