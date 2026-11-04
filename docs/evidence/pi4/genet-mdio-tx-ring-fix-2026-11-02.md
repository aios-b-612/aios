# GENET: DMA_RING_CFG + MDIO dump (2026-11-02)

## Causa do `tx timeout`

Em `tx_ring_init` / `rx_ring_init`, `DMA_RING_CFG` estava com
`1 << (DEFAULT_Q + DMA_RING_BUF_EN_SHIFT)` (bit **17**).

U-Boot/Linux usam:

- `DMA_RING_CFG` → `1 << DEFAULT_Q` (bit **16**)
- `DMA_CTRL` → `1 << (DEFAULT_Q + DMA_RING_BUF_EN_SHIFT) | DMA_EN` (bit **17** + EN)

O anel default (q=16) nunca era habilitado → `CONS_INDEX` não avançava →
`beacon N err: tx timeout`.

Também faltava `DMA_START_ADDR = 0` no anel TX (presente no RX e no U-Boot).

## MDIO / PHY

DTB do cartão: `ethernet-phy@1`, `phy-mode = rgmii-rxid` (phyaddr **1** OK).

Driver passa a:

- dump `BMCR/BMSR/PHYID` + scan 0..31 no boot e no loop se `link=0`
- status MDIO explícito (`ok` / `timeout` / `fail`) — antes timeout virava `0` silencioso
- timeout MDIO 100 ms; write/read no padrão U-Boot (cmd + START_BUSY)

## Artefacto

- binário `bcm2711-genetd` md5 `6b4f7b59fbbfdff5e5d772196cfd1c50`
- imagem `/tmp/aios-edge-pi4-sd-mdio-tx.img` md5 `fb73546fbb71fe110b9e77541cd0baa5`
- copiada para `redox-os/build/aarch64/pi4/{aios-edge-pi4-sd,harddrive}.img`

## Flash

- `pkexec dd` → `/dev/sda` (2 GiB), `FLASH_OK` (~12:52 local).
- Cartão ejetado (`udisksctl power-off`).

## Boot 2026-11-02 ~10:04 (após flash ring-fix)

- `enp63s0` carrier up, **100 Mbps Full**; partner anuncia 10/100/1000.
- `rx_packets=0` durante >2 min; `tcpdump 0x88b5` = 0.
- `ethtool -S`: `align_errors` a subir (~6k) → sinal no fio, framing errado.
- Hipótese: soft-fail do PHY punha **UMAC @ 10** enquanto PHY autonegociava **100**.

## Fix follow-up (speed100)

- Default soft-fail / MDIO-blind → `max_speed=100` + `adjust_link`.
- Imagem `/tmp/aios-edge-pi4-sd-speed100.img` md5 `e741c0c8bbfe9aa6fdc7452220d63b0f`
  (bin `96ceeaa61d2a13a7df417e977ee4b8f5`).
- Pendente: desligar Pi, reflash do cartão, novo boot.
