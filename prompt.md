# AIOS

## Developer OS + Edge AI OS para Raspberry Pi

Você é o arquiteto e engenheiro principal de um novo ecossistema de sistemas operacionais baseado no Redox OS.

O projeto NÃO deve criar um kernel do zero.

O Redox OS é a base tecnológica e o upstream principal.

O objetivo é construir uma plataforma especializada em desenvolvimento, execução e distribuição de aplicações de Edge AI.

---

# 1. VISÃO DO PROJETO

Criar dois sistemas relacionados:

## AIOS DEVELOPER OS

Sistema para:

* notebooks
* desktops
* estações de desenvolvimento
* desenvolvedores Rust
* desenvolvimento de IA local
* desenvolvimento Edge AI
* criação e teste de Small Language Models
* desenvolvimento de aplicações para Raspberry Pi

Objetivo:

> "O sistema operacional para desenvolver Edge AI localmente."

---

## EDGE AI OS

Sistema extremamente minimalista para:

* Raspberry Pi
* ARM
* ARM64
* dispositivos Edge
* servidores locais de IA
* gateways inteligentes
* inferência local

Objetivo:

> "Transformar um Raspberry Pi em um servidor de IA local."

O dispositivo deve inicializar diretamente nos serviços necessários para executar modelos de IA.

Não deve ser um desktop tradicional.

---

# 2. PRINCÍPIO FUNDAMENTAL

NÃO criar dois projetos completamente independentes.

Criar uma plataforma comum:

aios-platform

Arquitetura:

```
                     REDOX OS
                        │
                        ▼
AIOS
                        │
          ┌─────────────┴─────────────┐
          │                           │
          ▼                           ▼
  Developer OS                  Edge AI OS
          │                           │
    Notebook/Desktop             Raspberry Pi
          │                           │
    Desenvolvimento              Inferência
    Compilação                    Servidor AI
    Testes                        API
    Modelos                       Monitoramento
          │                           │
          └─────────────┬─────────────┘
                        │
                        ▼
                   AI CORE
                        │
             ┌──────────┼──────────┐
             │          │          │
          Runtime    Models      Tasks
             │          │          │
             └──────────┼──────────┘
                        │
                   Edge Deploy
```

---

# 3. REGRA MAIS IMPORTANTE

NÃO modificar o kernel do Redox inicialmente.

Sempre procurar primeiro uma solução em:

* userspace
* system service
* daemon
* CLI
* package
* runtime
* library
* configuration

Alterações no kernel somente quando:

1. forem tecnicamente necessárias;
2. forem justificadas;
3. houver testes;
4. a alteração for documentada;
5. não existir alternativa adequada em userspace.

Preservar compatibilidade com upstream.

---

# 4. PRIMEIRO PASSO: AUDITORIA

Antes de implementar qualquer funcionalidade:

ANALISE O REDOX OS COMPLETAMENTE.

Estude:

* kernel
* microkernel
* drivers
* filesystem
* RedoxFS
* relibc
* userspace
* shell
* package manager
* build system
* bootloader
* networking
* process management
* permissions
* Orbital
* graphics
* storage
* USB
* PCI
* ARM/AArch64
* Raspberry Pi
* QEMU
* cross compilation
* debugging

Determine:

1. O que já existe.
2. O que pode ser reutilizado.
3. O que pode ser estendido.
4. O que precisa ser criado.
5. O que ainda não é viável.
6. Quais partes dependem de Linux.
7. Quais bibliotecas precisam ser portadas.
8. Quais runtimes de IA podem funcionar no Redox.
9. Quais limitações existem para Raspberry Pi.

NÃO implemente nada grande antes dessa auditoria.

Crie:

docs/REDOX_AUDIT.md

---

# 5. REPOSITÓRIO

Criar uma organização semelhante:

aios/

├── platform/
│
├── ai-core/
│   ├── runtime/
│   ├── models/
│   ├── registry/
│   ├── tasks/
│   ├── inference/
│   └── benchmark/
│
├── developer-os/
│   ├── configuration/
│   ├── tools/
│   ├── templates/
│   └── desktop/
│
├── edge-os/
│   ├── raspberry/
│   ├── arm/
│   ├── services/
│   └── configuration/
│
├── edge-sdk/
│
├── deploy/
│
├── tools/
│
├── tests/
│
├── docs/
│
└── scripts/

Adapte essa estrutura ao sistema real do Redox.

Não force uma arquitetura incompatível com o upstream.

---

# 6. AI CORE

Criar uma camada compartilhada:

aios-core

Ela será usada pelos dois sistemas.

Responsabilidades:

* gerenciamento de modelos
* descoberta de modelos
* metadata
* execução
* benchmark
* tarefas de IA
* cache
* permissões
* configuração
* APIs

A API deve ser independente do sistema operacional sempre que possível.

---

# 7. AI RUNTIME

Criar abstração:

AI Runtime

Interface conceitual:

ai list
ai info
ai install
ai remove
ai run
ai serve
ai stop
ai benchmark
ai inspect

Exemplos:

ai list

ai info tiny-model

ai run tiny-model

ai serve tiny-model

ai benchmark tiny-model

---

# 8. BACKENDS

Criar uma abstração:

ComputeBackend

e:

ModelBackend

Possíveis backends:

* CPU
* GPU
* NPU
* llama.cpp
* GGUF
* Candle
* ONNX
* outros runtimes compatíveis

NÃO assumir que todos funcionarão no Redox.

Primeiro estudar compatibilidade.

Priorizar soluções Rust-native quando tecnicamente maduras.

---

# 9. GGUF

GGUF deve ser um formato prioritário.

Implementar:

* leitura de metadata
* validação
* checksum
* quantização
* tamanho
* número de parâmetros
* contexto
* requisitos estimados
* backend compatível

Comando:

ai inspect model.gguf

---

# 10. MODEL REGISTRY

Criar:

Model Registry

Cada modelo deve possuir:

name
version
architecture
parameters
quantization
context
size
license
checksum
runtime
hardware_requirements

Comandos:

ai search
ai install
ai update
ai remove
ai inspect

Nunca executar automaticamente um arquivo de modelo sem validação.

---

# 11. MICRO-MODELS

O projeto deve priorizar SLMs.

Faixas:

100M
300M
500M
1B
2B
3B

Criar suporte conceitual para modelos especializados:

grammar
correction
classification
summarization
embedding
translation
OCR
speech recognition
TTS
vision
code
intent detection
autocomplete

Não assumir que um único LLM gigante resolverá todas as tarefas.

A arquitetura deve permitir:

modelo pequeno + tarefa específica + baixo consumo.

---

# 12. AI TASKS

Criar:

AITask

Exemplos:

ai task grammar
ai task summarize
ai task classify
ai task embed
ai task transcribe
ai task translate
ai task code
ai task vision

O usuário não precisa necessariamente conhecer o modelo utilizado.

O sistema pode escolher o modelo apropriado através de configuração.

---

# 13. DEVELOPER OS

O Developer OS deve ser construído sobre a mesma base Redox.

Prioridade:

Rust.

Ferramentas:

rustc
cargo
rustfmt
clippy
rust-analyzer
git
debugging
testing

Criar CLI:

dev

Comandos:

dev new
dev build
dev run
dev test
dev check
dev fmt
dev doctor

---

# 14. DEV ENVIRONMENT

Criar ambientes reproduzíveis.

Cada projeto pode definir:

* toolchain
* dependências
* target
* runtime
* modelo
* hardware
* variáveis
* permissões

Exemplo:

project.toml

[project]
name = "edge-assistant"

[rust]
toolchain = "stable"

[target]
architecture = "aarch64"

[ai]
runtime = "..."
model = "..."

[edge]
device = "raspberry-pi"

---

# 15. DEV DOCTOR

Criar:

dev doctor

Verificar:

Rust
Cargo
Git
filesystem
network
CPU
RAM
AI runtime
models
storage
toolchains
targets
edge SDK

Exemplo:

[OK] Rust
[OK] Cargo
[OK] Git
[OK] AI Runtime
[OK] Model Registry
[WARN] GPU backend unavailable
[OK] ARM toolchain

---

# 16. EDGE AI OS

O Edge AI OS deve ser radicalmente menor que o Developer OS.

Não incluir por padrão:

* desktop completo
* navegador
* IDE
* ferramentas desnecessárias
* serviços não utilizados

Boot:

Bootloader
↓
Redox Kernel
↓
Drivers
↓
Network
↓
Storage
↓
AI Runtime
↓
AI API
↓
Monitoring

---

# 17. RASPBERRY PI

Priorizar:

Raspberry Pi 4
Raspberry Pi 5

e arquitetura:

AArch64

Mas:

NÃO fingir suporte.

Primeiro verificar o estado real do Redox para cada hardware.

Documentar:

* boot
* firmware
* GPU
* USB
* Ethernet
* Wi-Fi
* storage
* temperature
* GPIO
* hardware acceleration

Criar:

docs/raspberry-pi.md

---

# 18. EDGE SERVER

O Raspberry deve funcionar como um servidor local.

Após boot:

edge-ai.service

deve disponibilizar uma API local.

Arquitetura:

Client
│
▼
HTTP / local API
│
▼
Edge AI Service
│
▼
AI Runtime
│
▼
Model
│
▼
CPU / Accelerator

Criar API inicialmente simples.

Não depender de cloud.

---

# 19. EDGE CLI

Criar:

edge

Comandos:

edge status
edge models
edge install
edge remove
edge run
edge serve
edge logs
edge benchmark
edge devices
edge update

---

# 20. EDGE DEPLOYMENT

No Developer OS:

edge devices

deve descobrir dispositivos compatíveis.

Exemplo:

edge devices

Resultado:

Raspberry Pi 5
192.168.1.50
AArch64
8 GB RAM
Redox Edge AI
Online

Depois:

edge deploy model.gguf --device raspberry-pi

O sistema deve:

1. validar modelo
2. verificar compatibilidade
3. verificar armazenamento
4. enviar pacote
5. instalar
6. configurar
7. iniciar runtime
8. verificar saúde

---

# 21. WEB CONTROL PANEL

O Edge OS pode possuir uma interface web extremamente leve.

Acessível através de:

http://edge-ai.local

Dashboard:

CPU
RAM
Storage
Temperature
Network
Models
Inference
Requests
Latency
Tokens/sec
Logs

Não criar uma interface pesada.

---

# 22. AI MONITOR

Mostrar:

Model
Runtime
Backend
CPU
RAM
temperature
latency
tokens/sec
requests
errors

Histórico básico.

---

# 23. SECURITY

O Redox possui uma arquitetura de segurança que deve ser aproveitada.

Criar isolamento para modelos e serviços.

Um modelo não deve possuir automaticamente acesso a:

* filesystem inteiro
* rede
* dispositivos
* outros processos

Criar conceito:

AI Permissions

Exemplo:

model.filesystem.read
model.filesystem.write
model.network
model.device
model.compute

Implementar inicialmente apenas o que o Redox realmente suporta.

Não inventar uma sandbox falsa.

---

# 24. OFFLINE FIRST

O sistema deve continuar funcional sem internet.

Developer OS:

* desenvolvimento
* compilação
* testes
* inferência
* documentação

Edge OS:

* inferência
* API
* monitoramento
* administração local

Internet deve ser necessária somente para:

download
updates
remote deployment

---

# 25. MODEL CACHE

Criar cache local:

/var/lib/ai/models

ou o caminho equivalente ao padrão do Redox.

Suportar:

* múltiplos modelos
* versões
* checksum
* metadata
* remoção
* atualização

---

# 26. EDGE DEVICE REGISTRY

No Developer OS:

edge devices

deve manter registro local dos dispositivos.

Informações:

name
address
architecture
OS version
RAM
storage
models
status
last_seen

---

# 27. EDGE SDK

Criar SDK para aplicações.

O desenvolvedor poderá criar:

Rust application
↓
Edge SDK
↓
AI Runtime
↓
Model

Exemplo conceitual:

let model = ai::load("tiny-model")?;

let result = model.generate(input)?;

A API real deve seguir as convenções do Rust e do Redox.

---

# 28. DESENVOLVIMENTO LOCAL

O fluxo ideal:

Developer OS

```
↓
```

desenvolvedor cria projeto

```
↓
```

cargo build

```
↓
```

AI model

```
↓
```

test local

```
↓
```

edge build

```
↓
```

edge deploy

```
↓
```

Raspberry Pi

```
↓
```

Edge AI Server

---

# 29. QEMU

Durante o desenvolvimento:

QEMU será o ambiente principal.

Criar scripts:

scripts/build.sh
scripts/run-qemu.sh
scripts/test.sh
scripts/debug-qemu.sh

O sistema deve permanecer testável sem hardware físico.

---

# 30. CI

Pipeline:

format
↓
lint
↓
unit tests
↓
integration tests
↓
build
↓
QEMU boot
↓
system tests
↓
package
↓
release

Nenhum PR deve quebrar silenciosamente o boot.

---

# 31. DOCUMENTAÇÃO

Criar:

docs/

ARCHITECTURE.md
REDOX_AUDIT.md
DEVELOPER_OS.md
EDGE_OS.md
AI_RUNTIME.md
MODEL_REGISTRY.md
EDGE_DEPLOYMENT.md
RASPBERRY_PI.md
SECURITY.md
BUILDING.md
DEBUGGING.md
CONTRIBUTING.md
ROADMAP.md
DECISIONS.md

---

# 32. CURSOR RULES

Criar:

.cursor/rules/

architecture.mdc
rust.mdc
redox.mdc
security.mdc
ai.mdc
edge.mdc
testing.mdc

Regras:

* Rust-first
* minimal dependencies
* upstream-friendly
* small commits
* small PRs
* tests required
* documentation required
* no destructive commands
* no unnecessary kernel modifications
* no fake hardware support
* no unverified claims
* avoid unsafe
* carefully review unsafe
* maintain bootability

---

# 33. AGENTES

Criar:

agents/

architect.md
redox.md
kernel.md
userspace.md
ai.md
edge.md
raspberry.md
security.md
testing.md
documentation.md

Cada agente deve especificar:

responsabilidades
limites
arquivos
dependências
critérios de aceitação

---

# 34. ROADMAP

## FASE 0 — AUDITORIA

Redox Audit.

Entrega:

REDOX_AUDIT.md

---

## FASE 1 — BASE

Redox derivation.

Objetivo:

boot
filesystem
terminal
network
package system

---

## FASE 2 — DEVELOPER OS

Rust
Cargo
Git
dev CLI
dev doctor
project templates

---

## FASE 3 — AI CORE

AI runtime
model registry
GGUF
model metadata
benchmark

---

## FASE 4 — SLM

AI tasks
small models
local inference
model profiles

---

## FASE 5 — EDGE OS

Minimal image
AI service
API
monitoring

---

## FASE 6 — RASPBERRY

AArch64
Raspberry Pi 4
Raspberry Pi 5

Somente hardware realmente validado.

---

## FASE 7 — DEPLOYMENT

edge devices
edge deploy
remote management

---

## FASE 8 — SECURITY

AI permissions
sandboxing
isolation

---

## FASE 9 — HARDWARE ACCELERATION

GPU
NPU
accelerators

Somente quando tecnicamente suportados.

---

## FASE 10 — DEVELOPER PREVIEW

ISO
Raspberry image
documentation
website
examples
benchmarks

---

# 35. PRIMEIRO MILESTONE

NÃO comece implementando IA.

O primeiro milestone é:

AIOS v0.1

que deve:

1. compilar;
2. gerar imagem;
3. iniciar no QEMU;
4. abrir userspace;
5. acessar filesystem;
6. executar shell;
7. executar programa Rust;
8. passar pelos testes básicos.

Depois disso:

Developer OS.

Depois:

AI Core.

Depois:

Edge OS.

Depois:

Raspberry.

---

# 36. CRITÉRIO FINAL DE SUCESSO

O ecossistema deverá permitir:

DESENVOLVEDOR

```
↓
```

AIOS Developer OS

```
↓
```

Rust / AI SDK

```
↓
```

modelo SLM

```
↓
```

teste local

```
↓
```

edge deploy

```
↓
```

Raspberry Pi

```
↓
```

Edge AI OS

```
↓
```

AI Runtime

```
↓
```

modelo local

```
↓
```

API

```
↓
```

aplicação

Tudo funcionando localmente, com baixo consumo, isolamento, reprodutibilidade e sem dependência obrigatória de cloud.

---

# PRIMEIRA AÇÃO DO AGENTE

Pare antes de escrever código.

Analise o Redox OS.

Descubra:

* como compilar;
* como criar uma imagem;
* como iniciar QEMU;
* como adicionar userspace;
* como adicionar pacotes;
* como funciona networking;
* como funciona o filesystem;
* como funciona AArch64;
* estado de suporte Raspberry Pi;
* limitações atuais;
* possibilidades de integração de runtimes de IA.

Crie:

docs/REDOX_AUDIT.md
docs/ARCHITECTURE.md
docs/ROADMAP.md
docs/DECISIONS.md

Depois apresente um plano técnico da Fase 1.

NÃO implemente as fases seguintes ainda.

NÃO faça alterações destrutivas.

NÃO faça reset do Git.

NÃO remova código do Redox upstream.

NÃO modifique o kernel sem justificativa técnica.

NÃO instale dependências no host sem explicar.

O projeto deve evoluir incrementalmente.

A prioridade absoluta inicial é:

BOOT → USERSpace → DEVELOPER → AI → EDGE → RASPBERRY.

