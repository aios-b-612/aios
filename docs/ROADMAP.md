# AIOS — Roadmap

> Fases incrementais. Cada fase gera artefatos testáveis e revisáveis.
> Princípio: **BOOT → USERSPACE → DEVELOPER → AI → EDGE → RASPBERRY.**
> Hardware só é listado quando **validado** (boot real em QEMU ou hardware).

## Validação no CI (2026-09-28)

PR #1 (`feature/complete-phases`) fecha com os três jobs verdes no GitHub
Actions, o que valida a cadeia de release de ponta a ponta, e não só o
código Rust:

| Job | Resultado | O que prova |
| --- | --- | --- |
| `Build & Test` | PASS (56s) | fmt, clippy, build, 123 testes, smoke dos 5 CLIs |
| `QEMU Boot Test (x86_64)` | **PASS** (10m50s) | imagem construída a partir do upstream pinado, boota até `login:`, `models` e `aios-developer-os` |
| `QEMU Boot Test (aarch64)` | **BLOCKED** (14m45s) | bootloader, `Currently in EL1` e `kernel_entry` atingidos; userland bloqueado pelo hang de NVMe do upstream |

O job aarch64 é neutro por desenho (exit 2 = BLOCKED, com notice), não um
verde disfarçado: o console mostra `[BLOCKED] login:` explicitamente.

**Nota de confiança**: até esta validação, `test.sh` rodava apenas no host de
desenvolvimento, onde `DISPLAY` está definido. No CI, QEMU morria com
`gtk initialization failed` antes de imprimir uma linha. O canário agora roda
no runner sem display, que é a configuração que de fato importa.

---

---

## FASE 0 — AUDITORIA ✅ (em andamento)

**Meta**: conhecer o Redox, mapear reutilizáveis, riscos, limites.

**Entregas**:
- [ ] `docs/REDOX_AUDIT.md` (criado)
- [ ] `docs/ARCHITECTURE.md` (criado)
- [ ] `docs/ROADMAP.md` (este)
- [ ] `docs/DECISIONS.md`

**Critério de aceite**: arquitetura revisada e validada; lista de crates/pacotes candidatos definida; planos da Fase 1 constantes neste doc.

---

## FASE 1 — BASE (upstream boot)

**Estado**: expandir a partir do upstream.

**Meta**: boot reprodutível em QEMU.

**Entregas**:
- [x] `platform/` meta-repo (build scripts próprios: `scripts/build.sh`, `scripts/run-qemu.sh`, `scripts/test.sh`, `scripts/debug-qemu.sh`).
- [x] Verificação do boot upstream x86_64 (ai-developer) + aarch64 (ai-edge) no host.
- [x] Perfis de config derivados: `ai-developer` (≈ desktop/dev) e `ai-edge` (≈ server/minimal sem GUI).
- [ ] `cio` no `platform/` passa a ser o entry-point de build (em vez de entrar no repo upstream manualmente).

**Critério**: `make qemu` (ou script próprio) boots até o prompt do ion; filesystem acessível; rede `smolnetd`/`dhcpd` ativa; `make qemu` aarch64 também bootstrap.

**Status da validação (2026-09-24)**:
- x86_64 ai-developer: **PASS** — boot → login `user` → `/var/lib/ai/models` e `/etc/ai-platform` presentes (canário `scripts/test.sh`, KVM).
- aarch64 ai-edge: imagem constrói; canário bootloader+kernel **PASS**; userland **já não bloqueada** — o fix de fences DMA + modo polling em `nvmed` permite boot até o prompt de login (validado em 2026‑09‑25). Blocker resolvido; reavaliar integração futura.

---

## FASE 2 — DEVELOPER OS

**Meta**: ambiente dev Rust completo e reprodutível.

**Status**: toolchain `rust` (self-hosted) + `gcc13` + `cmake` + `python312` + `git` **embarcados no perfil `ai-developer`** (config: `dev-essential` + `git`, `filesystem_size=8192`; imagem com ~934M reais). Binários do toolchain executam in-guest (`rustc 1.98.0-dev`, `cargo 1.98.0-dev`, `gcc 13.2.0` ✅). **BLOCKER para compilação in-guest**: sysroot do rustc via `dladdr` (relibc) + paralelismo do cargo + exceções de kernel sob KVM — **Fase 3 prossegue cross-compilando do host** (ver `REDOX_AUDIT.md` §2.15 e §3.1/10).

**Entregas**:
- [x] Construir/incluir toolchain Rust self-hosted no perfil `ai-developer` (receitas `rust`, cargo, rustfmt, clippy; avaliar `rust-analyzer`).
- [ ] `dev` CLI (crate userspace) — `dev new/build/run/test/check/fmt/doctor`.
- [ ] Templates de projeto com `project.toml`.
- [ ] `dev doctor` com checagem de: Rust, Cargo, Git, filesystem, network, CPU, RAM, AI runtime, models, storage, toolchains, targets, edge SDK.

**Critério**: executar `cargo build` e `cargo test` de um template dentro do OS; `dev doctor` reporta tudo OK/permitido. — *primeira parte bloqueada pela estabilidade upstream sob QEMU/KVM (§2.15).*

---

## FASE 3 — AI CORE

**Meta**: camada `aios-core` funcional.

**Entregas**:
- [x] Crate `aios-core` (runtime abstraction, model meta, cache, checksum, registry).
- [x] CLI `ai` (list/info/install/remove/run/serve/stop/benchmark/inspect).
- [x] GGUF metadata parser (Rust puro) + `ai inspect model.gguf`.
- [x] Backend CPU via Candle (validado no target `-unknown-redox` e in-guest — ADR-003).
- [x] `ai-sdk` básico (`ai::load` funcional; `model.generate` real a partir da Fase 4).

**Status**: workspace criado (`aios/`); `aios-core` (parser header GGUF tipos 0–12, SHA-256 puro, model meta, cache, registry TSV) e `aios-sdk` (`load` resolve modelo via registry + cache) prontos; CLI `ai` completo para a fase com **backend Candle CPU real** (list/inspect/verify/install/remove/info/benchmark/doctor/**run**; `serve`/`stop` recusam com erro explícito "Fase 4"). **Build nativo OK** — 11 testes (aios-core 7 + aios-sdk 4) cobrindo roundtrip install/remove, rejeição de nomes inválidos, load via registry/cache **e headers GGUF >1 MiB (streaming)**. Env overrides `AIOS_MODELS_DIR`/`AIOS_REGISTRY`. **Cross-compilação `x86_64-unknown-redox` release OK**: `ai` é único binário estático **8.39 MB** (full stack candle-core 0.9.2 + candle-transformers 0.9.2 + tokenizers 0.21.4). **Inferência real in-guest (KVM)**: modelo TinyLlama-1.1B-Chat Q4_K_M (668 MB, GGUF v3, 201 tensores) injetado em `/var/lib/ai/models`; `ai run` gerou texto (~24 tokens) a **~1.5–1.7 tokens/s** (load ~24–30 s); `ai benchmark` reportou GGUF parse **5/5 ok** (metadata real com vocab de 32k tokens), SHA-256 ~340 MiB/s e throughput Candle ~1.73 tokens/s. Host: ~6.9 tokens/s, load 0.56 s. Regressão de parser: metadata >1 MiB agora é lida em streaming (antes `truncated GGUF` em modelos reais). Exigiu `chmod 1777` em `/var/lib/ai` e `/var/lib/ai/models` (usuário `user` — ADR-017). Pendência: **rebuild da imagem** para o marker `/etc/ai-platform` refletir o rename de branding (`aios-developer-os`).

**Critério**: carregar metadata GGUF, validar checksum, listar/instalar/remover modelos no cache local; `ai benchmark` roda um SLM básico e reporta latência/tokens per sec. Tudo offline.

---

## FASE 4 — SLM & TASKS

**Meta**: inferência local viável com modelos pequenos.

**Entregas**:
- [x] `AITask` framework (grammar, correction, classification, summarization, embedding, translation, OCR, speech, TTS, vision, code, intent, autocomplete — os viáveis em CPU-first). *Framework pronto com built-ins `summarize`/`classify`/`intent`/`translate`/`qa`; os demais são templates adicionáveis via config.*
- [x] Roteamento tarefa→modelo via config.
- [x] Perfil de modelo (SLM ≤3B Q4 otimizado). *TinyLlama-1.1B-Chat Q4_K_M é o perfil de referência (668 MB, GGUF v3).*
- [x] `ai task <name>` funcional.
- [x] SDK: `aios_sdk::generate`/`generate_with_metrics` com inferência real via Candle (exemplo `examples/generate.rs`).

**Critério**: executar `ai task summarize`/`ai task classify` offline com um SLM baixado; documentar benchmarks reais. — *validado no host e in-guest (ver status).*

**Status (2026-09-24)**: novo subcomando **`ai task`** com framework `AITask` no CLI (`cli/ai/src/tasks.rs`): 5 tasks built-in (summarize/classify/intent/translate/qa), templates com placeholder `{input}`, roteamento tarefa→modelo por config JSON (`AIOS_TASKS` ou `/etc/ai/tasks.json`) que pode sobrescrever model/prompt/max_tokens de built-ins ou **criar tasks novas**; flags `--list`/`--model`/`--text`/`--file`/`--max-tokens`/`--json` (input: `--text` > `--file` > stdin). Resolução de modelo reutiliza o caminho file→registry→cache (`resolve_model_path`). **Workspace: 14 testes** (aios-cli +3). **Host (TinyLlama real)**: `ai task classify --text "This product is amazing, I love it!"` → *"Positive:..."*; `ai task summarize` gera bullets; `intent` com `--json` devolve JSON válido; ~3 t/s com contexto de task. **In-guest (KVM, smoke PASS)**: `/etc/ai/tasks.json` embarcado ligando summarize/classify→`tinyllama.q4_k_m`; `ai task --list` lista tasks com modelo ligado; `ai task classify` (prompt "amazing"/24 tok) → **0.73 t/s**, `ai task summarize` (24 tok) → **0.72 t/s** (menor que os ~1.5–1.7 de `ai run` porque o prompt de task tem ~30–40 tokens de contexto); task desconhecida rejeitada com erro limpo. Binário cross `ai` agora **8.49 MB** (+serde/serde_json). Pendência conjunta Fase 3/4: rebuild da imagem para o marker de branding `aios-developer-os`.

---

## FASE 5 — EDGE AI OS

**Meta**: imagem mínima que boota direto para serviço de IA.

**Entregas**:
- [x] Perfil `ai-edge` (aarch64) construído na Fase 1.
- [x] `edge-ai.service` (daemon HTTP local, boot direto) — daemon reorder bind-first validado **in-guest**: `listening on http://127.0.0.1:8989` em <4s (loopback OK) com preload do modelo em thread de fundo.
- [x] API JSON simples (health, models, infer, benchmark, logs, monitor/panel) — validada no host.
- [x] `edge` CLI (status/models/install/remove/run/serve/logs/benchmark/devices/update) — validado no host e in-guest (exceto TCP, ver blocker).
- [x] `ai-monitor` (métricas: CPU/RAM/storage/temp/network/models/infer/requests/latency/tokens/s/errors) + histórico simples.
- [x] Web control panel leve (HTML+JSON no mesmo daemon).

**Critério**: boot QEMU da imagem edge → API respondendo → `edge status` reporta runtime ativo; monitor mostra métricas; painel web acessível no http://edge-ai.local (resolvida por config/hosts local).

**Status (2026-09-25)**: rebuild da imagem completada após corrupção da `harddrive.img` (causa: boot/montagem FUSE concorrentes no mesmo disco). Inject do perfil `ai-developer` renovado: bins `edge`/`edge-ai`, modelos (`tinyllama.q4_k_m`, `hello.w4gguf`...); marker `/etc/ai-platform` setado para `aios-developer-os`. **Validação in-guest**: daemon ≥ SMOKE bind-first confirmado (`M1_START`→`M2_BOUND_LOOPBACK`→`M3_TRY_LOOPBACK` com `edge-ai: listening on http://127.0.0.1:8989`).

**Blocker (plataforma Redox, não aios)**: `netstack` (userspace netstack do Redox, iniciado pelo init, PID 40) **aborta no boot** sob este qemu: `UNHANDLED EXCEPTION ... /usr/bin/netstack` → `[ERROR netstack@src/header/stdlib/mod.rs:121] Abort`. Como o Redox atende o scheme `tcp:` **inteiramente via userspace netstack**, qualquer connect TCP in-guest (loopback **e** eth0 10.0.2.15) depende dele — logo `edge status`/`edge models` in-guest travam por causa do netstack, **não** do daemon. O bind-first do daemon (0.0.0.0→127.0.0.1) já está validado; resta validar o round-trip TCP completo quando o netstack parar de abortar (upstream Redox / config qemu). Detalhes: `gotchas/redox-netstack-abort-boot-blocker.md`.

**Atenção (blocker upstream)**: fix do `nvmed` aplicado em 2026‑09‑25 (fences DMA + modo polling). A userland aarch64 agora boot até login; pendentes são o netstack e a validação TCP in‑guest. O `ai-edge` é validado em x86_64 (perfil sem GUI); o aarch64 permanece como alvo de deploy futuro.

---

## FASE 6 — RASPBERRY PI

**Meta**: port para hardware real **validado**.

**Entregas**:
- [ ] Confirmar RPi 3B+ no Redox (U-Boot → kernel → console UART).
- [ ] Imagem de boot para RPi 3B+ (SD card, config) com rede (a validar), storage (RedoxFS), energia.
- [ ] Empacotar Edge AI OS para o board.
- [ ] RPi 4 / RPi 5: **apenas** quando kernel red-ox-Med aarch64 bootear (documentar grid de validação).

**Critério**: SD card com Redox Edge AI OS boota RPi 3B+ até o serviço de IA; `edge status` via rede local funciona; temperatura/estado lidos.

**Status**: bloqueada por falta de hardware. Nada aqui é fechável por software.

A perna de software existe e está testada — o `aios-deploy` faz o deploy
completo e o `aios-edge` é o daemon alvo (Fase 7). O que falta é o **critério**,
que é explicitamente sobre RPi 3B+ real:

- **Sem Raspberry Pi disponível.** Nenhum 3B/3B+/4/5 nesta máquina ou acessível.
  As entregas da fase são literalmente "confirmar no Redox", "imagem de boot
  para o board" e "empacotar para o board" — todas exigem o device.
- **QEMU `virt` aarch64 não é substituto válido.** O kernel sobe até
  `kernel_entry` (EL1) e morre num hang de NVMe do upstream antes do userspace
  (`docs/gotchas/aarch64-nvmed-not-reproducible.md`). Rodar a Edge AI OS em
  aarch64 emulado exigiria   *patchear o kernel do upstream*, e o patch local de
  `nvmed` (`61d483a`) não é reproduzível a partir deste meta-repo. Aceitar o
  QEMU como "RPi validado" seria exatamente o tipo de proxy que o critério proíbe.

- **U-Boot do RPi não é validável aqui.** O `redox_firmware` (u-boot-rpi-3-b-plus)
  é baixado pelo build, mas não há board para executá-lo; só dá para dizer que o
  artefato existe.

O que seria necessário para fechar: um RPi 3B+ com fonte e cartão SD, o
`redox_firmware` correspondente, e rodar a sequência U-Boot → kernel → console
UART → `edge status` pela rede local.

---

## FASE 7 — DEPLOYMENT

**Meta**: Developer OS → Raspberry Pi deploy sem cloud.

**Entregas**:
- [x] `edge devices` registry no Developer (name, address, arch, OS, RAM, storage, models, status, last_seen).
- [x] `edge deploy <model.gguf> --device <id>` (validate → compat → storage → transfer → install → configure → start → health).
- [x] Protocolo de transferência local (HTTP) com retry/checksum.

**Critério**: deploy E2E de um SLM do Developer OS para um Edge (QEMU aarch64 ou RPi validado) com health check ok.

**Status**: software completo e testado; o critério **ainda não é satisfeito** porque
falta a perna de hardware.

Entregue:
- `aios-deploy` e `edge deploy` executam o pipeline completo: validação de
  compatibilidade → transferência chunked com streaming do arquivo → verificação
  SHA-256 no device → registro no registry → `GET /api/health` + `GET /api/models`.
- O health check não aceita liveness sozinho: um daemon saudável que não lista o
  modelo é tratado como deploy falho (`deploy/src/transfer.rs::health_check`).
- `edge devices` sonda cada dispositivo e mostra alcançabilidade, contagem de
  modelos e status, em vez de repetir o que está gravado no arquivo.
- Transferência não carrega o modelo em RAM: hash e upload passam por um
  `File` aberto, com no máximo um chunk em memória, e cada retry rebobina para o
  início. Um modelo de 4 GB não caberia nos dispositivos de 1–4 GB que esta fase
  tem por alvo.
- `max_retries` passou a significar "tentativas *depois* da primeira" (antes o
  laço `1..=max_retries` entregava N tentativas e o nome mentia).
- `--no-start` foi removido: o daemon não expõe endpoint de ciclo de serviço, e
  aceitar a flag dizendo que ela não faz nada seria enganoso. Agora ela é
  rejeitada com o motivo.
- `--no-verify` só desliga a releitura local pós-transferência; o device sempre
  recalcula o SHA-256, então a flag não consegue instalar modelo corrompido.
- `ai-core` GGUF com limites de parsing: `kv_count`, array count e string length
  são validados antes de alocar, e `u64 -> usize` passa por `try_from` (sem isso
  havia truncamento real em alvos 32-bit).

Verificação:
- 22 testes E2E em `deploy/tests/e2e_transfer.rs` (chunking, retry, exaustão de
  retries, rebobinagem, checksum corrompido, arquivo alterado durante o envio,
  health check, parser malicioso) + 11 de registry/validação.
- CLI exercitada end-to-end contra um device real, nos dois sentidos: deploy
  bem-sucedido muda `devices` de `unknown models=0` para `online models=1`, e um
  device que mente que instalou faz o comando sair com código 1.
- `cargo test --all` = 123 testes verdes; `cargo clippy --all -- -D warnings` limpo.

Bloqueios (não são de software):
- **Raspberry Pi**: sem hardware disponível.
- **QEMU aarch64**: o kernel sobe (bootloader, EL1, `kernel_entry`) mas o
  userspace nunca inicia por um hang de NVMe no Redox upstream, antes de
  `login:`. Ver `docs/gotchas/aarch64-nvmed-not-reproducible.md`.

O que os testes cobrem hoje é o protocolo HTTP completo em host x86_64, não o
alvo aarch64/RPi. O payload dos testes é um arquivo GGUF sintético, não um SLM
treinado: exercita transporte e instalação, não carga nem qualidade de inferência.

---

## FASE 8 — SECURITY

**Meta**: isolamento real de modelos/serviços.

**Entregas**:
- [x] Mapear suporte real (`contain`, schemes, sudo) e documentar `AI Permissions`.
- [x] Policy por modelo (filesystem.read/write, network, device, compute).
- [ ] Execução de inferência em container/isolamento `contain`.

**Critério**: um modelo com policy restrita não acessa rede/filesystem fora da política; teste automatizado negativo.

**Status**: camada de decisão de política completa e coberta por 34 testes
negativos. A lacuna restante é o isolamento no kernel.

Entregue (`5742b01`):
- Policy engine com escopo por componente, normalização lexical de `.`/`..`,
  tie-break `Deny` antes de `Allow` e preservação de `None` como "sem escopo".
- `plan_container` para planning e `create_container` retornando
  `NotImplemented` — em vez de fingir isolamento, a API diz que não isola.
- Perfis built-in e CLI (`authorize`, `describe`, `contain-plan`).

Lacuna honesta: o critério da fase é sobre *isolamento real*, e o que está
testado é a decisão de autorização em userland. `contain` no kernel não está
implementado, então um processo que ignore a library ainda teria acesso ao que a
policy nega. Ver `docs/gotchas/security-isolation.md`.

---

## FASE 9 — HARDWARE ACCELERATION

**Meta**: acelerar quando tecnicamente suportado.

**Entregas**:
- [ ] Avaliar drivers GPU no Redox (Intel) e possíveis usos (compute via OpenCL? comunitário) — investigar.
- [ ] NPU (ex.: RPi NPU) — só quando driver existir.
- [ ] Refinar backend compute com SIMD/feature flags no Candle.

**Critério**: benchmark comparativo CPU vs acelerado, só com suporte real no Redox.

**Status**: bloqueada por falta de suporte no upstream, não por falta de código.

O critério é explícito: benchmark CPU **vs acelerado**, "só com suporte real no
Redox". As três entregas dependem de coisas que não existem no alvo:

- **GPU (Intel)**: o Redox não tem um driver de GPU utilizável para compute, e
  não há backend OpenCL/Vulkan no upstream. Não existe contra o que benchmarkar,
  então produzir um número "acelerado" seria inventar o denominador.
- **NPU (RPi)**: depende da Fase 6 (sem hardware) **e** de driver — o NPU do RPi
  não tem suporte no Redox.
- **SIMD / feature flags no Candle**: esta parte é software e é fechável, mas
  isolada ela não satisfaz o critério da fase, que é comparativo. Medir
  throughput de AVX2 vs scalar no host x86_64 não diz nada sobre o alvo.

O que já existe e é real: `ai benchmark` mede o caminho **CPU** de verdade
(Candle, GGUF parse em streaming, SHA-256), com números reportados de host e de
guest. É a linha de base do comparativo — falta o outro lado. Ver Fase 4.

---

## FASE 10 — DEVELOPER PREVIEW

**Meta**: publicação e adoção.

**Entregas**:
- [x] ISO Developer OS regenerável.
- [ ] Imagem RPi (validada na fase 6).
- [ ] Documentação completa + exemplos liberados.
- [ ] Benchmarks publicados.
- [ ] Website público (repositório de páginas dedicado, ADR-022).
- [ ] CONTRIBUTING/ROADMAP público.
- [x] CI completo na plataforma (format/lint/unit/integration/build/CLI + QEMU boot x86_64 + canary aarch64).

**Critério**: `make release` produz artefatos reprodutíveis; CI verde com boot QEMU em todos os PRs.

**Status**: metade feita, e o que falta depende de fora.

Correção de registro (2026-09-28): o item "Website público" estava marcado como
entregue, mas não existe `site/` nem um único `.html` em nenhuma branch, e não há
workflow de Pages em `.github/`. O item foi desmarcado. O único conteúdo de
documentação que existe é `docs/`+ este ROADMAP; a publicação é trabalho a
fazer, não feito.

O item também estava escrito errado: dizia `site/` neste repositório, mas o
ADR-022 decidiu que o site vive em repositório dedicado
(`aios-b-612/aios-b-612.github.io`), justamente para o código do SO não carregar
artefatos de site. Por isso não existe e não deve existir um `site/` aqui — o que
falta é o repositório de páginas, que é trabalho fora deste repositório.

Entregue (`f2e8d09`, `9fac75a`):
- `platform/` versionado com `upstream.lock` pinado, `bootstrap.sh --verify` e
  `release.sh` com checksums e manifestos.
- Release multiplataforma; `platform/dist/` removido (~1,8 GB) em favor de
  artefatos versionados e reproduzíveis.
- CI: format, clippy `-D warnings`, build, testes e smoke test dos cinco CLIs.
- Canary aarch64 no CI com semântica correta: `0` passou, `2` bloqueado (notice),
  qualquer outro código **falha o job**. A versão anterior terminava com
  `exit 0` incondicional e mascarava regressão real.

Lacunas:
- Imagem RPi depende da Fase 6.
- "CI verde com boot QEMU em todos os PRs": o x86_64 sobe; o aarch64 fica
  bloqueado em `kernel_entry` pelo hang de NVMe upstream, então o job roda como
  notice, não como prova de boot.

### ISO regenerável e instalável (`7c01354`, `8a4268a`)

Fechado. `make release` agora produz `ai-developer-x86_64-redox-live.iso`, que
sobe até `redox login:` e passa nos três marcos do boot test.

Três defeitos distintos estavam entre a release e a ISO bootável, e dois deles
falhavam **em silêncio** (log de 72 bytes, sem uma linha de diagnóstico):

- **`repo cook` não tem modo headless.** O TUI não tem fallback; sem TTY o
  `into_raw_mode()` morre no ioctl, e com pty ele dá underflow no buffer de log
  vazio. O próprio upstream documenta `CI=1` como a forma de desligar o TUI, e
  ninguém passava. O build x86_64 passava antes só porque `repo.tag` já
  existia e o build pulava o `cook`; pedir o alvo `live` invalidava a tag e
  batia no TUI.
- **ISO é CD-ROM, não disco.** O `test.sh` entregava a ISO ao QEMU como NVMe e
  o boot pendurava sem log — o caminho El Torito só existe na mídia de CD-ROM
  emulada. Agora usa `media=cdrom` + `-boot d`, como o próprio `mk/qemu.mk` faz.
- **A ISO é UEFI-only.** O build emite `bootloader-live.efi` e não há
  `bootloader-live.bios` utilizável, então SeaBIOS não sobe. O caminho de ISO
  carrega OVMF por pflash.
- **`filesystem_size` teve de cair de 8192 para 3072 MiB.** O bootloader live
  copia o RedoxFS inteiro para a RAM num bloco contíguo abaixo de 8 GiB, e o
  buraco MMIO do QEMU deixa ~3 GiB como maior bloco livre. Medido: 3072 boota,
  3584+ morre com `SETUP PANIC ... "out of resources"`. O conteúdo instalado
  ocupa ~0.9 GiB, então sobram ~2 GiB de rascunho para `cargo` no guest.

Detalhe completo em `docs/gotchas/live-iso-ram-ceiling.md`.

Ressalva honesta: o job de boot do CI continua no `harddrive.img`, porque
`ubuntu-latest` tem ~7 GB e não hospeda o QEMU de `-m 8192` que o boot live
exige. A ISO é validada localmente, não no CI — o que é menos do que a frase
"CI verde" sugere.

---

## Prioridades cruzadas

| Prioridade | Área | Justificativa |
|---|---|---|
| P0 | Fase 1–2 | Boot + dev env viabiliza tudo |
| P0 | GGUF/inspect | Fundação do modelo |
| P1 | Candle CPU | Backend inferência |
| P1 | Edge service | Produto mínimo da borda |
| P2 | Security/isolamento | Essencial mas downstream |
| P2 | RPi hardware | Bloqueado por upstream |
| P3 | Aceleração | Bloqueado por drivers |

---

*Próximo doc: `docs/DECISIONS.md`*