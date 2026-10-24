#!/bin/bash
# Regravação com verificação + diagnóstico (cartão SD do Pi 4 / AIOS Edge)
set +e
IMG=/home/fasr/SSD_BACKUP/Workspace/aios/redox-os/build/aarch64/pi4/aios-edge-pi4-sd.img
DEV=/dev/sda
MT=/home/fasr/SSD_BACKUP/Workspace/aios/redox-os/build/tools/mtools/bin
SZ=2147483648
EXPECTED=b0bfb1766ff7fb0efb3e8f8c68e17d36
export MTOOLS_SKIP_CHECK=1

travas() {
  for m in / /home /boot /boot/efi; do
    local src pk
    src="$(findmnt -no SOURCE -T "$m" 2>/dev/null || true)"
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
    if [ -n "$pk" ] && [ "/dev/$pk" = "$DEV" ]; then echo "ERRO: $DEV contém $m"; return 1; fi
  done
  if [ -n "$(lsblk -no MOUNTPOINTS "$DEV" | tr -d '[:space:]')" ]; then echo "ERRO: $DEV montado"; return 1; fi
  return 0
}

echo "########## PARTE 1: diagnóstico ##########"
date '+início: %F %T'
echo
echo "== dmesg (cartão/leitor USB) =="
dmesg --time-format=iso 2>/dev/null | grep -iE "sda|usb-storage|sd 0:|scsi|super top" | grep -viE "linuwu" | tail -40
echo
echo "== leitor =="
lsusb 2>/dev/null | grep -iE "14cd|super top|storage" || true
lsusb -t 2>/dev/null | head -25 || true
command -v smartctl >/dev/null && smartctl -i -d sat "$DEV" 2>&1 | head -15
echo
echo "== mapa de diferenças (blocos de 16 MiB; 128 no total) =="
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
nd=0; first=""; last=""
for i in $(seq 0 127); do
  a=$(dd if="$DEV" bs=16M skip=$i count=1 status=none 2>/dev/null | sha256sum | cut -d' ' -f1)
  b=$(dd if="$IMG" bs=16M skip=$i count=1 status=none 2>/dev/null | sha256sum | cut -d' ' -f1)
  if [ "$a" != "$b" ]; then
    printf "  DIFERENTE: bloco %3d — %4d MiB\n" "$i" "$((i*16))"
    nd=$((nd+1)); [ -z "$first" ] && first=$i; last=$i
  fi
done
echo "  resumo: $nd blocos diferentes de 128${first:+ (do bloco $first ao $last)}"
echo
echo "== amostra forense (16 KiB no 1º diff, offset 867958784) =="
dd if="$DEV" bs=4096 skip=211904 count=4 status=none > /tmp/opencode/forense-cartao.bin 2>/dev/null
dd if="$IMG" bs=4096 skip=211904 count=4 status=none > /tmp/opencode/forense-imagem.bin 2>/dev/null
md5sum /tmp/opencode/forense-cartao.bin /tmp/opencode/forense-imagem.bin
echo

echo "########## PARTE 2: regravação ##########"
travas || { echo "abortado"; exit 1; }
md5sum "$IMG"
echo "== T1: bs=4M conv=fsync (igual à 1ª tentativa) =="
dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
sync; sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
if cmp -n "$SZ" "$DEV" "$IMG"; then echo "T1: CONFERIDO OK"; ok=1; else echo "T1: FALHOU"; ok=0; fi

if [ "${ok:-0}" -eq 0 ]; then
  travas || { echo "abortado"; exit 1; }
  echo
  echo "== T2: bs=1M conv=fsync oflag=direct =="
  dd if="$IMG" of="$DEV" bs=1M conv=fsync oflag=direct status=progress
  sync; sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  if cmp -n "$SZ" "$DEV" "$IMG"; then echo "T2: CONFERIDO OK"; ok=1; else echo "T2: FALHOU"; ok=0; fi
fi

if [ "${ok:-0}" -eq 0 ]; then
  travas || { echo "abortado"; exit 1; }
  echo
  echo "== T3: forçar reescrita da janela 768–960 MiB com padrões, depois regravar =="
  echo "-- padrão 0xAA em 768–960 MiB:"
  dd if=/dev/zero bs=1M count=192 status=none | tr '\000' '\252' | dd of="$DEV" bs=1M seek=768 conv=fsync status=none
  sync
  n1=$(dd if="$DEV" bs=1M skip=768 count=192 status=none | tr -d '\252' | wc -c)
  echo "   bytes diferentes do padrão AA: $n1 (esperado 0)"
  echo "-- zeros em 768–960 MiB:"
  dd if=/dev/zero of="$DEV" bs=1M seek=768 count=192 conv=fsync status=none
  sync
  n0=$(dd if="$DEV" bs=1M skip=768 count=192 status=none | tr -d '\000' | wc -c)
  echo "   bytes diferentes de zero: $n0 (esperado 0)"
  echo "-- regravando a imagem completa:"
  dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
  sync; sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  if cmp -n "$SZ" "$DEV" "$IMG"; then echo "T3: CONFERIDO OK"; ok=1; else echo "T3: FALHOU"; ok=0; fi
fi

echo
echo "########## RESULTADO ##########"
if [ "${ok:-0}" -eq 1 ]; then
  echo "CARTÃO CONFERIDO — pode ir para o Pi"
  blockdev --rereadpt "$DEV" 2>/dev/null || partprobe "$DEV" 2>/dev/null || true
  echo "-- ESP:"
  "$MT/mdir" -i "$DEV@@1048576" :: 2>&1 | sed 's/^/   /' || true
  echo "-- md5 dos 2 GiB no cartão (esperado $EXPECTED):"
  dd if="$DEV" bs=4M count=512 status=none | md5sum
  echo "-- layout:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$DEV"
else
  echo "AINDA FALHOU — NÃO usar o cartão para boot até resolver"
fi
echo
echo "== dmesg final (cartão) =="
dmesg --time-format=iso 2>/dev/null | grep -iE "sda|usb-storage|sd 0:" | grep -viE linuwu | tail -20
date '+fim: %F %T'
echo "########## FIM ##########"
