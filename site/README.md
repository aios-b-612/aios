# AIOS - Public Website

**Website público do AIOS** - Sistema Operacional AI-First para edge computing.

> **Nota:** Este repositório (`aios-b-612/aios-b-612.github.io`) hospeda o site público do projeto AIOS. O código do SO permanece neste repositório (`aios-b-612/aios`). O site é versionado separadamente conforme ADR-022.

## Sobre

O site apresenta a linguagem visual e a identidade do [obscura.sh](https://obscura.sh/), adaptada para o AIOS, preservando:
- Conteúdo sobre edge AI, GGUF models, device management
- Multi-arquitetura: x86_64, aarch64, ARMv7
- Interface de desenvolvedor e cases de uso

## Estrutura

```
site/
├── index.html       # Página principal (22KB, HTML5 + CSS inline)
└── assets/          # Diretório para assets futuros (ícones, etc.)
```

## Design

**Inspirado em obscura.sh** — temas escuros, acento teal `#00d4aa`, tipografia Inter, layout grid responsivo, animações smooth e IntersectionObserver scroll reveals.

## Tecnologias

- HTML5 sem dependências externas (CSS inline)
- Google Fonts: Inter + JetBrains Mono (preconnect)
- Vanilla JavaScript — IntersectionObserver, contra-animations de counters
- Totalmente responsivo: mobile-first, grid reflow em 768px

## Publicação

Este site é publicado automaticamente no GitHub Actions:
- **Gatilho:** push no branch `main` (quando `site/` for modificado)
- **Destino:** `aios-b-612.github.io` branch `main`
- **URL:** `https://aios-b-612.github.io`

## Desenvolvimento

Para fazer alterações visuais:
1. Editar `site/index.html`
2. Commit no `main` do `aios-b-612/aios-b-612.github.io`
3. O GitHub Actions deployará automaticamente em ~1-2 minutos

Ou publicar manualmente:
```bash
git clone https://github.com/aios-b-612/aios-b-612.github.io.git
cp -r /caminho/para/aios/site/* aios-b-612.github.io/
cd aios-b-612.github.io
git add -A && git commit -m "docs: update website design"
git push origin main
```

## Conteúdo Preservado

- GGUF model support and inference
- Edge AI deployment and management
- Device management across architectures
- Security with isolated containers
- Multi-architecture: x86_64, aarch64, ARMv7
- REST API and web panel interface

## Roadmap

- [x] Versão inicial com fidelidade ao design obscura.sh
- [i18n] Versões PT/EN se necessário
- [custom domain] Domínio próprio após validação
- [SEO] Metadados otimizados para buscadores