# Boot parava antes do root — offset do RedoxFS (2026-11-06)

Dois arranques da imagem estável não chegaram ao login. O logdump ficou a zero e a partição RedoxFS não foi escrita. O U-Boot tinha corrido (variáveis EFI).

## Causa
O `BOOTAA64.EFI` procura o RedoxFS. Se o firmware publica a partição lógica, o offset é 0 e o boot segue. Se só publica o disco inteiro, o offset estava fixo em 2 MiB. Nesta imagem a partição REDOX começa no LBA 264192 (ESP de 128 MiB). O ecrã fica em `No RedoxFS partitions found` e o root não abre.

## Correção no cartão
- EFI novo em `EFI/BOOT/BOOTAA64.EFI` (135680 bytes), com `AIOS: RedoxFS GPT`.
- Backup do EFI anterior: `/tmp/BOOTAA64-before-gpt.efi`.
- Fonte: [redox#7](https://github.com/aios-b-612/redox/pull/7), em `dev`.
- O driver GENET não mudou. Continua o binário M1, sem `network.genet`.

O próximo arranque tem de passar de `Looking for RedoxFS:` e chegar a `aios login:`.
