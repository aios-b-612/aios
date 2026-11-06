# Boot ainda parou depois do offset GPT (2026-11-06)

O EFI com a leitura da GPT (135680 bytes, `055499bd…`) estava no cartão. O logdump ficou a zero e a partição RedoxFS, comparada com a imagem estável, não tinha nenhum bloco diferente. O sistema não montou o root. O U-Boot continua a ser o único sinal de que o firmware correu.

## O que este EFI muda

- A tabela GPT é lida um bloco de cada vez. Um `ReadBlocks` de 16 KiB pode falhar no firmware do Pi e o código antigo caía no offset de 2 MiB.
- `SetMode` do GOP não é chamado. O modo que o firmware já programou segue para o kernel.
- A última etapa é gravada em `\aios-stage.txt` na ESP (32 bytes, sobrescrito).

EFI no cartão: 136704 bytes, md5 `46b2fa17a07dab4ee45827cec39719f1`. Não havia `aios-stage.txt` no momento da cópia. Fonte: [redox#8](https://github.com/aios-b-612/redox/pull/8).

O driver GENET não mudou. Continua o binário M1, sem `network.genet`.

## Leitura se o ecrã parar outra vez

O ficheiro `\aios-stage.txt` na partição EFI fica com a última etapa:

| Texto | Onde parou |
| --- | --- |
| `boot-start` | O EFI novo arrancou e ainda não abriu o RedoxFS |
| `fs-open` | Entrou na procura do RedoxFS |
| `gpt-header` | A ler o cabeçalho GPT (LBA 1) |
| `gpt-scan` | A ler as entradas, um bloco de cada vez |
| `gpt-ok` | Encontrou a partição REDOX |
| `gpt-header-fail` / `gpt-read-fail` / `gpt-missing` | Caiu no offset de 2 MiB |
| `fs-ok` | RedoxFS aberto |
| `pre-video` / `post-video` | Modo de ecrã, sem `SetMode` |
| `pre-paging` / `post-paging` | Tabelas de página |

Ausência do ficheiro: este EFI não chegou a correr.
