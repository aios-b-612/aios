#!/bin/bash
set -euo pipefail
IMG=/home/fasr/SSD_BACKUP/Workspace/aios/redox-os/build/aarch64/pi4/aios-edge-pi4-sd.img
DEV=/dev/sda
MT=/home/fasr/SSD_BACKUP/Workspace/aios/redox-os/build/tools/mtools/bin
EXPECTED=b0bfb1766ff7fb0efb3e8f8c68e17d36

echo "== travas de segurança =="
for m in / /home /boot /boot/efi; do
  src="$(findmnt -no SOURCE -T "$m" 2>/dev/null || true)"
  pk="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
  if [ -n "$pk" ] && [ "/dev/$pk" = "$DEV" ]; then
    echo "ERRO: $DEV contém o sistema de arquivos $m — gravação abortada"; exit 1
  fi
done
if [ -n "$(lsblk -no MOUNTPOINTS "$DEV" | tr -d '[:space:]')" ]; then
  echo "ERRO: $DEV tem partição montada — desmonte antes"; exit 1
fi
[ -r "$IMG" ] || { echo "ERRO: imagem não encontrada: $IMG"; exit 1; }
szimg=$(stat -c%s "$IMG")
szdev=$(blockdev --getsize64 "$DEV")
[ "$szdev" -ge "$szimg" ] || { echo "ERRO: cartão ($szdev B) menor que a imagem ($szimg B)"; exit 1; }
[ "$(cat /sys/block/sda/ro)" = "0" ] || { echo "ERRO: cartão em modo somente-leitura"; exit 1; }
echo "  conferindo md5 da imagem (pode levar ~30s)..."
got=$(md5sum "$IMG" | cut -d' ' -f1)
[ "$got" = "$EXPECTED" ] || { echo "ERRO: md5 da imagem: $got (esperado: $EXPECTED)"; exit 1; }
echo "  imagem OK ✔ md5=$got (idêntica à validada no QEMU)"
echo "  alvo : $DEV — $((szdev/1073741824)) GiB, USB, desmontado ✔"
echo
echo "== GRAVANDO (isto apaga o cartão inteiro) =="
date '+início: %F %T'
dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
sync
date '+fim:    %F %T'
echo
echo "== conferência byte a byte (cartão vs imagem) =="
if cmp -n "$szimg" "$DEV" "$IMG"; then
  echo "RESULTADO: CONFERIDO ✔ — cartão idêntico à imagem validada"
else
  echo "RESULTADO: DIVERGÊNCIA ✗ — cartão deve ser regravado"; exit 1
fi
blockdev --rereadpt "$DEV" 2>/dev/null || partprobe "$DEV" 2>/dev/null || true
echo
echo "== conteúdo da partição de boot do cartão =="
if [ -x "$MT/mdir" ]; then
  MTOOLS_SKIP_CHECK=1 "$MT/mdir" -i "$DEV@@1048576" :: 2>&1 | sed 's/^/   /' || true
fi
echo
echo "== layout final do cartão =="
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DEV" || true
echo "== FIM =="
