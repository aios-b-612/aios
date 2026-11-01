# Teste cluster mínimo — 2026-11-01

## Flash
- Cartão `/dev/sda` gravado com `aios-edge-pi4-sd.img`
- md5 `4a86f6d3d01b834a300d05108e47b412`
- LOG_LBA 4259840 zerado

## No Pi
1. Cabo RJ45 → PC (`enp63s0`, share `10.42.0.0/24`)
2. HDMI: banner **AIOS Edge**, prompt `aios login:` (#50)
3. Sem teclado: serviços sobem sozinhos (genetd + netstack + edge-ai)

## No PC
```bash
# beacons M1
sudo tcpdump -i enp63s0 -nn -c 5 'ether proto 0x88b5'

# descobrir nó (após lease)
aios-deploy scan 10.42.0
aios-deploy provision 10.42.0.X    # IP do lease
aios-deploy probe 10.42.0.X:8989
aios-deploy devices
```

## Issues cobertas neste artefacto
| # | Esperado no teste |
|---|-------------------|
| 50 | ecrã AIOS |
| 44 | tcpdump AIOS-BOOT |
| 47 | IP + ping |
| 51 | curl/probe :8989 |
| 52 | sem teclado |
| 53 | scan/provision CLI |
