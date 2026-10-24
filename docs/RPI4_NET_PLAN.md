# Plano: comunicação de rede no Raspberry Pi 4 (AIOS Edge)

Status: **Fase 1 (M1) implementada — aguardando teste no hardware.**

## Objetivo
Fazer o AIOS Edge (Redox) se comunicar com este PC pelo cabo RJ45, sem
adaptador serial, e permitir atualização do SO pela rede.

## Realidade do ambiente
- GENET (Ethernet do Pi 4) **não é emulado no QEMU** (qemu 9.2.1 imprime
  "brcm,bcm2711-genet-v5 has been disabled!"). Portanto o desenvolvimento do
  driver é feito no **hardware real**, com canais de diagnóstico cegos:
  1. **LED verde (GPIO42)** — padrões de piscada por estágio.
  2. **Pacotes no cabo** — PC faz `tcpdump` na enp63s0 (beacons EtherType 0x88B5).
  3. **Diário no cartão** — `/var/lib/ai/net-stage` (lido depois via QEMU boot).
  4. **Fallback** — regravar o cartão (já dominado).
- Wi-Fi (BCM43455/SDIO) fica para fase posterior — é um projeto bem maior;
  o cabo resolve comunicação + atualização.

## Fases

- **M1 (feito)**: daemon `bcm2711-genetd` (plataforma, sem pcid) — init GENET
  (MMIO, PHY/MDIO, DMA rings, MAC TX/RX), TX de beacons a cada 2s, LED por
  estágio, diário no cartão. Kernel: registro de /scb (device memory).
  Build: imagem `aios-edge-pi4-sd.img` (md5 `3941e7b64fc3c98809d261f5137aea57`).
- **M2**: RX ring + NetworkScheme (`network.genet`) → netstack + dhcpd → Pi
  ganha IP via DHCP → ping funciona.
- **M3**: canal bidirecional (ctl + raw frames) e serviço de comandos/arquivos
  para atualização do SO pela rede (PC serve, Pi busca com curl ou protocolo
  próprio; remote shell simples).
- **M4 (opcional)**: Wi-Fi.

## Como testar (M1)
1. Gravar: `sudo dd if=build/aarch64/pi4/aios-edge-pi4-sd.img of=/dev/sdX bs=4M conv=fsync`
2. Ligar o Pi; olhar LED verde (vermelho fixo = energia ok).
3. No PC: `sudo tcpdump -i enp63s0 -nn 'ether proto 0x88b5'` — deve aparecer
   pacotes "AIOS-BOOT ..." se GENET TX funcionou.
4. Reportar: padrão do LED + se apareceram pacotes.
5. (Opcional, pós-teste) trazer o cartão ao PC → comparar com a imagem mestra;
   diferenças = boot avançou; ler `/var/lib/ai/net-stage` via boot QEMU.

## Arquivos-chave
- `recipes/core/base/source/drivers/net/bcmgenetd/` (daemon)
- `recipes/core/base/source/init.d/10_bcm2711-genetd.service`
- `recipes/core/kernel/source/src/dtb/mod.rs` (/scb fix)
- Evidências: `docs/evidence/pi4/`

## Referências
- U-Boot `drivers/net/bcmgenet.c` (init/TX/RX/MDIO/PHY).
- Linux `drivers/net/ethernet/broadcom/genet/bcmgenet.h` (registradores).
- Template: `recipes/core/base/source/drivers/storage/bcm2835-sdhcid/`.