# Flash falso: `/dev/sda` era ficheiro (2026-11-02)

## O que aconteceu
O `pkexec dd … of=/dev/sda` reportou `FLASH_OK` a ~567 MB/s (3,8 s).
No host, `/dev/sda` e `/dev/sda3` eram **ficheiros regulares** (2 GiB / 1,9 GiB),
não block devices — a imagem foi escrita para o filesystem do PC, não para o
cartão. O leitor USB Mass Storage **não aparecia** em `lsusb` / `/sys/block`.

## Efeito
O Pi continuou a arrancar a imagem antiga (quiet=3 s) → redoxfs abort → boot
com erro; beacons ausentes.

## Recuperação
1. `rm` dos ficheiros rogue em `/dev/sda*`.
2. Reinserir o leitor; confirmar `lsblk` com `TRAN=usb` / `RM=1`.
3. `dd` real para o block device (script `/tmp/fix-dev-sda-and-flash.sh`).
