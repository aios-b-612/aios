# Boot travou após restore M1 (2026-11-04)

## Factos no cartão
- `bcm2711-genetd` md5 `96ceeaa6…` (M1 beacon-only) — OK
- initfs: patch nologdump presente (`NOP` + `RET` em spawn) — OK
- Sem breadcrumbs `net-*` novos
- LBA 4259840 tinha **log antigo** (logdump+`Lacks grant`+TX timeout) — enganador; zerado

## Hipótese
`10_bcm2711-genetd.service` em `type=notify` pode segurar o bring-up se
`genet.init()`/MDIO atrasar antes de `daemon.ready()`.

## Mitigação gravada no cartão
- Serviço → `oneshot_async` (init não espera ready)
- p3 = verify M1 + nologdump
- LBA logdump zerado

Próximo boot: login HDMI esperado; beacons se PHY ok.
