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

- **Status**: Aceito (validado em Fase 3, 2026-09-24)
- **Contexto**: Rust puro sem libc pesada; PyTorch/TensorFlow inviáveis. llama.cpp requer pthreads/FFI C robusto.
- **Decisão**: Adotar Candle com backend CPU como primeira opção; manter trait `ComputeBackend` para plugar GPU/NPU/outros depois.
- **Consequências**: + simplicidade e portabilidade; - performance GPU/NPU adiada.
- **Backup**: se Candle não compilar no Redox, fallback para `wonnx` (já tem receita wip) ou tokenizer+inferência pura Rust minimal para os primeiros SLM.
- **Validação (Fase 3)**: full stack `candle-core 0.9.2` + `candle-nn` + `candle-transformers 0.9.2` + `tokenizers 0.21.4` cross-compila para `x86_64-unknown-redox` (binário estático 8.4 MB). `ai run` gera texto real com TinyLlama-1.1B-Chat Q4_K_M (GGUF llama-arch) tanto no host quanto in-guest (KVM). Ink-guest: ~1.7 tokens/s, load ~24-30 s. host: ~6.9 tokens/s, load ~0.56 s.

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

## ADR-014 — Projeto paralelo e privado: nenhum envio ao Redox nem a repositórios de código

- **Status**: Aceito
- **Contexto**: O Redox OS é a base tecnológica do AIOS (kernel, userspace, toolchain prefix). Direção do mantenedor (2026-09-24): o AIOS é um projeto **paralelo e privado**; não deve ser enviado/submetido ao Redox nem a repositórios de código fonte.
- **Decisão**: Nenhum código, receita, perfil, config, pacote, report, issue ou MR é enviado ao Redox OS (`redox-os/*`) nem a repositórios de código fonte. O upstream é consumido apenas como dependência passiva; qualquer correção local permanece no nosso tree. Repositórios locais (`aios/`, `platform/`) ficam **sem remote**.
- **Consequências**: + independência e privacidade; - ficamos fora de correções/benefícios upstream (fixes do kernel/userland dependem de terceiros). Report de estabilidade (rustc/cargo KVM) registrado apenas internamente (`docs/UPSTREAM_REPORT_KVM_RUSTC.md`).

## ADR-015 — Ferramentas do Developer OS: navegador obscura.sh; IDE opencode (prioridade); memória ai-memory (padrão)

- **Status**: Aceito
- **Contexto**: Escolha de navegador, IDE e ferramenta de memória padrão do Developer OS (perfil dev; Edge permanece sem eles). Direção do mantenedor (2026-09-24, incl. adendo ai-memory).
- **Decisão**: Navegador padrão: **obscura.sh** (`https://obscura.sh/`). IDE padrão: **opencode** (prioridade); **vscode** opcional. Memória de longo prazo para agentes: **ai-memory** (padrão, ver ADR-018). Edge AI OS não inclui navegador nem IDE.
- **Consequências**: + ferramenta definida para o perfil dev; - obscura.sh/vscode/ai-memory exigem portabilidade ao Redox (validar na Fase 3+; fallback: navegador/IDE leve nativo se não portarem).

## ADR-018 — Memória de longo prazo para agentes: ai-memory como ferramenta padrão

- **Status**: Aceito
- **Contexto**: Com opencode como IDE padrão (ADR-015) e o dispositivo como gadget do notebook de dev (ADR-016), sessões de agentes precisam de continuidade entre agentes, máquinas e reboots. Direção do mantenedor (2026-09-24): "ferramenta padrão dentro do nosso sistema" = **ai-memory** (`https://aimemorybr.netlify.app/pt-br/`, repo `github.com/akitaonrails/ai-memory`).
- **Decisão**: `ai-memory` é a ferramenta padrão de memória de longo prazo no AIOS (Developer OS). Binário único em Rust (MIT), sem conta/chave de API no caminho padrão (captura/consolidação sem LLM); integra com opencode e 20+ agentes via hooks/MCP; serve como daemon opcional (multimáquina/time) ou CLI local. Alinha com a visão "o modelo é alugado, a memória é nossa" — wiki em markdown puro, versionada em git, própria do usuário.
- **Consequências**: + memória persistente e portátil para agentes no dispositivo (cruza agentes, máquinas e reboots); + MIT/open, arquivos markdown auditáveis; - portabilidade a `x86_64-unknown-redox` a validar (Rust puro, mas com SQLite/HTTP e hooks por agente — risco baixo a médio; fallback: rodar no host/LAN apontando para o dispositivo); - é app de usuário, não runtime do Edge AI OS.
- **Referência**: Fase 3+ (embarcar binário `ai-memory` no Developer OS; `ai-memory run opencode` como fluxo padrão).

## ADR-016 — Objetivo estendido: servidor de IA + gadget de apoio ao notebook de dev

- **Status**: Aceito
- **Contexto**: A visão original era "Transformar um Raspberry Pi em um servidor de IA local". Direção do mantenedor (2026-09-24): o dispositivo também é um **gadget de apoio para o notebook principal de desenvolvimento de IA**.
- **Decisão**: O dispositivo serve a dois papéis: (1) servidor local de IA (inferência/tarefas offline); (2) gadget de apoio ao notebook de dev (offload de inferência, execução de tarefas, monitoramento). Ambos no mesmo runtime Edge AI OS.
- **Consequências**: + caso de uso imediato e útil no dia a dia do dev; - escopo do Edge OS inclui interface de integração com o notebook de dev (ex.: API/serve, CLI edge) já prevista nas Fases 4–5.

---

## ADR-017 — Cache global de modelos com escrita liberada (1777)

- **Contexto**: na Fase 3, `ai install hello-1b` falhou in-guest com `i/o: Permission denied (os error 13)`: `user` (uid 1000) não podia gravar em `/var/lib/ai` e `/var/lib/ai/models` (modo 755 root-owned), onde vivem o cache global e o registry `registry.tsv`.
- **Decisão**: `/var/lib/ai` e `/var/lib/ai/models` são criados com modo **1777** (sticky, world-writable) na imagem; `ai install/remove` gravam no cache global sem privilégios. É uma decisão de empacotamento da imagem, não do runtime: o daemon de runtime (Fase 4) e o CLI exigem que o único usuário do dispositivo consiga gerenciar modelos.
- **Consequências**: + gerenciamento de modelos sem sudo/root no Edge AI OS; + self-contained em device single-user; - segurança de multi-usuário deliberadamente não priorizada (dispositivo dedicado; reavaliar se um dia AIOS suportar multi-user como o Redox vanilla).
- **Status**: Aceito (2026-09-24).
- **Referência**: Fase 3 smoke-test; perms aplicadas na imagem manualmente até o rebuild incorporar `chmod 1777` na receita.

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