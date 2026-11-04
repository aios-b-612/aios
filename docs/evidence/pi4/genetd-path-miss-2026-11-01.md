# GENET: zero frames no cabo — daemon nunca arrancou

Data: 2026-11-01. Pi boot OK (`aios login:`), `enp63s0` carrier up, `rx_packets=0`.

## Achado no cartão (RedoxFS p3)

- Presentes: `/usr/lib/drivers/bcm2711-genetd`, `10_bcm2711-genetd.service`, `edge-ai`.
- Ausentes: `/var/lib/ai/net-00` … `net-07` e `boot-*.log` → **nenhuma etapa do genetd**.
- `/usr/bin/bcm2711-genetd` **não existia**.

## Causa

`init` define `PATH=$prefix/bin` e faz `Command::new(cmd)`.
O unit tinha `cmd = "bcm2711-genetd"` (nome curto). O binário só está em
`/usr/lib/drivers/` (padrão dos drivers PCI via `pcid-spawner`).
Resultado: `failed to execute` → sem TX / sem beacons.

## Correcção aplicada no cartão

- `cmd = "/usr/lib/drivers/bcm2711-genetd"`
- symlink `/usr/bin/bcm2711-genetd` → `../lib/drivers/bcm2711-genetd`
- Mesmo fix na recipe `init.d/10_bcm2711-genetd.service`

## Re-teste

1. Cartão no Pi + RJ45 + `sudo tcpdump -i enp63s0 -nn -c 5 'ether proto 0x88b5'`
2. Esperado: `AIOS-BOOT`; depois `aios-deploy scan 10.42.0`
