# REDOX OS — Auditoria Técnica

> Status: **Completa**
> Base auditada: `redox-os/redox` @ `e2bf6961e` (branch `master`, pós-0.9.x)
> Data da auditoria: 2026-09-24
> Ferramenta de build: **Cookbook + Makefiles** (repo `redox-os`)

Esta auditoria mapeia o estado real do Redox OS para fundamentar a construção do **AIOS** (plataforma baseada no Redox). Nenhuma afirmação aqui é suposição: tudo foi verificado no repositório upstream na data acima.

---

## 1. Visão Geral

O repositório `redox-os/redox` é o **meta-repositório** de build. Ele NÃO contém o kernel, relibc, drivers, shell etc. — contém:

- **`Makefile` + `mk/*.mk`** — sistema de build orquestrado em camadas.
- **`build.sh`** — wrapper para o Makefile por arquitetura/config.
- **`config/`** — configurações de filesystem por arquitetura (x86_64, i586, aarch64, riscv64gc) e por perfil (desktop, server, minimal, dev, demo, etc.).
- **`recipes/`** — milhões de receitas de pacotes (o "cookbook"). Cada receita define source (git/archive), template de build (cargo, custom, autotools, python, etc.), dependências e metadados.
- **`src/`** — código do **cookbook** (o `cargo`-based package manager da plataforma).
- **`scripts/`** — utilitários (`mount-redoxfs.sh`, `network-boot.sh`, `dual-boot.sh`, etc.).
- **`podman/` + `native_bootstrap.sh` + `podman_bootstrap.sh`** — ferramentas de bootstrap do ambiente de build.
- **`rust-toolchain.toml`** — canal `nightly-2026-05-24` com `rust-src`, `rustfmt`, `clippy`.

Os componentes reais vivem em repositórios GitLab próprios (`gitlab.redox-os.org/redox-os/*`), referenciados via receitas.

---

## 2. Componentes e seu Estado

### 2.1 Kernel

| Item | Estado | Observação |
|---|---|---|
| Repositório | `redox-os/kernel` | Microkernel escrito em Rust, baseado em microkernel design |
| Chamadas de sistema | Sob esquemas (**schemes**) | `syscall_*`, mais abstração de recursos como arquivos |
| Arquiteturas | `x86_64`, `i586`, `aarch64`, `riscv64gc` | Na prática: x86_64 e i586 maduros; aarch64 funcional mas limitado; riscv64gc em desenvolvimento |
| IPC | `chan`, `pipe`, `shm`, `event`, `display*` | Esquemas nativos no `/etc/login_schemes.toml` (base.toml) |
| Drivers | Core: PS/2, USB (xhci), ATA/NVMe/SATA, e1000, RTL8139, virtio, framebuffer | Suporte a hardware real varia; muitos drivers em receitas `wip` |
| ACPI | Parcial | `acpid` com panics conhecidos em hardware real (ver HARDWARE.md); algumas coisas hardcoded |
| Networking | `dpio` (E/S de dispositivos) → daemons `smolnetd`, `dhcpd` | Esquema `ip`, `icmp`, `tcp`, `udp` no userspace |
| Alocação | `memory` esquema | Gerenciamento de memória via scheme do kernel |

### 2.2 relibc

| Item | Estado |
|---|---|
| Repositório | `redox-os/relibc` |
| Natureza | Libc escrita em Rust pelos próprios autores (não é uma port do glibc/musl) |
| Syscall binding | Direto via `syscall` crate (o kernel Redox usa chamadas próprias) |
| Suporte posix | Parcial: POSIX foi estendido progressivamente; ainda faltam funcionalidades (ex.: falta de suporte completo a `mmap` anônimo compartilhado, semáforos POSIX etc.) |
| Compilação | `cargo` (script `cookbook_cargo`) |
| Código C externo | `libc` API implementada em Rust, com algumas partes em assembly |
| Header | `/usr/include` — os headers são os do relibc |
| Rust std | Compila com `std` para target `*-unknown-redox` |

### 2.3 Userspace base

| Pacote | Função |
|---|---|
| `relibc` | libc |
| `base` | Inicialização de início (init scripts, config de user/groups/schemes) |
| `ion` | Shell default (muito rápido, escrito em Rust, usado por scripts de init) |
| `dash` | SH POSIX simples (compatibilidade) |
| `coreutils`, `extrautils`, `uutils`, `uutils-grep`, `uutils-procps`, `uutils-sed` | Comando base do sistema |
| `netutils` | daemons de rede (`smolnetd`, `dhcpd`, etc.) |
| `userutils` | `sudo`, `id`, `whoami`, etc. |
| `pkgar`, `pkgutils` | Gerenciador de pacotes (binário + deps) |
| `contain` | Contêineres leves (schemes isolados) — promissor para isolamento de modelos |
| `redoxfs` | Filesystem nativo |
| `pkgutils` | Package manager de baixo nível |

### 2.4 RedoxFS

| Item | Estado |
|---|---|
| Repositório | `redox-os/redoxfs` |
| Natureza | Filesystem próprio com journaling (log), checksums e suporte a snapshots |
| Uso | Filesystem principal nas imagens geradas pelo installer |
| Ferramentas | `redoxfs-mkfs`, `redoxfs` (FUSE) + script `scripts/mount-redoxfs.sh` |
| Encrypt | Suporta `--encrypt` no `REDOXFS_MKFS_FLAGS` |
| Limitações | Ainda em desenvolvimento ativo; sem antigravity locks etc. |

### 2.5 Gerenciador de pacotes

| Item | Estado |
|---|---|
| Cookbook | `src/` (Rust) — build de receitas, gera `repo.tag`, instala no filesystem |
| `repo` | Gerenciamento de repositório binário (receitas em `mk/repo.mk`) |
| `pkgutils` | Instalação/remoção de pacotes dentro do OS |
| `acid` + `acid-bins` | A ferramenta de gerenciamento de pacotes em desenvolvimento |
| Fonte canonical | `https://static.redox-os.org/pkg` (ver `/etc/pkg.d/50_redox` no base.toml) |
| Formato de receita | `recipe.toml` — source, build (template + script), dependencies, optional-packages |

### 2.6 Build system

| Item | Estado |
|---|---|
| Orquestração | `Makefile` + `mk/config.mk`, `mk/prefix.mk`, `mk/repo.mk`, `mk/disk.mk`, `mk/qemu.mk`, `mk/ci.mk`, `mk/fstools.mk`, `mk/podman.mk` |
| Toolchain | Prefix cross-compiler `build/prefix` (gcc, binutils, rust) ou `PREFIX_BINARY=1` (prebuilt) |
| Containerização | Podman por padrão (`PODMAN_BUILD=1`) — `podman/redox-base-containerfile` |
| Alvo Rust | `{arch}-unknown-redox` (ex.: `x86_64-unknown-redox`, `aarch64-unknown-redox`) |
| Target GNU | `{arch}-unknown-redox` alias |
| Imagens | `harddrive.img` (raw); `redox-live.iso` (live/demo); `installer-*` |
| Argumentos | `./build.sh -X/-A/-5/-R -c CONFIG -f FILESYSTEM_CONFIG TARGET` |
| `make qemu` | QEMU com flags específicas por arch (ver 2.10) |
| `make env` | Abre shell com PATH do prefix |
| Testes CI | `.gitlab-ci.yml` + `mk/ci.mk` (jobs format/lint/unit/integration/build/qemu-boot/...) |

### 2.7 Bootloader

| Item | Estado |
|---|---|
| Repositório | `redox-os/bootloader` |
| Formatos | BIOS/MBR (`bootloader.bios`), UEFI (`bootloader.efi`) para x86_64/i586 |
| AArch64 | UEFI (`aarch64-unknown-uefi`) — **não existe BIOS para aarch64**; usa UEFI firmwares (AAVMF/edk2) |
| Live | `bootloader-live.bios` / `bootloader-live.efi` |
| Raspberry Pi 3 | U-Boot: `raspi3bp_uboot.rom` (QEMU ank `raspi3b`) |
| Raspberry Pi | Sem firmware oficial na árvore; usa-se U-Boot baixado |

### 2.8 Shell / Terminal

| Item | Estado |
|---|---|
| Shell | `ion` (Rust), `dash` |
| Terminal | `orbterm` (Orbital), `kibi` (TUI), terminfo |
| TUI apps | `bottom`, `htop`, `vim`, `nano`, `tmux` |
| Console | `/usr/lib/init.d/30_console_switch` — `inputd -A 2` |

### 2.9 Gráficos / Desktop

| Item | Estado |
|---|---|
| Compositor | **Orbital** (Rust, compositor próprio do Redox) |
| GUI toolkit | `liborbital` + `orbclient` (Rust) |
| Desktop COSMIC | `cosmic-edit`, `cosmic-files`, `cosmic-icons`, `cosmic-term`, `cosmic-text`, `cosmic-monitor`, `cosmic-reader`, `cosmic-settings`, `cosmic-store` (wip) |
| Formatos | VGA (VRAM), UEFI GOP, framebuffer |
| WSI | `vga`/`ramfb`/`virtio-gpu` em QEMU; `display*` scheme |
| Fallback | Orbital tem composição por thread; sem X11 por padrão (X11 em `recipes/groups/x11-full`/`x11-minimal` ainda, wip) |
| Wayland | `config/wayland.toml` existe (em desenvolvimento) |

### 2.10 Emulação / QEMU

| Arquitetura | Máquina | Flags | Observações |
|---|---|---|---|
| x86_64 | `q35` | `-cpu core2duo -smp 4 -m 2048`, UEFI/OVMF | Suporte completo, KVM no host |
| i586 | `pc` | `-cpu pentium2 -smp 1 -m 1024`, VGA | Suporte completo |
| aarch64 | `virt` (padrão) | `-cpu max -smp 1 -m 2048`, UEFI AAVMF, gpu ramfb | Boa suporte em QEMU |
| aarch64 | `raspi3b` (BOARD=raspi3bp) | `-cpu max`, `-smp 4`, `-m 1024`, SD card disk, usb-net | Usa U-Boot (`raspi3bp_uboot.rom`) |
| riscv64gc | `virt,acpi=off` | `-smp 4 -m 2048` | Em desenvolvimento |

Regras importantes:
- `disk=ata|nvme|usb|virtio|cdrom|sdcard` — controladores variam por arch.
- `net=rtl8139|virtio|usb-net|redir|no` — `redir` faz port forwarding (8022 ssh, 8080 webserver, 64126 gdbserver).
- `gpu=vga|ramfb|virtio|...`.
- `make qemu` usa `redox-live.iso` se `live=yes` (aarch64 default), senão `harddrive.img`.
- `make gdb` (rust-gdb remote :1234), `make gdb-userspace`, `make wireshark` (pcap).

### 2.11 Networking userspace

| Item | Estado |
|---|---|
| Esquemas | `ip`, `icmp`, `tcp`, `udp` implementados via daemons |
| Daemon | `smolnetd` (config IP), `dhcpd` (DHCP client) |
| Config | `/etc/net/dns`, `/etc/net/ip`, `/etc/net/ip_router`, `/etc/net/ip_subnet` |
| Init | `/usr/lib/init.d/10_dhcpd.service`, `10_smolnetd.service` |
| Servidores | `nginx`, `simple-http-server`, `miniserve`, `openssh`(wip), `redox-ssh`(não compila) |
| Clientes | `curl`, `wget`, `git`, `rsync`, `miniserve` |
| TLS | `openssl3`, `libsodium` |
| DNS | `/etc/net/dns` (padrão 9.9.9.9 no base.toml) |

### 2.12 AArch64 / ARM / Raspberry Pi

| Item | Estado |
|---|---|
| Suporte kernel aarch64 | Sim, boot via UEFI (kernel `aarch64-unknown-redox`) |
| QEMU aarch64 (virt) | Boot UEFI → bootloader → kernel OK; **userland bloqueado no master (corrigido em 2026‑09‑25)**: causa raiz era falta de fences de ordering DMA + IRQ não entregue em aarch64; resolvido com fences `Acquire/Release` em `queues.rs` + modo polling no executor (`set_poll_mode(true)`). Agora o init do nvmed completa, ambos os discos NVMe são reconhecidos e a userland avança para o prompt de login. Upstream não tem CI de boot aarch64 (só `repo-tree`). |
| Raspberry Pi 3 Model B+ | **Reportado como "Booting"** na HARDWARE.md (0.8.0, server, ARM64, console UART pl011) |
| Raspberry Pi 4 | **NÃO listado** — nenhum suporte validado |
| Raspberry Pi 5 | **NÃO listado** — nenhum suporte validado |
| GPIO | Não há driver de GPIO genérico validado |
| VideoCore/GPU do Pi | Sem suporte de aceleração |
| Wi-Fi | **NÃO suportado** (explicitado na HARDWARE.md) |
| Bluetooth | **NÃO suportado** |
| Configs existentes | `config/aarch64/ci.toml`, `config/aarch64/demo.toml`, `config/aarch64/dev.toml`, `config/aarch64/redoxer.toml`, `config/aarch64/raspi3bp/minimal.toml` |
| Firmware Pi | Via U-Boot (rastro: `config/aarch64/ci.toml` refere-se a `redox_firmware` GitLab) |
| Console serial | pl011 UART funcionando no Pi 3B+ |

### 2.13 Rust toolchain no Redox

| Item | Estado |
|---|---|
| `rust` receita | `redox-os/rust` branch `redox-2026-05-24` — Rust **self-hosting** no próprio Redox |
| `cargo` | Pakote dentro da receita `rust` (`tools = ["cargo","clippy","rustdoc","rustfmt","src"]`, `extended = true`) — roda no OS |
| `rustup` | **Não roda no Redox** (scripts host: "in redox OS, rustup is not available; packages managed by pkg"; receita wip quebrada) |
| `rustfmt` | Parte do pacote `rust` (self-hosted) |
| `clippy` | Parte do pacote `rust` (self-hosted) |
| CLI cargo extras | wip: `recipes/wip/dev/cargo-tools` (112 receitas cargo-*) |
| `rust-analyzer` | wip (`recipes/wip/dev/ide/rust-analyzer`) |
| `dev-essential` | grupo: autotools, cmake, gcc13(+cxx), gnu-grep, groff, gawk, file, perl5, python312, ripgrep, lua54, m4, nasm, patch, pkg-config, rust, sed |
| `dev-redox` | grupo: dev-essential + redox-tests + libs (openssl3, libsodium, libxml2, ncursesw, zlib, …) |
| Build self-hosted | `cookbook` instala receitas no OS; `config/sys-build.toml` roda `make prefix` + `make r.sys` dentro do Redox |
| Toolchain upstream | `nightly-2026-05-24` (host), target `-unknown-redox` |
| Compilação cruzada | Via prefix (gcc + rust target) ou `PREFIX_BINARY=1` |

### 2.14 Casos de testes

| Item | Estado |
|---|---|
| `redox-tests` grupo | Suíte de testes do redox (`recipes/groups/redox-tests`) |
| `acid` | Ferramenta de benchmark (config `acid.toml`) |
| `auto-test` | Config/script automático (`config/auto-test.toml`, `mk/ci.mk`) |
| redoxer | Executa CI dentro do próprio Redox (config redoxer.toml) |
| `os-test` | Testes do OS |

### 2.15 Fase 2 — experimentação self-hosted (QEMU, x86_64)

Imagem `ai-developer` (Fase 2) com `dev-essential` + `git` embarcados, validada in-guest via serial:

| Evidência | Resultado |
|---|---|
| `rustc --version` / `cargo --version` in-guest | `rustc 1.98.0-dev`, `cargo 1.98.0-dev (8b241a6b6 2026-06-01)` ✅ |
| `gcc --version` / `ld` | `gcc (GCC) 13.2.0` ✅; `ld` em `/usr/lib/gcc/.../x86_64-unknown-redox/bin/ld` |
| `cc`, `gcc`, `cargo`, `rustc` em `/usr/bin` | Todos presentes ✅ |
| `cargo init --name hello --vcs none` | ✅ (cria Cargo.toml + src/main.rs) |
| `rustc src/main.rs -o hello` ( ابن) | **Panic do rustc**: `thread 'main' panicked at .../filesearch.rs:255:60: Failed finding sysroot: "dladdr failed"` (ICE) |
| `cargo build` (ابن) | `error: failed to determine the amount of parallelism available (Invalid argument)` — workaround: `-j1` |
| Compilação in-guest sob **KVM** | `kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID ..., NAME /usr/bin/rustc|cargo` — kernel derruba o processo (mesmo `cargo init` crashou uma vez) |

**Leitura (TCG x KVM)**: sob **TCG puro** (`-accel tcg`) o userland é estável (boot, login, cargo init OK) e o rustc chega até o próprio panic com **mensagem determinística** → os dois gargalos reais são:

1. **Sysroot por `dladdr`**: rustc (invocado ad-hoc como `/usr/bin/rustc`) precisa auto-localizar o sysroot via `dladdr`, que o relibc Redox não implementa → `dladdr failed` → ICE. (O cookbook chama rustc de outra forma — com `--sysroot`/layout de prefix — por isso upstream não vê este caso.) `--sysroot /usr` por flag e `env RUSTC_SYSROOT=/usr` **não** evitaram o panic nos testes (falta validar propagação do env pelo `env` do ion / invocação igual ao cookbook). Workaround pendente.
2. **`cargo` não determina paralelismo**: `available_parallelism` → EINVAL no Redox → `cargo build` morre antes de chamar rustc. Workaround: `cargo -j 1`.

**Bug de kernel sob KVM (paralelo ao aarch64)**: a mesma carga que no TCG dá panic "limpo" do rustc, sob `-enable-kvm` derruba `cargo`/`rustc` com `UNHANDLED EXCEPTION` (kernel::context::signal), i.e., **instabilidade de userland dependente da aceleração** — o KVM expõe caminhos de clock/timers/TLB que estouram no kernel. Registro completo em `docs/UPSTREAM_REPORT_KVM_RUSTC.md` (documentação interna; **sem envio upstream**). Reprodução: `/tmp/opencode/phase2*.log`, `tcg*.log`, `sysroot.log`.

**Implicação Fase 2**: presença/execução do toolchain demonstradas ✅; **compilação in-guest de hutte** fica condicionada a (a) sysroot do rustc (dladdr) e (b) `cargo -j1`, ambos upstream/relibc — até lá a Fase 3 segue **cross-compilando do host** com o toolchain prefix (funciona, sem essas limitações).

**Notas de ambiente**: (1) desligamento não-limpo do QEMU (mata por timeout) **não persiste** escrita no disco (RedoxFS bufferiza; sem sync/flush perde-se tudo entre boots); (2) o ion desta versão **não suporta** `2>&1` nem `2>arquivo` (o token `2` é passado ao comando); (3) `printf` do ion não interpreta `\n` na string de formato (usar `cargo init` — Cargo.toml via printf fica inválido); (4) `randd` avisa "Seeding failed, no entropy source" no boot (entropia insuficiente — agrava instabilidade).

---

## 3. Estados e Restrições Importantes

### 3.1 O que ainda NÃO é suportado (blockers)

1. **Wi-Fi e Bluetooth**: NÃO suportados (HARDWARE.md).
2. **GPUs não-Intel**: driver Intel somente; outros usam VESA/GOP framebuffer.
3. **ACPI incompleto**: panic `acpid` recorrentes em hardware específico.
4. **I2C**: sem suporte (touchpads I2C-HID falham).
5. **RPi 4 / RPi 5**: SEM suporte validado.
6. **NPU / aceleração de IA em hardware**: NADA no Redox.
7. **GPU compute (CUDA/ROCm/Vulkan compute)**: NÃO existe.
8. **POSIX completo**: faltam semáforos POSIX, `mmap` anônimo completo etc.
9. **std de Rust para REDOX**: parcial — crates com código UNIX específico precisam de patches (padrão `redox-unix`).
10. **Compilação in-guest do rustc/cargo dependente de upstream**: (a) sysroot do rustc via `dladdr` não funciona no relibc → ICE "Failed finding sysroot" sob TCG; (b) `cargo` falha ao levantar paralelismo (`available_parallelism` → EINVAL; workaround `-j1`); (c) sob **KVM**, processos são derrubados com `UNHANDLED EXCEPTION` no kernel (bug de kernel dependente da aceleração, paralelo ao aarch64) — ver §2.15. Binários do toolchain executam; impacto: critério "cargo build dentro do OS" da Fase 2 fica condicionado até upstream/relibc resolver (estratégia atual: cross-compilar do host).

### 3.2 O que FUNCIONA BEM hoje

1. **Boot+userspace no QEMU x86_64** (desktop/demo/server/dev).
2. **Boot aarch64 no QEMU virt** (UEFI, live ramfb).
3. **Filesystem RedoxFS** com journaling, checksums, mount via FUSE.
4. **Networking TCP/UDP/IP userspace** (smolnetd/dhcpd), HTTP server possível.
5. **Package system** (pkgar/pkgutils/acid), cookbook para build de novos pacotes.
6. **Rust self-hosting** intraframework.
7. **Orbital** desktop Rust puro.
8. **Containers leves** (`contain` scheme-based).

---

## 4. Implicações para a Plataforma de IA

### 4.1 O que pode ser REUTILIZADO

- Build system (cookbook + Makefiles) para novos pacotes.
- `recipe.toml` para novos serviços e ferramentas.
- `config/*.toml` para novos perfis de imagem (Developer OS / Edge OS).
- `contain` para isolar serviços de inferência.
- `acid` para benchmarks (re-quadro AI benchmark).
- init system (`/usr/lib/init.d/*`) para boot da Edge AI Service.
- `netutils`/`smolnetd` para networking da Edge.
- `redoxfs` para storage local de modelos.
- `relibc` + Rust `std` para apps Rust.
- QEMU (virt + raspi3b) para testes sem hardware.

### 4.2 O que pode ser ESTENDIDO

- Receitas novas em `recipes/` (runtimes de IA Rust: llama.cpp bindings, GGUF parser, candle...).
- Novos esquemas para isolamento via `contain` (policy por modelo).
- Novos perfis de config: `config/<arch>/ai-developer.toml`, `ai-edge.toml`.
- Daemons de monitoramento (scheme-based) estilo `smolnetd`.

### 4.3 O que precisa ser CRIADO

- `aios-core` (runtime abstração, registry, benchmark) — **novo**.
- CLI `ai` / `dev` / `edge` — **novos** (userspace tools).
- Edge AI Service (daemon HTTP) — **novo**.
- GGUF metadata reader (Rust crate) — **novo**.
- Dev environment (project.toml parser + dev doctor) — **novo**.
- Web control panel leve (HTTP server + API JSON) — **novo**.

### 4.4 O que ainda NÃO é VIÁVEL

- GPU/NPU compute dentro do Redox (bloqueado por drivers).
- Runtimes que dependem de APIs POSIX completas (ex.: PyTorch, TensorFlow, llama.cpp com pthreads avançado, OpenBLAS) — precisam de port pesada.
- ONNX Runtime completo (depende de muito suporte a syscalls).
- LLM grandes (ex.: Qwen, Llama 7B+) no RPi/edge com memória limitada.

### 4.5 Runtimes de IA candidatos (compatibilidade)

| Runtime | Lang | Compatibilidade Redox | Prioridade |
|---|---|---|---|
| **GGUF parser (Rust)** | Rust | Alta (uso de `std` + apenas I/O + hashing) | **ALTA** |
| **Candle** (HuggingFace) | Rust | Média (depende de `libm`, BLAS opcional; cores puros Rust compile) | **ALTA** — avaliar |
| **llama.cpp (não-vendored)** | C/C++ | Média-baixa (usa pthreads; precisa de port relibc) | MÉDIA |
| **llama.cpp via crate `llama_cpp`** | Rust FFI | Baixa (FFI com libc) | MÉDIA |
| **ONNX (wonnx)** | Rust | Baixa (já tem receita `recipes/wip/ai/nnx` com TODO: fs2 crate error) | BAIXA |
| **tinygrad / micrograd** | Python | Baixa (Python no Redox é limitado) | TESTAR |
| **Tokenizers (HF)** | Rust | Média (crates puros Rust) | ALTA |
| **burn (Burn AI)** | Rust | Média | MÉDIA |
| **bolt / linfa (ML clássico)** | Rust | Alta (puros Rust) | MÉDIA |
| **ggml** (C) | C | baixa | BAIXA |

### 4.6 Estratégia recomendada

1. **GGUF como formato central** — parser Rust puro (sem libc), com metadata, checksum, validação.
2. **Candle como backend primeira opção de inferência** — compile em target `-unknown-redox` sem drivers de dispositivo e usar apenas backend CPU. Avaliar com um build de teste.
3. **Fallback puro-Rust de ML** (tokenizers Rust + candle CPU) para slм.
4. **`contain` para isolamento** de modelos/serviços.

### 4.7 Requisitos de board para RPi

| Board | Status | Iniciable? | Observação |
|---|---|---|---|
| QEMU `virt` ARM64 (aarch64) | Funciona | **SIM** | Ambiente de desenvolvimento e CI |
| Raspberry Pi 3B+ | "Booting" (0.8.0, server, UART pl011) | SIM (só console serial, sem ethernet garantida) | Não apostar nele como alvo primário |
| Raspberry Pi 4 | Nenhum | **NÃO validado** | A guarda de "no fake support" aplica: NÃO prometer até boot validado |
| Raspberry Pi 5 | Nenhum | **NÃO validado** | Idem |

---

## 5. Conclusões Finais da Auditoria

1. **Não há obstáculo fundamental** para rodar uma plataforma de IA em userspace no Redox, desde que:
   - 100% Rust core;
   - CPU-only (sem GPU/NPU no período);
   - modelos pequenos (SLM ≤ ~2-3B params, Q4 quantização realista);
   - armazenamento local (RedoxFS) + cache.
2. **x86_64 é o alvo de desenvolvimento primário** (maduro, QEMU funcional, KVM).
3. **aarch64 (QEMU virt) é o alvo de validação de ARM** e o trampolim para RPi.
4. **Raspberry Pi real: apenas RPi 3B+ tem status "Booting"**; não prometer RPi 4/5 até validação.
5. **A estratégia de kernel zero-modificação é realista** — tudo o que precisamos nos primeiros milestones é userspace/sistema de serviços/receitas/config.
6. **O isolamento de IA é viável via `contain`** + schemes, sem tocar o kernel.
7. **O maior risco técnico** é a portabilidade de crates Rust que usam `libc`/UNIX específico — mitigação: uso de crates puros Rust + feature flags redox, e testes no CI com `redoxer`.

---

## 6. Recursos do Redox relevantes para consulta

| Recurso | URL |
|---|---|
| Redox repo | gitlab.redox-os.org/redox-os/redox |
| Kernel | gitlab.redox-os.org/redox-os/kernel |
| relibc | gitlab.redox-os.org/redox-os/relibc |
| RedoxFS | gitlab.redox-os.org/redox-os/redoxfs |
| Cookbook | `src/` local |
| Build scripts | `build.sh`, `Makefile`, `mk/*.mk` |
| Hardware reports | `HARDWARE.md` |
| Bootloader | gitlab.redox-os.org/redox-os/bootloader |
| Docs | redox-os.org/docs/ |

---

*Fim da auditoria — próxima etapa: `docs/ARCHITECTURE.md`.*