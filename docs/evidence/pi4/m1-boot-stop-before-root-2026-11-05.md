# M1 estável — boot parou antes do root (2026-11-05)

Cartão regravado com `cb76c565…` e ligado no Pi. O ecrã mostrou erro e o boot não seguiu. De volta ao leitor, o disco não guardou esse erro.

## O que mudou
- Logdump, LBA 4259840: zero. O dumper continua desligado no `initfs`.
- Só a partição EFI difere da imagem. O U-Boot reescreveu `ubootefi.var` (`Boot0000`, `BootOrder`, `PlatformLang=en-US`).
- A partição RedoxFS está igual à imagem. O root não chegou a ser montado. `/var/log` não teve oportunidade de receber nada.

## Leitura
O firmware chegou ao U-Boot. O kernel Redox, ou o `initfs`, parou antes de abrir o RedoxFS. Não é o hang do `network.genet`: nesse caso o superbloco do RedoxFS tinha sido reescrito.

A imagem no cartão continua a ser a que já mostrou `aios login:`. Regravar a mesma imagem não traz o texto do erro.
