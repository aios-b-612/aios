# Diagnóstico: redoxfs cai no Pi 4 real após switchroot (2026-11-01)

## Evidência
- Logdump cru LBA 4259840: `logdump-hardware-2026-11-01.log`
- Header: `seq=62 elapsed_ms=455149 len=92529` (~7,5 min ligado)

## Sequência no hardware
1. EMMC2/SDHCI inicia; cartão 60906 MiB OK.
2. `logdump` começa **na hora** (`seq=1` em `t=0ms`, dezenas de KiB via PIO).
3. `pcid` panic (esperado em aarch64 sem PCIe/ACPI) — também no QEMU.
4. `redoxfs` sonda `disk.mmc/0`, `0p0`, `0p1` (não são RedoxFS) → erros normais.
5. Lista de partições: `0 / 0p0 / 0p1 / 0p2` — OK.
6. `init: switchroot to /usr /etc` — **mount de 0p2 funcionou**.
7. `Lacks grant` + data abort `FAR=0x40` / `ESR=0x92000007` em
   `/scheme/initfs/bin/redoxfs` → handle `Partition(0, 2)` removido.
8. Depois disso, `bcm2711-genetd` / `netstack` / `edge-ai` → ENOENT/ENODEV.

## Contraste com QEMU (probe7b, 2026-10-16)
Mesmo panic do `pcid` e mesmas falhas de sonda 0/0p0/0p1, mas **redoxfs
sobrevive** e chega a `redox login:`. Esses probes **não** tinham o logdump
agressivo (imagem de 16/10; logdump entrou depois).

## Causa provável
O logdump segurava o `Mutex` do SDHCI durante `write_blocks` de ~35–128 KiB
(bloco a bloco, PIO) a cada 2 s **durante** o mount e o exec inicial. Isso
esfomeia o `DiskScheme`/`redoxfs` na janela crítica. No hardware real o
sintoma é o abort; no QEMU a corrida não se reproduziu nos probes antigos.

## Correção aplicada
`bcm2835-sdhcid/src/logdump.rs`:
1. Marker de 1 bloco imediato (prova que o dumper subiu).
2. Quiet de 20 s antes do primeiro dump completo.
3. Escrita bloco a bloco **soltando o mutex** entre blocos.
4. Intervalo rápido 5 s (depois do quiet).

Próximo: rebuild `aarch64`/`pi4`, regravar cartão, ler logdump de novo —
esperado: `bcm2711-genetd` a correr e/ou beacons `0x88B5`.
