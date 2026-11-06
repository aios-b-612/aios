# M1 estável — segundo boot também parou antes do root (2026-11-06)

Novo arranque no Pi, sem `aios login:`. Cartão de volta ao leitor `14cd:1212`.

## Disco
- Logdump LBA 4259840: zero.
- Diferença para `/tmp/aios-edge-pi4-sd-m1-stable.img` (`cb76c565…`): só os dois intervalos da partição EFI já vistos em 2026-11-05 (variáveis do U-Boot). A partição RedoxFS não foi escrita.

O firmware chega ao U-Boot. O kernel ou o `initfs` param antes de abrir o RedoxFS. O texto do ecrã continua fora do cartão.
