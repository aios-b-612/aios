# Reflash + genetd path fix — 2026-11-01 16:22

- Imagem mestra `aios-edge-pi4-sd.img` (md5 `4a86f6d3…`) + patch unit:
  `cmd = "/usr/lib/drivers/bcm2711-genetd"` + symlink `/usr/bin/bcm2711-genetd`
- Artefacto gravado: `/tmp/aios-edge-pi4-sd-genetfix.img` md5 `5d965d62d4853369613b46a940479075`
- `dd` → `/dev/sda`, `cmp` OK, logdump LBA 4259840 zerado

## Teste
1. Cartão no Pi + RJ45 ↔ `enp63s0`
2. HDMI: `aios login:` (sem ENOENT em massa)
3. PC: `sudo tcpdump -i enp63s0 -nn -c 5 'ether proto 0x88b5'`
4. Se beacon: `cargo run -p aios-deploy -- scan 10.42.0`
