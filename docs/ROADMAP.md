# AIOS — Roadmap

> Fases incrementais. Cada fase gera artefatos testáveis e revisáveis.
> Princípio: **BOOT → USERSPACE → DEVELOPER → AI → EDGE → RASPBERRY.**
> Hardware só é listado quando **validado** (boot real em QEMU ou hardware).

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
- aarch64 ai-edge: imagem constrói; canário bootloader+kernel **PASS**; **userland BLOQUEADA upstream** (`nvmed` initfs estoura stack em QEMU TCG ⇒ `/usr` não monta). Blocker registrado em `REDOX_AUDIT.md` §2.12 / ADR-004; reavaliar quando upstream corrigir.

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
- [x] `ai-sdk` básico (`ai::load` funcional; `model.generate` placeholder até Fase 4).

**Status**: workspace criado (`aios/`); `aios-core` (parser header GGUF tipos 0–12, SHA-256 puro, model meta, cache, registry TSV) e `aios-sdk` (`load` resolve modelo via registry + cache) prontos; CLI `ai` completo para a fase com **backend Candle CPU real** (list/inspect/verify/install/remove/info/benchmark/doctor/**run**; `serve`/`stop` recusam com erro explícito "Fase 4"). **Build nativo OK** — 11 testes (aios-core 7 + aios-sdk 4) cobrindo roundtrip install/remove, rejeição de nomes inválidos, load via registry/cache **e headers GGUF >1 MiB (streaming)**. Env overrides `AIOS_MODELS_DIR`/`AIOS_REGISTRY`. **Cross-compilação `x86_64-unknown-redox` release OK**: `ai` é único binário estático **8.39 MB** (full stack candle-core 0.9.2 + candle-transformers 0.9.2 + tokenizers 0.21.4). **Inferência real in-guest (KVM)**: modelo TinyLlama-1.1B-Chat Q4_K_M (668 MB, GGUF v3, 201 tensores) injetado em `/var/lib/ai/models`; `ai run` gerou texto (~24 tokens) a **~1.5–1.7 tokens/s** (load ~24–30 s); `ai benchmark` reportou GGUF parse **5/5 ok** (metadata real com vocab de 32k tokens), SHA-256 ~340 MiB/s e throughput Candle ~1.73 tokens/s. Host: ~6.9 tokens/s, load 0.56 s. Regressão de parser: metadata >1 MiB agora é lida em streaming (antes `truncated GGUF` em modelos reais). Exigiu `chmod 1777` em `/var/lib/ai` e `/var/lib/ai/models` (usuário `user` — ADR-017). Pendência: **rebuild da imagem** para o marker `/etc/ai-platform` refletir o rename de branding (`aios-developer-os`).

**Critério**: carregar metadata GGUF, validar checksum, listar/instalar/remover modelos no cache local; `ai benchmark` roda um SLM básico e reporta latência/tokens per sec. Tudo offline.

---

## FASE 4 — SLM & TASKS

**Meta**: inferência local viável com modelos pequenos.

**Entregas**:
- [ ] `AITask` framework (grammar, correction, classification, summarization, embedding, translation, OCR, speech, TTS, vision, code, intent, autocomplete — os viáveis em CPU-first).
- [ ] Roteamento tarefa→modelo via config.
- [ ] Perfil de modelo (SLM ≤3B Q4 otimizado).
- [ ] `ai task <name>` funcional.

**Critério**: executar `ai task summarize`/`ai task classify` offline com um SLM baixado; documentar benchmarks reais.

---

## FASE 5 — EDGE AI OS

**Meta**: imagem mínima que boota direto para serviço de IA.

**Entregas**:
- [x] Perfil `ai-edge` (aarch64) construído na Fase 1.
- [ ] `edge-ai.service` (daemon HTTP local, boot direto).
- [ ] API JSON simples (health, models, infer, benchmark, logs).
- [ ] `edge` CLI (status/models/install/remove/run/serve/logs/benchmark/devices/update).
- [ ] `ai-monitor` (métricas: CPU/RAM/storage/temp/network/models/infer/requests/latency/tokens/s/errors) + histórico simples.
- [ ] Web control panel leve (HTML+JSON no mesmo daemon).

**Critério**: boot QEMU da imagem edge → API respondendo → `edge status` reporta runtime ativo; monitor mostra métricas; painel web acessível no http://edge-ai.local (resolvida por config/hosts local).

**Atenção (blocker upstream)**: completar a userland aarch64 depende do fix do `nvmed` (REDOX_AUDIT.md §2.12). Enquanto isso, o `ai-edge` pode ser validado em x86_64 (perfil sem GUI) para o desenvolvimento do serviço; o aarch64 permanece como alvo de deploy.

---

## FASE 6 — RASPBERRY PI

**Meta**: port para hardware real **validado**.

**Entregas**:
- [ ] Confirmar RPi 3B+ no Redox (U-Boot → kernel → console UART).
- [ ] Imagem de boot para RPi 3B+ (SD card, config) com rede (a validar), storage (RedoxFS), energia.
- [ ] Empacotar Edge AI OS para o board.
- [ ] RPi 4 / RPi 5: **apenas** quando kernel red-ox-Med aarch64 bootear (documentar grid de validação).

**Critério**: SD card com Redox Edge AI OS boota RPi 3B+ até o serviço de IA; `edge status` via rede local funciona; temperatura/estado lidos.

---

## FASE 7 — DEPLOYMENT

**Meta**: Developer OS → Raspberry Pi deploy sem cloud.

**Entregas**:
- [ ] `edge devices` registry no Developer (name, address, arch, OS, RAM, storage, models, status, last_seen).
- [ ] `edge deploy <model.gguf> --device <id>` (validate → compat → storage → transfer → install → configure → start → health).
- [ ] Protocolo de transferência local (HTTP) com retry/checksum.

**Critério**: deploy E2E de um SLM do Developer OS para um Edge (QEMU aarch64 ou RPi validado) com health check ok.

---

## FASE 8 — SECURITY

**Meta**: isolamento real de modelos/serviços.

**Entregas**:
- [ ] Mapear suporte real (`contain`, schemes, sudo) e documentar `AI Permissions`.
- [ ] Policy por modelo (filesystem.read/write, network, device, compute).
- [ ] Execução de inferência em container/isolamento `contain`.

**Critério**: um modelo com policy restrita não acessa rede/filesystem fora da política; teste automatizado negativo.

---

## FASE 9 — HARDWARE ACCELERATION

**Meta**: acelerar quando tecnicamente suportado.

**Entregas**:
- [ ] Avaliar drivers GPU no Redox (Intel) e possíveis usos (compute via OpenCL? comunitário) — investigar.
- [ ] NPU (ex.: RPi NPU) — só quando driver existir.
- [ ] Refinar backend compute com SIMD/feature flags no Candle.

**Critério**: benchmark comparativo CPU vs acelerado, só com suporte real no Redox.

---

## FASE 10 — DEVELOPER PREVIEW

**Meta**: publicação e adoção.

**Entregas**:
- [ ] ISO Developer OS regenerável.
- [ ] Imagem RPi (validada na fase 6).
- [ ] Documentação completa + exemplos liberados.
- [ ] Benchmarks publicados.
- [ ] Website/CONTRIBUTING/ROADMAP público.
- [ ] CI completo no plataforma (format/lint/unit/integration/build/QEMU boot/system tests/package/release).

**Critério**: `make release` produz artefatos reprodutíveis; CI verde com boot QEMU em todos os PRs.

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