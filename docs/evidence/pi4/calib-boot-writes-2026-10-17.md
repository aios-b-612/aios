# Calibração: um boot completo grava no cartão? (2026-10-17)

**Objetivo.** Saber se o boot do artefato AIOS (`aios-edge-pi4-sd.img`) deixa
bytes gravados no cartão — para usar "comparar o cartão pós-boot com a imagem
mestre" como **detector de boot** no Raspberry Pi físico (sem monitor/serial).

## Método

1. Cópia do artefato para `wrtest.img` (o artefato original não foi tocado).
2. QEMU com o mesmo setup do `probe7c` (raspi4b, u-boot `rpi_4-u-boot.bin`,
   `dtb-emmc-swap.dtb`), **sem `-snapshot`** → escritas reais no arquivo.
3. Boot até `redox login:` (t+49s), 20s parado, desligamento via QMP.
   Nenhum comando enviado no serial (equivalente ao hardware: ninguém loga).
4. Comparação byte a byte do `wrtest.img` vs artefato mestre (p1/p2/p3).

## Resultado

- **p1**: 0 bytes diferentes.
- **p2 (FAT/ESP)**: 309 bytes em 4 regiões — spans rel [3768..3769],
  [134840..134841], [262976..263037], [3609096..3609550].
- **p3 (redoxfs)**: **24.445 bytes**; primeira região ≈ rel 458.793 — é o
  cabeçalho/metadados do redoxfs (UUID `625b072a-6402-4215-821e-0d7746df16c2`
  presente; contadores e checksums atualizados). Demais regiões ≈ rel 724–766 MB.
- Lista completa de faixas: `calib-diff-ranges-2026-10-17.txt`.

## Conclusão

Um boot que chega ao login **grava marcas detectáveis** (~24 KB no sistema de
arquivos + ~300 B na partição de boot). Portanto, ao comparar o cartão físico
pós-boot com a imagem mestre:

- **Com diferenças** → o boot avançou até montar/escrever no redoxfs (sinal
  positivo forte; não prova login, mas prova kernel/init bem adiantado).
- **Idêntico** → **inconclusivo** (pode ter parado antes de escrever): usar
  LEDs + serial para investigar.

## Artefatos

- `calib-wrprobe-2026-10-17.py` — harness usado (adapta o probe7c).
- `calib-wrprobe-serial-2026-10-17.log` — serial do boot de calibração.
- `calib-diff-ranges-2026-10-17.txt` — faixas precisas de diferença.
- (temporário, não versionado: `/tmp/opencode/pi4tb/wrtest.img`, 2 GiB)
