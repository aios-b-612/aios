# logdump: marker imediato (2026-11-01)

## Hipótese
Após quiet de 20s, LBA 4259840 ficou zero pós-hang → sdhcid nunca persistiu.
Marker volta ao caminho single-block `write_blocks` (já comprovado em HW), tags `boot-0`/`boot-1`/`post-quiet`, quiet 3s.

## Imagem gravada
- `aios-edge-pi4-sd.img` md5 `8fb1d10982703c9774186c0f1861b8c4`
- cartão: markers `boot-0`/`boot-1`/`post-quiet` presentes; `boot-quiet` ausente; LOG_LBA zerado

## Leitura após boot
`./scripts/read-pi4-logs.sh /dev/sda`
Esperado se sdhci sobe: header `AIOS-SDHCI-LOGDUMP` com `marker=boot-0` (ou dump completo).
