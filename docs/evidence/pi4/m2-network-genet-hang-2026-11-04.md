# M2 hang — `NetworkScheme` no GENET (2026-11-04)

## Sintoma
Após writeback do `bcm2711-genetd` M2 (`network.genet` + loop `tick`), o Pi
**não chega a login**. Cartão relido: sem breadcrumbs `net-*` em `/var/lib/ai`
(hang antes de flush ou dentro de `NetworkScheme::new` / primeiro `tick`).

## Binários
| Perfil | md5 | Resultado |
|--------|-----|-----------|
| M1 beacon-only | `96ceeaa61d2a13a7df417e977ee4b8f5` | login + beacons `0x88b5` |
| M2 NetworkScheme | `1af1edf3473969f7c61e388de8153db0` | hang (reproduz etapa7) |

## Acção
- Cartão restaurado para p3 M1 (`/var/tmp/pi4-verify-p3.img`) e ejetado.
- PR M2 ([rodriguesfas/redox#3](https://github.com/rodriguesfas/redox/pull/3)) **não mergear** até haver
  path estável (IRQ ou scheme fora do caminho crítico de boot) + testes.
- Regressão automatizada: crate `pi4-contract` + `scripts/pi4-regression-guard.sh`
  (default = beacon-only; `NetworkScheme::new` só atrás de feature `network-scheme`).

## Lição
RING_CFG correcto **não** basta para M2. Registar `NetworkScheme` no mesmo
daemon que faz o bring-up ainda trava o board no HW actual.
