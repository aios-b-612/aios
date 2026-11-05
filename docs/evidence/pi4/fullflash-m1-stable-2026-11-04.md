# Full flash M1 estável (2026-11-04 ~15:45)

Boot sem login após restores só de p3. LBA logdump vazio (patch off).

## Acção
- Base: `aios-edge-pi4-sd-quiet20-speed100.img`
- Patch nologdump no initfs (NOP+RET)
- genetd M1 `96ceeaa6…`
- serviço `oneshot_async`
- **dd do disco inteiro** → `/dev/sda` (boot+EFI+root)
- md5 imagem: `cb76c56573c9301f8395123873088c44`
- Verificado no cartão antes de ejetar

Artefacto local: `/tmp/aios-edge-pi4-sd-m1-stable.img`

## Resultado (2026-11-05)

- HDMI: `aios login:` (confirmado no Pi).
- Cabo: `enp63s0` 100 Mb/s Full, `LOWER_UP`. Sem lease DHCP (esperado em M1).
