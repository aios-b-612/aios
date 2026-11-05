# M2 gated gravado no cartão (2026-11-05)

Imagem de teste com `network.genet` atrás da feature, serviço `oneshot_async`, logdump desligado. O boot no Pi ainda não foi feito.

## Cartão
- Leitor USB `14cd:1212`, `/dev/sda`, removível, 59,5 GiB.
- Imagem `/tmp/aios-edge-pi4-sd-m2-gated.img`, md5 `e2693fa93e5622a1290e21dd99237758`.
- `dd` do disco inteiro (2 GiB). A primeira leitura de volta falhou em três intervalos de 112 sectores (56 KiB), LBA 1023488, 1264128 e 1423872. Esses intervalos foram reescritos. Com cache descartada e I/O directo, o md5 dos 2 GiB coincidiu com a imagem.
- Logdump LBA 4259840, 257 sectores, a zero.
- Cartão ejetado (`udisksctl power-off`).

## Conteúdo conferido no RedoxFS
- `/usr/lib/drivers/bcm2711-genetd` md5 `a45bb0e9f1998a38a478cf96d30a8ad4`.
- O binário contém `network.genet registered` e `beacon-only M1`.
- `/usr/lib/init.d/10_bcm2711-genetd.service`: `cmd` absoluto, `type = oneshot_async`.
- `initfs` em `/usr/lib/boot/initfs`, ELF no offset 15425536: NOP `1f2003d5` em `+0x10d28`, RET `c0035fd6` em `+0xc55c`.

## Se o login não aparecer
Voltar a imagem estável `/tmp/aios-edge-pi4-sd-m1-stable.img` (md5 `cb76c56573c9301f8395123873088c44`, genetd `96ceeaa6…`) com `dd` do disco inteiro.
