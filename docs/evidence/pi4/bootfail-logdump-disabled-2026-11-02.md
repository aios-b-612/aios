# Boot estável: logdump desligado (2026-11-02)

## Por que “não avançava”
O crash **não era o genet**. Sequência repetida no logdump:

1. `switchroot to /usr /etc`
2. `Lacks grant` → abort do `redoxfs` → `Partition(0,2)` removida
3. Cascata `ENOENT` (getty, genetd, edge-ai…)

O dumper SDHCI (markers `boot-0`/`boot-1` + dumps) compete com o mount
no mesmo controller. Quiet 3s ou 20s **não bastou** — o abort acontece
ainda na janela do switchroot; `post-quiet` só aparece *depois* no buffer.

## Correção desta vez (uma só)
- `initfs` / `bcm2835-sdhcid`: **NOP** no `bl logdump::spawn` + `ret` no
  início de `spawn` (logdump não corre).
- Fonte: `main.rs` deixa de chamar `logdump::spawn`.
- `bcm2711-genetd` mantém fixes TX (`DMA_RING_CFG`) + default 100 Mbps.

Sem logdump automático até haver caminho pós-login / serial.
