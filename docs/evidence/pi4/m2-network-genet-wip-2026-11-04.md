# M2 WIP — `network.genet` (2026-11-04)

## Código
- `bcm2711-genetd`: após init GENET, `NetworkScheme::new(..., "network.genet")`.
- Loop poll 2 ms + `tick()`; beacons `AIOS-BOOT` a cada 2 s.
- Binário aarch64: md5 `1af1edf3473969f7c61e388de8153db0`.
- Imagem p3 pronta: `/tmp/pi4-m2-p3.img` (base = p3 nologdump validado M1).

## Flash
```bash
# Cartão no leitor USB (block real, não ficheiro)
/tmp/flash-m2-genetd.sh /dev/sda
```

## Aceite (pendente HW)
1. Boot → login (sem regressão logdump).
2. Beacons `0x88b5` continuam.
3. PC: lease DHCP / ping ao Pi.
4. Sem hang na etapa 7.

PR driver: https://github.com/rodriguesfas/redox/pull/3
