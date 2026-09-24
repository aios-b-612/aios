# AIOS — Registro de Decisões (ADR)

> Formato: ADR simples. Cada entrada: contexto, decisão, consequências, status.
> **Regra** — nenhuma decisão destrutiva ou não reversível sem revisão explícita.

---

## ADR-001 — NÃO modificar o kernel upstream no início

- **Status**: Aceito
- **Contexto**: O Redox upstream é um microkernel ativo. Modificações sem necessidade técnica seriam um fork e quebrariam updates.
- **Decisão**: Todas as funcionalidades são implementadas em userspace (serviço, daemon, CLI, package, runtime, library, config). Kernel só quando: (1) tecnicamente necessário; (2) justificado; (3) com testes; (4) com docs; (5) sem alternativa em userspace.
- **Consequências**: + compatibilidade upstream; - acesso a recursos profundos (ex.: aceleradores) não disponíveis no início.

## ADR-002 — GGUF como formato nativo de modelo

- **Status**: Aceito
- **Contexto**: GGUF é amplamente usado pela comunidade (llama.cpp), auto-descritivo, com metadata rica.
- **Decisão**: GGUF é o formato primário. Implementar parser puro-Rust (metadata, checksum, quantização, contexto, requisitos) no `aios-core`.
- **Consequências**: Maior portabilidade; parser próprio elimina dependência C.

## ADR-003 — Backend de inferência primário: Candle (CPU, Rust)

- **Status**: Proposto (validar na Fase 3 com build real no target `-unknown-redox`)
- **Contexto**: Rust puro sem libc pesada; PyTorch/TensorFlow inviáveis. llama.cpp requer pthreads/FFI C robusto.
- **Decisão**: Adotar Candle com backend CPU como primeira opção; manter trait `ComputeBackend` para plugar GPU/NPU/outros depois.
- **Consequências**: + simplicidade e portabilidade; - performance GPU/NPU adiada.
- **Backup**: se Candle não compilar no Redox, fallback para `wonnx` (já tem receita wip) ou tokenizer+inferência pura Rust minimal para os primeiros SLM.

## ADR-004 — Alvo inicial: x86_64; ARM via QEMU virt; RPi somente validado

- **Status**: Aceito
- **Contexto**: Auditoria: x86_64 maduro, aarch64 funcional no QEMU, RPi 3B+ "boot", RPi 4/5 não validados. Wi-Fi e Bluetooth não suportados. **Validado em Fase 1 (2026-09-24)**: QEMU aarch64 boots até kernel+initfs, mas o daemon `nvmed` initfs estoura a stack (guard page) no master ⇒ `/usr` não monta ⇒ sem login. Upstream não faz CI de boot aarch64.
- **Decisão**: Desenvolvimento em x86_64; validação ARM em QEMU virt (aarch64); hardware Raspberry Pi apenas quando boot real comprovado (começando RPi 3B+). Proibido "fake support".
- **Consequências**: Produto confiável; RPi 4/5 não prometido até validação. Edge OS aarch64: imagem constrói e canário de boot (bootloader+kernel) passa; userland bloqueada por bug upstream — monitorar (aguardar correção upstream; sem contribuir) antes de Fase 5.

## ADR-005 — Isolamento via `contain` + schemes, sem sandbox fake

- **Status**: Aceito
- **Contexto**: Não existem cgroups/namespaces estilo Linux. Existe `contain` (scheme-based) e schemes por usuário.
- **Decisão**: AI Permissions implementadas com mecanismos que o Redox realmente oferece (`contain`, schemes, sudo). Documentar limitações; não criar ilusão de sandbox.
- **Consequências**: Segurança honesta; o kernel pode precisar de evolução futura para mais isolamento (documentado, não implementado sem necessidade).

## ADR-006 — Offline-first com cloud apenas para download/update

- **Status**: Aceito
- **Contexto**: Produto promete funcionar sem internet.
- **Decisão**: Inferência, API, monitor, admin locais todos offline. Internet usada apenas para baixar modelos/atualizações/deploy remoto solicitados explicitamente.
- **Consequências**: UX local simples; registro de modelos depende de cache local robusto.

## ADR-007 — Perfis de imagem separados para Developer e Edge

- **Status**: Aceito
- **Contexto**: Dois produtos com necessidades opostas (dev completo vs borda mínima).
- **Decisão**: Um `aios-platform` compartilhado; dois perfis de config: `ai-developer` (≈desktop) e `ai-edge` (≈server/minimal sem GUI). Compartilham `aios-core`.
- **Consequências**: Build único, distribuição unificada.

## ADR-008 — Cache de modelos em `/var/lib/ai/models`

- **Status**: Aceito
- **Contexto**: Redox usa `/var/lib` para dados de estado (ver `base.toml`).
- **Decisão**: Cache em `/var/lib/ai/models`, com subdiretórios por modelo/versão e arquivo de metadata + checksums.
- **Consequências**: Compatível com convenções Redox.

## ADR-009 — CI canário = QEMU boot

- **Status**: Aceito
- **Contexto**: Nenhum PR deve quebrar boot silenciosamente.
- **Decisão**: Pipeline: format → lint → unit → integration → build → QEMU boot → system tests → package → release. Boot QEMU obrigatório para merge.
- **Consequências**: Custo de CI maior; qualidade garantida.

## ADR-010 — Tools de build próprios (scripts/) mas usando MD do upstream

- **Status**: Aceito
- **Contexto**: O Meta-repo upstream (`redox-os`) tem make/qemu robusto; não queremos reinventar.
- **Decisão**: O meta-repo `platform/` referencia o upstream como submodule/subtree ou mirror, e adiciona `scripts/build.sh|run-qemu.sh|test.sh|debug-qemu.sh` que chamam o tooling upstream (+ perfis extra). Nada destrutivo no upstream.
- **Consequências**: Rápido de começar; o acoplamento ao upstream é explícito e revisável.

## ADR-011 — API do AIOS independente do SO

- **Status**: Aceito
- **Contexto**: AI Core deve rodar em ambos OS e, se possível, em outros sistemas.
- **Decisão**: `aios-core` usa boundary traits; crates dependentes de plataforma ficam em módulos feature-gated. Code paths Redox isolados.
- **Consequências**: Portabilidade; pequena sobrecarga de abstração.

## ADR-012 — SLMs ≤ 3B como alvo inicial

- **Status**: Aceito
- **Contexto**: RAM edge (1–8GB), CPU-only.
- **Decisão**: Alvo SLM 100M–3B (Q4). Modelos maiores só se medidos (guarda de benchmark).
- **Consequências**: Escopo claro; roadmap focado em tarefas especializadas.

## ADR-013 — Validar estabilidade antes de prometer "self-hosted build"

- **Status**: Aceito
- **Contexto**: Toolchain `rust` self-hosted presente no perfil `ai-developer` e binários executam, mas `rustc` crasha com `UNHANDLED EXCEPTION` (kernel) ao compilar de verdade sob QEMU/KVM (audit §2.15). Padrão já visto no aarch64 (initfs `nvmed` estoura stack). Upstream só cobre TCG/podman/repo-tree; não valida esse perfil sob KVM+serial.
- **Decisão**: Não prometer "dev/build sel-hosted funcional dentro do OS" até demonstrado em bootstrap limpo (KVM e depois hardware nativo). Tratar instabilidade de userland sob emulação como risco de plataforma (não da nossa config) e documentar internamente (ver `docs/UPSTREAM_REPORT_KVM_RUSTC.md`; **sem envio upstream**). Critério da Fase 2 fica "parcial" até lá.
- **Consequências**: Fase 2 (build self-hosted) dependente de upstream; caminhos de   mitigação: testar (a) TCG puro, (b) hardware nativo via `cookbook` local, (c) tentar mitigação local do kernel via tree próprio (fork não contribuído); usuário escolhe.

---

## Decisões Rejeitadas (e por quê)

- **Rejeitado**: "Fork próprio do kernel" (ADR-001).
- **Rejeitado**: "Prometer suporte RPi 4/5 sem validação" (ADR-004).
- **Rejeitado**: "Usar Python/PyTorch como runtime base" (auditoria: relibc/POSIX falha; Python limitado no Redox).
- **Rejeitado**: "Construir sandbox própria tipo seccomp/cgroups" (Redox não tem; seria fake).
- **Rejeitado**: "GGML/llama.cpp como backend default" (dependência C/pthreads; rever quando relibc amadurecer).

---

## Formato de nova ADR

1. Número sequencial ADR-NNN.
2. Título descritivo.
3. Contexto histórico.
4. Decisão (curta, acionável).
5. Consequências (+/-).
6. Status (Proposto/Aceito/Deprecado/Superseded).
7. Referência à PR/Doc quando aplicável.

*Próximo: plano técnico da Fase 1 no `README.md` do `platform/` (ver seção final da conversa).*