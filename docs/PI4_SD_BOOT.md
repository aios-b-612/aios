# Boot no Raspberry Pi 4B — cartão SD + console serial

Guia prático (2026-10-16) para colocar o **AIOS Edge OS** no Raspberry Pi 4B.
A mesma imagem já foi validada em QEMU até o login; falta apenas o hardware real.

---

## 1. Material necessário

| Item | Observação |
|---|---|
| Cartão microSD **separado** (sacrificial) | 8 GB+; a imagem usa 2 GB. **NÃO use o cartão atual do Pi** |
| Adaptador **USB-TTL 3,3 V** (CH340, CP2102, FT232…) | para ver/operar o console serial |
| (Opcional) kit de dissipação térmica | recomendado para o Pi 4 |
| Leitor de cartão no PC | o mesmo serve para gravar e para recuperar |

> A imagem já vem com tudo embutido: SO (Redox/AIOS) + u-boot + firmware do
> VideoCore + `config.txt`. Você não precisa montar nada à mão.

---

## 2. Gravar o cartão (1 comando)

```sh
cd /home/fasr/SSD_BACKUP/Workspace/aios

# 1) descubra o nome do cartão (insira no leitor e rode; procure o de tamanho
#    correspondente, normalmente com coluna TRAN=usb):
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL

# 2) gravar (troque /dev/sdX pelo nome EXATO que apareceu):
./scripts/make-sd-pi4.sh --write /dev/sdX
# quando pedir, digite:  GRAVAR
```

Travas do script: recusa o disco do sistema, recusa cartão montado, recusa
cartão < 2 GiB, e só grava após confirmação digitada.

Sem o script (equivalente):

```sh
sudo dd if=redox-os/build/aarch64/pi4/aios-edge-pi4-sd.img of=/dev/sdX bs=4M conv=fsync status=progress
sudo sync
```

Artefato: `redox-os/build/aarch64/pi4/aios-edge-pi4-sd.img`
(md5 `b0bfb1766ff7fb0efb3e8f8c68e17d36`, validado no QEMU no probe 7c).

---

## 3. Console serial (UART) — fios

No PC: `ls /dev/ttyUSB*` (com o adaptador plugado).

| Adaptador | Pino físico do Pi | Sinal |
|---|---|---|
| GND | 6 | GND |
| RX | 8 | GPIO14 = TXD do Pi (o **RX do adaptador** recebe) |
| TX | 10 | GPIO15 = RXD do Pi |

- **Não** conecte o pino de alimentação (3,3 V/5 V) do adaptador — o Pi tem fonte própria.
- Use adaptador em **3,3 V** (se tiver jumper, deixe em 3V3).
- Com o Pi **desligado**: GND primeiro, depois RX/TX. Conferir duas vezes (RX↔TX trocados = nenhuma saída).
- 8N1, **115200**.

---

## 4. Ligar e acompanhar

```sh
# ver o console (e gravar log):
picocom -b 115200 --logfile /tmp/pi4-boot.log /dev/ttyUSB0
# sair do picocom:  Ctrl-A  Ctrl-X
```

1. Insira o cartão no Pi (desligado) e ligue a energia.
2. Esperado no serial, em ordem:
   - firmware VideoCore (rápido) → **u-boot** (banner `U-Boot 20xx…`);
   - u-boot acha `EFI/BOOT/BOOTAA64.EFI` no cartão e carrega o bootloader Redox;
   - kernel Redox: mensagens de init, driver de SD (`bcm2835-sdhcid`) anunciando
     o cartão, `init: switchroot to /usr /etc`;
   - **`redox login:`** → login `root` / senha `password`.
3. Se chegou no login: **sucesso** — o SO está rodando do cartão no hardware real.

Para parar/desligar com segurança: desligue a energia (o RedoxFS tolera; evite
ciclos rápidos). Log completo em `/tmp/pi4-boot.log` — me mande esse arquivo!

---

## 5. Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Nada no serial | TX/RX invertidos, GND solto, baud errado, adaptador em 5 V |
| Sai firmware mas nada de u-boot | `kernel8.img` ausente na partição FAT, `config.txt` errado |
| u-boot roda mas não acha nada | partição EFI sem `EFI/BOOT/BOOTAA64.EFI` (regravar com o script) |
| Trava no kernel | anotar as últimas linhas; é o caso a depurar juntos (driver SD/EMMC2) |

---

## 6. Recuperar o cartão depois

- Raspberry Pi Imager (PC) ou `sudo dd if=/dev/zero of=/dev/sdX bs=4M` para zerar.

---

## 7. Notas técnicas (o que está em teste no hardware)

- O caminho completo já foi validado **em QEMU** com exatamente esta imagem e
  este u-boot: `docs/evidence/pi4/probe6-boot-completo.log`,
  `probe7b-login-shell.log` e `probe7c-sd-artefato.log`.
- Ponto em aberto do hardware real: o driver de SD (`bcm2835-sdhcid`, caminho
  SDHCI) — no QEMU ele foi validado contra o controlador emulado via DT
  remapeado; no Pi real o cartão está no **EMMC2** (BCM2711), que é o alvo do
  driver. É o primeiro item a observar no log.
- Rede (GENET) ainda **não tem driver** → `edge-ai` não sobe no Pi por enquanto
  (gap conhecido; o runtime AIOS já está na imagem).
- O restante do espaço do cartão (se > 2 GB) fica sem uso nesta fase
  (crescer o RedoxFS é melhoria futura).
