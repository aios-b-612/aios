# M2 gated — boot travou, sem log (2026-11-05)

Cartão de volta no leitor depois do teste da imagem `e2693fa9…`. Não há texto de boot para ler.

## O que está vazio
- Logdump, LBA 4259840, 257 sectores: tudo zero. O dumper está desligado no `initfs` (NOP+RET), por isso este boot não gravou traço.
- `/var/log` vazio. Sem ficheiros `net-*`. `/var/lib/ai/registry.tsv` é o registo do modelo que já vinha na imagem.

## O que o disco mostra
- A imagem e o cartão diferem. U-Boot actualizou as variáveis EFI (`UBOOTEFIVAR`).
- O superbloco RedoxFS e blocos de metadados foram reescritos. O root chegou a ser montado.
- O texto legível nesses blocos é o das units já gravadas (`oneshot_async` no genetd, `notify` no netstack, `dhcpd`) e o `registry.tsv`. Não é uma linha nova de log. Restos de comentário no slack do bloco (`retry de 10s`, `/scheme/network*`) já estavam na imagem.

## Leitura
O arranque passou do firmware e montou o root. A partir daí não persistiu nada. O `oneshot_async` do genetd não chegou a mostrar `aios login:`. O netstack (`type = notify`) espera até 10 s por `/scheme/network*` e, se sair sem `ready()`, o init regista a falha e segue; um ecrã parado não se explica só por essa espera.

Imagem estável ainda em `/tmp/aios-edge-pi4-sd-m1-stable.img` (`cb76c565…`).
