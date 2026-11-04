# Boot falhou após fix do path do genetd (2026-11-01 ~16:12)

## Sintoma
Utilizador reportou erro no Pi. No PC, `tcpdump` sem filtro só viu tráfego
do próprio host (`10.42.0.1`); sem beacons `0x88b5`.

## Logdump (LBA 4259840, seq=6, ~29.6 s)

Ficheiro: `docs/evidence/pi4/logdump-2026-11-01-*.log` (hora da leitura).

### 1. Path do genetd — fix aplicado
```
init: failed to execute ... "/usr/lib/drivers/bcm2711-genetd": No such file or directory
```
O unit já usa o caminho absoluto (antes era só o nome curto). O init **tentou**
o binário certo.

### 2. Causa real deste boot — root FS não ficou utilizável
Ordem relevante:
1. `pcid` panic (PCI/ACPI/FDT no Pi — esperado/ruído em aarch64 sem PCIe útil).
2. `pcid-spawner` exit 1.
3. `redoxfs` **UNHANDLED EXCEPTION** (data abort) ao abrir `/scheme/disk.mmc/…`.
4. `switchroot` segue na mesma.
5. Depois disso **quase todos** os serviços falham com ENOENT:
   `logind`, `getty`, `netstack`, `dhcpd`, `edge-ai`, e o próprio genetd.

Ou seja: não é “só GENET”. O userspace não vê `/usr` de forma consistente
neste boot (RedoxFS/SDHCI a falhar no meio do switchroot).

### 3. No cartão lido no PC (RedoxFS p3)
- `cmd = "/usr/lib/drivers/bcm2711-genetd"` + symlink em `/usr/bin` — OK.
- Binários `edge-ai`, `bcm2711-genetd`, `netstack` **existem** na imagem.
- Continua **sem** `var/lib/ai/net-*` (genetd nunca chegou a correr com FS estável).

## Leitura
O fix de PATH estava certo, mas este boot morreu no **redoxfs/disk.mmc**.
Precisa de boot limpo com SDHCI/RedoxFS estável (ou reflash da imagem mestra
+ reaplicar só o unit do genetd) antes de validar M1 TX de novo.
