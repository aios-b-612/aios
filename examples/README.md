# Exemplos

Scripts executáveis que usam as CLIs reais deste repositório. Cada um roda
sozinho, não depende de rede, e diz no fim o queDEU errado se algo deu errado.

```bash
chmod +x examples/*.sh
./examples/01-ai-model-lifecycle.sh
```

| Script | Precisa de modelo real? | Mostra |
| --- | --- | --- |
| `01-ai-model-lifecycle.sh` | não (24 bytes sintéticos) | `ai inspect`/`verify`/`install`/`list`/`info`/`remove` |
| `02-ai-inference.sh` | **sim** (638 MiB) | `ai run`, `ai benchmark`, `ai task` |
| `03-edge-daemon.sh` | não | `edge serve`/`status`/`models`/`run`, o daemon HTTP |
| `04-security-policy.sh` | não | `aios-security` create/check/authorize/describe |

Todos usam um diretório temporário próprio e **não tocam** em
`/var/lib/ai`, nem no seu `$HOME`.

## As duas variáveis de ambiente que quase todo mundo esquece

Fora do guest, o Redox espera que `/var/lib/ai` exista. No seu notebook ele
existe como root, então `ai install` falha com `Permission denied` — e a
mensagem não ajuda. Aponte as duas variáveis:

```bash
export AIOS_MODELS_DIR="$PWD/.aios/models"
export AIOS_REGISTRY="$PWD/.aios/registry.tsv"
```

Dentro do Redox não é preciso: lá `/var/lib/ai/models` e
`/var/lib/ai/registry.tsv` são os caminhos reais (ADR-017 deixa o diretório de
modelos com escrita liberada, `1777`).

## `ai run` e o tokenizer

O `.gguf` e o `tokenizer.json` precisam estar **no mesmo diretório**, e o modelo
tem que ser passado com o diretório junto:

```bash
./target/release/ai run models/tinyllama-.../tinyllama-...gguf --prompt "Hello"
```

Sem o tokenizer o backend Candle é pulado e a saída diz `skipped`, que parece
falta de suporte em vez de arquivo faltando. Foi um bug de resolução de caminho
(corrigido em `0cb3bae`), mas a exigência do tokenizer continua sendo real: um
`.gguf` sozinho não é executável.

## `edge serve` escuta em `0.0.0.0` por padrão

Se você só quer ver o status, use a porta padrão e deixe o daemon em loopback:

```bash
./target/release/edge serve --host 127.0.0.1 --port 8989
```

O `--host`/`--port` são do **daemon**. Os subcomandos de cliente (`status`,
`models`, `run`) não aceitam `--port`: eles speak sempre com `127.0.0.1:8989`
e hard-coded. Se o daemon estiver em outra porta, aponte o cliente por
`EDGE_BASE_URL`:

```bash
export EDGE_BASE_URL="127.0.0.1:8990"
```

Não deixe o daemon em `0.0.0.0` numa máquina de desenvolvimento: ele expõe um
endpoint HTTP sem autenticação, para a rede toda.
