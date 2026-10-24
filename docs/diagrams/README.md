# Diagramas Archify — AIOS

Este diretório contém os diagramas de arquitetura, fluxo e ciclo de vida do sistema operacional AIOS, autorados como **specs JSON versionadas** (`src/*.json`) e entregues como **HTML interativos** autônomos (`*.html`).

## Padrão adotado

| Diagrama | Tipo | Spec (versionado) | Artefato (entregue) | Descrição |
|----------|------|-------------------|---------------------|-----------|
| 01 | architecture | `src/01-camadas.architecture.json` | `01-camadas.html` | Camadas do SO: firmware, kernel, runtime, apps |
| 02 | architecture | `src/02-componentes-runtime.architecture.json` | `02-componentes-runtime.html` | Componentes runtime edge-ai + ai-core |
| 03 | sequence | `src/03-fluxo-requisicao.sequence.json` | `03-fluxo-requisicao.html` | Sequência `POST /api/infer` (daemon → runtime → cache) |
| 04 | architecture | `src/04-integracao-apps.architecture.json` | `04-integracao-apps.html` | Integração apps Laya Gateway + Web SQLite Admin |
| 05 | lifecycle | `src/05-ciclo-vida-modelo.lifecycle.json` | `05-ciclo-vida-modelo.html` | Ciclo de vida GGUF: install → cache → registry → load → infer → verify/fail/recovery → remove |
| 06 | architecture | `src/06-build-deploy.architecture.json` | `06-build-deploy.html` | Build cross-build Redox, imagem A/B, canário QEMU, edge bind-first |

## Como autorar / validar / entregar

### Pré-requisitos
- Skill `archify` instalada em `~/.agents/skills/archify/`
- Node.js (o CLI roda via `node bin/archify.mjs`)

### Pipeline por diagrama

```bash
cd ~/.agents/skills/archify

# 1. Validar (exige 9/9 checks showcase, 0 errors/warnings)
node bin/archify.mjs validate <tipo> /home/fasr/SSD_BACKUP/Workspace/aios/docs/diagrams/src/XX-<nome>.<tipo>.json --quality showcase --json

# 2. Entregar HTML
node bin/archify.mjs deliver <tipo> /home/fasr/SSD_BACKUP/Workspace/aios/docs/diagrams/src/XX-<nome>.<tipo>.json /home/fasr/SSD_BACKUP/Workspace/aios/docs/diagrams/XX-<nome>.html

# 3. Visual-check automatizado (viewports 1440x900, 1600x1000, 1920x1080, 2048x1320, light/dark)
node bin/archify.mjs visual-check /home/fasr/SSD_BACKUP/Workspace/aios/docs/diagrams/XX-<nome>.html
```

### Convenções de autoria

- `quality_profile: "showcase"` em todos os `meta`
- Sem `visual_preset`, sem `animation` (estáticos)
- Views ≤ 5 por diagrama
- Cards com fatos verificáveis (caminhos, comandos, portas, ADRs)
- Labels com identificadores exatos: `/api/infer`, `edge-ai.service`, `127.0.0.1:8989`, `registry.tsv`, `load_ms`
- `viewBox` ajustado para contenção vertical em 1440×900 (aspecto ≲ 0.43)
- Sublabels curtos (auto-shrink < 6px projetado causa overflow)

### Rebuild em lote (script sugerido)

```bash
#!/usr/bin/env bash
# scripts/diagrams.sh
set -euo pipefail
ARCHIFY=~/.agents/skills/archify/bin/archify.mjs
SRC=/home/fasr/SSD_BACKUP/Workspace/aios/docs/diagrams/src
DST=/home/fasr/SSD_BACKUP/Workspace/aios/docs/diagrams

for spec in "$SRC"/*.json; do
  base=$(basename "$spec" .json)
  type=$(jq -r '.diagram_type' "$spec")
  echo "=== $base ($type) ==="
  node "$ARCHIFY" validate "$type" "$spec" --quality showcase --json
  node "$ARCHIFY" deliver "$type" "$spec" "$DST/$base.html"
  node "$ARCHIFY" visual-check "$DST/$base.html"
done
```

## Legado (.webp)

Os 5 arquivos `.webp` originais (gerados do CSS do site, repo separado) foram **substituídos** pelos HTML Archify interativos. Referências em `docs/ARCHITECTURE.md` foram atualizadas para apontar aos `.html`.

Os `.webp` legados foram movidos para `legacy/` (fora do versionamento padrão) caso haja necessidade de comparação histórica.

## Divulgação: UI do viewer em inglês

O Archify renderiza a UI do viewer (toolbar, legenda, navegação) em inglês (`meta.locale` omitido → fallback `en`). O **conteúdo dos diagramas** (labels, cards, sublabels) é autorado em **pt-BR**. Isso é intencional e documentado aqui para transparência.

## Referências de schema

- `~/.agents/skills/archify/schemas/architecture.schema.json`
- `~/.agents/skills/archify/schemas/sequence.schema.json`
- `~/.agents/skills/archify/schemas/lifecycle.schema.json`
- `~/.agents/skills/archify/schemas/workflow.schema.json`
- Exemplos em `~/.agents/skills/archify/examples/*.json`

## Fatos-chave do sistema (para consistência entre diagramas)

- Daemon edge-ai: `127.0.0.1:8989`, rotas GET `/` (painel), `/api/health|models|benchmark|logs|metrics`, POST `/api/infer`
- Resolução: arquivo → registry → cache
- Cache: **1 modelo** (load_ms=0 se mesmo path)
- Registry TSV: `/var/lib/ai/registry.tsv` (ADR-008)
- Cache dir: `/var/lib/ai/models` (1777, ADR-017)
- Env overrides: `AIOS_MODELS_DIR`, `AIOS_REGISTRY`, `EDGE_BASE_URL`
- Apps: Laya Gateway (OpenAI-compat, fail-open), Web SQLite Admin (rusqlite, processo separado, WIP)
- Cross-build: `scripts/build-redox.sh` → `x86_64-unknown-redox`, `redox-os/` fork
- Imagem A/B: `platform/dist/` (MANIFEST.txt, upstream.lock), perfis `ai-developer` / `ai-edge`
- Canário QEMU: boot → `/api/health` → infer smoke
- Netstack Redox incompleto = blocker Fase 5 (ROADMAP)