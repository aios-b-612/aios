# M1 estável regravado depois do hang M2 (2026-11-05)

O boot da imagem M2 gated não chegou ao login e não deixou log. O cartão voltou à imagem que já mostrou `aios login:`.

## Gravação
- Leitor `14cd:1212`, `/dev/sda` removível.
- Imagem `/tmp/aios-edge-pi4-sd-m1-stable.img`, md5 `cb76c56573c9301f8395123873088c44`.
- A primeira leitura de volta diferia num intervalo de 112 sectores (56 KiB), LBA 1446400. Reescrito. Com I/O directo, o md5 dos 2 GiB coincidiu.
- Logdump LBA 4259840, 257 sectores, a zero.
- Cartão ejetado.

O binário M2 (`a45bb0e9…`, `network.genet`) não volta ao cartão enquanto o registo do scheme puder prender a máquina depois do mount do root.
