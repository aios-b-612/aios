# Login OK; PHY link=0; beacon tx timeout (2026-11-02)

Logdump `seq=32`, ~336 s. RJ45 LEDs apagados no Pi; PC `carrier` flaky.

## O que funciona
- Boot → `aios login:` (beacon-only / `daemon.ready` cedo).
- genetd sobe: etapas 0–7 (`beacon-only M1`).
- Loop corre: `phy link=0 speed=10`, `beacon N err: tx timeout` (dezenas de vezes).

## O que falha
1. **MDIO/PHY**: BMSR nunca reporta link (bit 2). LEDs RJ45 off.
2. **TX DMA**: `tx timeout` — descriptor não completa (MAC/DMA/clocks ou PHY down a impedir TX).

PC chegou a ver `carrier=1 @ 100Mb/s` por alguns segundos no boot → o cobre/PHY físico pode ligar; o driver não mantém/lê link.

## Próximo
- Dump MDIO regs (BMSR/BMCR/PHYID) no log.
- Confirmar `phyaddr` no DT vs BCM54213.
- Revisar enable TX path com link down (Linux genet força RGMII_LINK?).
