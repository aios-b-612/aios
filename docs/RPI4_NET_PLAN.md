# Plano: comunicação de rede no Raspberry Pi 4 (AIOS Edge)

Status: **M1 fechado 2026-11-04** — boot login + beacons `0x88B5` no cabo
(evidência [`evidence/pi4/m1-validated-2026-11-04.md`](evidence/pi4/m1-validated-2026-11-04.md)).
Imagem estável: genet TX (RING_CFG/100 Mbps) + logdump SDHCI desligado.
Próximo: M2 RX/`network.genet` (#47).

## Objetivo
PC orquestra nós Pi pelo cabo (depois Wi‑Fi). Sem teclado/UART no Pi.

## Realidade do ambiente (2026-11-01)
- **Boot real no Pi 4**: chega a `aios login:` / console HDMI.
- GENET **não é emulado no QEMU** → beacon/DHCP só no hardware.
- Imagem SD: `redox-os/build/aarch64/pi4/aios-edge-pi4-sd.img`.
- Wi‑Fi (BCM43455/SDIO) = [#48](https://github.com/aios-b-612/aios/issues/48) (próximo ciclo).
- OTA = [#45](https://github.com/aios-b-612/aios/issues/45) (próximo ciclo).

## Fases

- **M0 / v0.1 (feito)**: boot SD → userspace → login HDMI; branding AIOS.
- **M1 (feito 2026-11-04)**: beacons TX `0x88B5` / `AIOS-BOOT` no Pi 4 real (#44).
- **M2 (em validação HW)**: RX + `network.genet` → netstack/DHCP → ping (#47); PR redox #3.
- **C0 cluster (CLI pronta)**: `aios-deploy scan|provision|probe` no PC.
- **M3**: OTA / shell pela rede.
- **M4**: Wi‑Fi.

## Como testar agora (C0)

1. Pi: energia + RJ45 ↔ PC `enp63s0` (share `10.42.0.0/24`). Sem teclado.
2. HDMI: banner AIOS + `aios login:` (#50).
3. PC:
   ```bash
   sudo tcpdump -i enp63s0 -nn -c 5 'ether proto 0x88b5'
   cargo run -p aios-deploy -- scan 10.42.0
   cargo run -p aios-deploy -- provision 10.42.0.X
   cargo run -p aios-deploy -- probe 10.42.0.X:8989
   ```
4. Checklist: [`evidence/pi4/test-hoje-cluster-2026-11-01.md`](evidence/pi4/test-hoje-cluster-2026-11-01.md).
5. Visão cluster: [`CLUSTER.md`](CLUSTER.md).

## Arquivos-chave
- `recipes/core/base/source/drivers/net/bcmgenetd/` (daemon)
- `recipes/core/base/source/init.d/10_bcm2711-genetd.service`
- `config/aarch64/aios.toml` → `50_aios_edge.service`
- `deploy/` → `aios-deploy scan|provision|probe`
- Evidências: `docs/evidence/pi4/`

## Referências
- U-Boot `drivers/net/bcmgenet.c` (init/TX/RX/MDIO/PHY).
- Linux `drivers/net/ethernet/broadcom/genet/bcmgenet.h` (registradores).
- Template: `recipes/core/base/source/drivers/storage/bcm2835-sdhcid/`.
