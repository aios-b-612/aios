# Login sumiu: genetd `notify` bloqueava o init

## Causa
Com o path absoluto corrigido, `bcm2711-genetd` passou a arrancar.
Em `phy no link` entrava em `loop { sleep }` **sem** `daemon.ready()`.
O unit é `type = "notify"` → init espera forever → sem getty/`aios login:`.

## Fix (reflash 2026-11-01 ~16:31)
- `phy_init`: sem link após 5s → segue a 100 Mbps (não hard-fail).
- Erros fatais restantes: `daemon.ready()` antes do sleep-loop.
- Binário novo + unit path absoluto na SD (`FLASH_OK`, md5 img `ac2ff1a0…`).
