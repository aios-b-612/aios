# Boot não avançou: redoxfs abort (2026-11-02)

## Sintoma
Ecrã/serviço não chega a `aios login:`. Logdump LBA 4259840
(`logdump-bootfail-2026-11-02-101052.bin`):

1. `pcid` panic (esperado em aarch64).
2. `init: switchroot to /usr /etc` — mount OK.
3. `Lacks grant` + data abort em `/scheme/initfs/bin/redoxfs`.
4. `removing handle: Partition(0, 2)`.
5. Cascata `ENOENT` — `getty`, `bcm2711-genetd`, `edge-ai`, …

Mesmo padrão de `diag-redoxfs-crash-2026-11-01.md`.

## Causa
`bcm2835-sdhcid` `logdump.rs` tinha `MOUNT_QUIET = 3s` (baixado de 20s).
O primeiro dump multi-bloco compete com o mount → abort do redoxfs.

## Correção
- Fonte: `MOUNT_QUIET` de volta a **20s**.
- Cartão: patch in-place no `initfs` (`mov #3` → `mov #20` @ sdhcid) +
  `bcm2711-genetd` speed100 (`96ceeaa6…`).
- Imagem: `/tmp/aios-edge-pi4-sd-quiet20-speed100.img`
  md5 `8720ff75cae797fb9d8edad3dd82d6cb`.
