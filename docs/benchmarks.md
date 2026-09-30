# Benchmarks

Números medidos, com o comando e o ambiente de cada um. Se um número não pode
ser reproduzido com o que está escrito aqui, ele não deveria estar aqui.

Os números do host foram medidos em 2026-09-28. Os do guest vêm da Fase 4 e são
de uma sessão anterior; estão marcados como tal e **não** foram remedidos junto
com esta publicação.

## O que estes números são — e o que não são

Estes são números de **inferência em CPU**. Não existe número acelerado aqui,
porque não existe caminho acelerado no alvo: a Fase 9 está bloqueada por falta
de driver de GPU e de NPU no Redox (`docs/ROADMAP.md`, FASE 9). Publicar uma
coluna "acelerado" aqui seria inventar o denominador do comparativo.

O que existe para a Fase 9 é a linha de base: é a coluna "CPU" da tabela abaixo.

## Ambiente

| | Host | Guest |
| --- | --- | --- |
| SO | Linux 7.0.0-31-generic | Redox OS, imagem `x86_64/ai-developer` |
| CPU | Intel Core i5-13420H (12 threads) | QEMU `q35` + KVM, 4 vCPU |
| RAM | 29 GiB | 2048 MiB (caminho `harddrive.img`) |
| Backend | `candle-cpu` (Candle core) | idem, compilado no guest |
| Modelo | TinyLlama-1.1B-Chat-v1.0 Q4_K_M | idem |
| Modelo (bytes) | 668 788 096 (637.8 MiB) | idem |
| GGUF | v3, 201 tensores, 23 KV de metadados, vocab 32k | idem |
| rustc | 1.91.1 | toolchain embarcado na imagem |

O tokenizer é um `tokenizer.json` separado (BPE, 32 000 entradas) e precisa estar
ao lado do `.gguf`. Sem ele o backend Candle é pulado e `ai benchmark` reporta
`skipped` — ver `0cb3bae`, era um bug de resolução de caminho, não falta de
suporte.

## Inferência (`ai run`)

Host, 12 threads, 32 tokens, prompt `"Hello"`:

```
$ ai run models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf --prompt "Hello" --max-tokens 32
,World!

5.Python:

```python
print("Hello,World!")
```

Inthisexample,we're
==> 4.53 tokens/s
```

| Métrica | Host | Guest (Fase 4, remedir) |
| --- | --- | --- |
| Throughput | **4.53 tokens/s** (32 tokens) | ~1.5–1.7 tokens/s (~24 tokens) |
| Load do modelo | 1.87 s | ~24–30 s |
| Razão host/guest | ~2.7x | — |

O tempo de load do guest é ~15x o do host pelo mesmo código em CPU. A
diferença é I/O e ausência de cache: o guest lê os 638 MiB do RedoxFS em disco
virtualizado dentro de uma VM com 2 GiB de RAM, enquanto o host tem a página em
cache. Isso é uma propriedade do ambiente de boot, não do backend.

## Metadados e checksum (`ai benchmark`)

`--iter 200` no host:

```
  GGUF parse:         200/200 ok, 10.8 parse/s
  SHA-256:            211.09 MiB/s (sample 1048576 bytes)
  Candle backend:     candle-cpu on CPU (Candle core) (load 1865 ms)
  Candle throughput:  3.78 tokens/s
```

| Métrica | Host (`--iter 200`) | Guest (Fase 4, `--iter 5`) |
| --- | --- | --- |
| Parse de header GGUF | 200/200 ok, 10.8 parse/s | 5/5 ok |
| SHA-256 | 211.09 MiB/s | ~340 MiB/s |
| Throughput Candle | 3.78 tokens/s | ~1.73 tokens/s |

**Cuidado com estas duas linhas.** Elas não são estáveis e não devem ser lidas
comparando host contra guest:

- `--iter` muda tudo. O parse abre o arquivo do zero a cada iteração, para
  exercitar o caminho de metadados em streaming — daí 10.8 parse/s com 200
  iterações contra um número muito maior com 5. Os 5/5 do guest não são "melhor",
  são menos iterações.
- SHA-256 do guest (~340 MiB/s) acima do host (~211 MiB/s) é ruído de máquina,
  não resultado: a amostra é de 1 MiB lida em memória, com 5 iterações no guest
  e 200 no host, em uma máquina que estava com 19 de 29 GiB em uso.
- O `Candle throughput` do `benchmark` (3.78) difere do `ai run` (4.53) porque
  `--gen-tokens` default é 32 e o tempo de carga entra na janela.

O que **é** sólido: o parse de header GGUF é 100% ok nos dois ambientes, e
inclui o caso que já quebrou antes — metadados de vocabulário acima de 1 MiB são
lidos em streaming, não truncados (regressão corrigida na Fase 4).

## Como reproduzir

```bash
# 1. Modelo e tokenizer no mesmo diretório
mkdir -p models
curl -L -o models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
curl -L -o models/tokenizer.json \
  https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0/resolve/main/tokenizer.json

# 2. CLI
cargo build -p aios-cli --release

# 3. Medir
export AIOS_MODELS_DIR="$PWD/models"
./target/release/ai inspect models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
./target/release/ai benchmark models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf --iter 200
./target/release/ai run models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  --prompt "Hello" --max-tokens 32
```

Passe o modelo **com diretório**. Com um nome solto no cwd o tokenizer é
procurado a partir dele — que é o comportamento certo, mas vale saber.

### No guest

O guest é a imagem `x86_64/ai-developer`, com o modelo em
`/var/lib/ai/models` (ver ADR-017 para as permissões `1777`):

```
$ ai benchmark /var/lib/ai/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
$ ai run tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf --prompt "Hello" --max-tokens 24
```

Rodar dentro do guest é o que faz a Fase 4 valer: prova que o mesmo binário
estático, cross-compilado para `x86_64-unknown-redox`, executa inferência real
dentro do sistema que a plataforma constrói.

## Tamanho do artefato

`ai` é um binário estático único, com a stack Candle inteira dentro
(`candle-core` 0.9.2, `candle-transformers` 0.9.2, `tokenizers` 0.21.4):

| Alvo | Tamanho |
| --- | --- |
| `x86_64-unknown-redox` release | 8.39 MB (estático) |

Esse é o número que importa para a Fase 6: o binário tem que caber e rodar em
um RPi de 1–4 GB, ao lado de um modelo que pode ocupar a mesma ordem de grandeza.
