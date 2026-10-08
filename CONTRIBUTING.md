# Como contribuir

O AIOS é um meta-repo: ele constrói o Redox OS com um cookbook próprio em Rust
e embarca o runtime de IA. Consequência prática: quase toda mudança de
plataforma só é confiável depois de **rodar o build e o boot**, não depois de
compilar. Um PR que só passa em `cargo test` ainda não provou nada sobre a
imagem.

Este documento é curto de propósito. O que vale saber está em três lugares:

| Onde | O quê |
| --- | --- |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | O que já foi entregue e o que está bloqueado, com o motivo |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | ADRs: por que o projeto é assim |
| [`docs/gotchas/`](docs/gotchas) | Armadilhas já descobertas, para não redescobrir |

## Antes de abrir PR

```bash
cargo fmt --all -- --check
cargo clippy --all -- -D warnings
cargo test --all
```

É exatamente o que o CI roda. Note que o clippy é `cargo clippy --all`, **sem**
`--all-targets` — o CI não linta código de teste. Se você passar `--all-targets`
vai aparecer aviso em `cli/ai/src/tasks.rs`, `cli/dev/src/scaffold.rs` e
`deploy/tests/e2e_transfer.rs` que o CI não vê. Corrigir esses três é um PR
bem-vindo, mas é separado.

## Mudança que toca a plataforma

Uma mudança em `platform/`, `Cargo.toml` ou no pin upstream exige validação de
boot, não só build:

```bash
./platform/scripts/build.sh -a x86_64 -c ai-developer -n live
./platform/scripts/test.sh x86_64 ai-developer
```

`-n` é build **nativo**. O caminho podman existe (`platform/scripts/build.sh` sem
`-n`) mas **não é validado** — ver `docs/gotchas/podman-build-unvalidated.md`. Não
troque o CI para podman sem antes fechar essa lacuna.

O build sem terminal define `CI=1` e isso desliga o TUI do `repo cook`, que em
modo não interativo trava. Se quiser o TUI, use `AIOS_TUI=1` num terminal real.

## Contrato com o upstream

Três pontos que não são negociáveis e que já custaram tempo:

1. **Não modificar o kernel upstream** (ADR-001). O Redox entra como submódulo/
   clone externo, pinado em `platform/upstream.lock`, e é *trackeado como
   somente-leitura*: um fork nosso seria trabalho invisível para quem só lê o
   repositório. Patch upstream é o canal correto.

2. **Patch local vive em `platform/patches/<arch>/`, versionado aqui.** Uma
   exceção documentada existe: `scripts/apply-patches.sh` rewrite de um recipe
   do cookbook dentro de `redox-os/`, porque o flag `--cookbook` do
   `repo cook` é código morto nesta versão e não permite sobrepor um recipe.
   O pin em git continua intacto, o overlay é idempotente e
   `bootstrap.sh --verify` falha (exit 2) se ele divergir de
   `platform/patches/`.

   Duas armadilhas, ambas já mordidas: recipe com patch precisa ser forçada
   para a regra `source` no `cookbook.lock`, senão `REPO_BINARY=1` baixa um
   `source.pkgar` e **ignora o patch sem erro**; e `bootstrap.sh --update`
   descarta o overlay, então o script precisa reaplicar depois. Ver
   `platform/patches/aarch64/README.md` antes de adicionar outro patch: se ele
   exigir um segundo recipe, o script precisa de um caso novo.

3. **Não subir artefatos grandes** (`.gguf`, ISO, `*.tokenizer.json`). O
   tokenizer de um modelo é um artefato de modelo, não um arquivo de código; o
   `docs/benchmarks.md` traz os comandos de download.

## Fluxo de branches

`dev` é a branch de integração. O fluxo é obrigatório e o CI o faz cumprir:

| Origem | Destino | Regra |
| --- | --- | --- |
| `feature/*`, `fix/*`, `docs/*`, `chore/*`, `ci/*`, `test/*`, `refactor/*`, `build/*`, `perf/*` | `dev` | PR com base `dev`; o job `Branch flow guard` falha se a base for outra |
| `hotfix/*` | `main` | Só emergência de produção; depois o mesmo fix é replicado em `dev` |
| `dev` | `main` | Promote é um PR separado, deliberado |
| `main` | — | Nunca é origem de PR |

Concluído e mergeado, **a branch morre**: o repositório apaga a branch
automaticamente no merge (configuração "Automatically delete head branches")
e o job `branch-cleanup.yml` (a cada push em `dev`/`main` + diário) apaga do
remoto qualquer branch cujo tip já esteja em `dev`/`main` sem PR aberta.
Trabalho em curso mantém a branch; trabalho mergeado não fica pendurado.

## Autoria

**O nome do assistente não aparece em commits, PRs, issues ou comentários.**

- Commits: apenas o autor do git (configurado em `user.name`/`user.email`).
- PRs: autor do git; sem `Co-authored-by` do assistente.
- Mensagens de commit, títulos/descrições de PR, issues: voz do autor.
- No Cursor: `attribution.attributeCommitsToAgent` e `attributePRsToAgent` em `false`.
- No IDE: Cursor Settings → Agent → Attribution (desligado).

Isso garante rastreabilidade clara e evita atribuição ambígua.

## Regras de conteúdo

- **Português** para docs. **Inglês** para mensagens de commit e comentários de
  código — é a mistura que o histórico já segue.
- Commit no formato Conventional Commits, imperativo, primeira linha com
 _no máximo ~72 caracteres_:
  `type(scope): o que mudou`. Tipos em uso: `feat`, `fix`, `docs`, `test`,
  `build`, `ci`, `chore`.
- Descreva **por que**, não o que. O diff já mostra o que.
- Se o commit conserta algo que um teste não pegava, o teste vai junto.
- Não edite a kernel upstream "só para compilar".

## O que não aceitamos

Um item marcado como entregue no `ROADMAP.md` que não está no repositório. Isso
já aconteceu com o site público e com a imagem RPi, e as duas entradas tiveram
que ser corrigidas por registro. Se você não tem como provar que está lá, deixe
`[ ]` e escreva o bloqueio.

O mesmo vale para benchmark: número sem ambiente, sem comando e sem método não
entra. `docs/benchmarks.md` é o formato — leia antes de acrescentar uma linha.

## Referência rápida

```bash
# CLI de IA
cargo run -p aios-cli -- ai --help
cargo run -p aios-cli -- ai doctor

# daemon de edge
cargo run -p edge-ai -- edge --help

# segurança
cargo run -p aios-security -- aios-security --help

# scaffold de app
cargo run -p aios-dev -- aios-dev --help
```

Exemplos completos e executáveis: [`examples/`](examples/).
