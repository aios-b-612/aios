# M1 validado no hardware — GENET TX `0x88B5` (2026-11-04)

Fecha [#44](https://github.com/aios-b-612/aios/issues/44).

## Aceite

| Critério | Resultado |
|----------|-----------|
| Boot SD → userspace / login HDMI | OK — `aios login:` (2026-11-03 e 2026-11-04) |
| Beacon `AIOS-BOOT` no cabo | OK — 5 frames `0x88b5` no PC (`enp63s0`) |
| MAC do nó | `dc:a6:32:fd:f9:6f` |
| Link PHY | 100 Mb/s Full, `LOWER_UP` (LED RJ45 aceso) |
| Estabilidade | Login + beacons contínuos; sem abort redoxfs nesta imagem |

## Artefactos

- Captura: [`m1-beacon-tcpdump-2026-11-03.txt`](m1-beacon-tcpdump-2026-11-03.txt)
- Link vivo (recheck com Pi no login): [`m1-link-alive-2026-11-04.txt`](m1-link-alive-2026-11-04.txt)
- Bloqueio de boot (logdump vs redoxfs) e fix: [`bootfail-logdump-disabled-2026-11-02.md`](bootfail-logdump-disabled-2026-11-02.md), [`bootfail-redoxfs-quiet3-2026-11-02.md`](bootfail-redoxfs-quiet3-2026-11-02.md)
- TX stall / `DMA_RING_CFG`: [`genet-mdio-tx-ring-fix-2026-11-02.md`](genet-mdio-tx-ring-fix-2026-11-02.md)
- Flash falso para ficheiro `/dev/sda`: [`false-flash-dev-sda-file-2026-11-02.md`](false-flash-dev-sda-file-2026-11-02.md)

## Fixes aplicados na imagem estável

1. **`bcm2835-sdhcid`**: `logdump::spawn` desligado (corrida com switchroot → `Lacks grant` / ENOENT).
2. **`bcm2711-genetd`**: `DMA_RING_CFG` bit `DEFAULT_Q` (não `16+SHIFT`); `TDMA_START_ADDR=0`; default 100 Mbps / soft-fail MDIO; `daemon.ready()` antes do loop beacon (tipo `notify`).

Fonte no tree Redox (clone local `redox-os/`, remoto `rodriguesfas/redox`).

## Fora de M1

- Sem IP / DHCP / ping → [#47](https://github.com/aios-b-612/aios/issues/47) (M2 `NetworkScheme`).
- Sem `/scheme/network.genet` nesta imagem (beacon-only de propósito).
