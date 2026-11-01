# Cluster doméstico AIOS Edge

Orquestrador no PC + nós Raspberry Pi 4 com AIOS Edge.
Prioridade: **conectividade + gestão** antes de agentes avançados.

## Epic e issues

| Issue | Gap |
|------|-----|
| [#49](https://github.com/aios-b-612/aios/issues/49) | Epic cluster |
| [#50](https://github.com/aios-b-612/aios/issues/50) | Branding AIOS no login |
| [#44](https://github.com/aios-b-612/aios/issues/44) | M1 GENET TX (beacon) |
| [#47](https://github.com/aios-b-612/aios/issues/47) | M2 `network.genet` + DHCP/ping |
| [#51](https://github.com/aios-b-612/aios/issues/51) | `edge-ai` alcançável no cabo |
| [#52](https://github.com/aios-b-612/aios/issues/52) | Controlo sem teclado (HTTP) |
| [#53](https://github.com/aios-b-612/aios/issues/53) | Fleet provision mínimo |
| [#45](https://github.com/aios-b-612/aios/issues/45) | M3 OTA pela rede |
| [#48](https://github.com/aios-b-612/aios/issues/48) | M4 Wi‑Fi onboard |

Plano de rede: [`RPI4_NET_PLAN.md`](RPI4_NET_PLAN.md).

## Teste mínimo de hoje (C0) — cartão já flashado

md5 gravado: `4a86f6d3d01b834a300d05108e47b412`.

1. Cabo RJ45: Pi ↔ PC (`enp63s0`, rede partilhada `10.42.0.0/24`).
2. HDMI: banner AIOS + `aios login:` (#50).
3. PC: `sudo tcpdump -i enp63s0 -nn -c 5 'ether proto 0x88b5'` (#44).
4. Após lease:
   ```bash
   cargo run -p aios-deploy -- scan 10.42.0
   cargo run -p aios-deploy -- provision 10.42.0.X
   cargo run -p aios-deploy -- probe 10.42.0.X:8989
   ```
5. Sem teclado no Pi — só cabo + energia (#52).

Checklist: [`evidence/pi4/test-hoje-cluster-2026-11-01.md`](evidence/pi4/test-hoje-cluster-2026-11-01.md).

## Fora do teste de cabo (próximo ciclo)

- [#45](https://github.com/aios-b-612/aios/issues/45) M3 OTA  
- [#48](https://github.com/aios-b-612/aios/issues/48) M4 Wi‑Fi onboard  
