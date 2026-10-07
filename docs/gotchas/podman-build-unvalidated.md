# O build podman é detectado automaticamente, mas não é validado

`platform/scripts/build.sh` usa podman quando encontra o binário na máquina.
Nenhuma imagem AIOS foi construída nesse caminho. As imagens validadas
(`x86_64/ai-developer`, e o build aarch64) vêm do build **nativo**
(`PODMAN_BUILD=0`), que é o que roda em qualquer máquina sem podman.

## Por que o podman falha hoje

Os profiles em `platform/config/` incluem o config de console do upstream:

```toml
include = ["../../../redox-os/config/server.toml"]
```

O `repo` resolve `include` relativo ao diretório do próprio config. Em modo
podman, o passo de sysroot roda dentro de um container que monta **apenas** a
árvore upstream, em `/mnt/redox`. O config acaba staged dentro dessa árvore, e
`../../../` sai da montagem:

```
failed to read '/mnt/redox/aios-config/../../../redox-os/config/server.toml':
No such file or directory (os error 2)
```

Esse caminho existe no host, e é exatamente por isso que a mensagem é confusa:
o build falha procurando um arquivo que está lá.

No modo nativo o config é lido direto do host, o include resolve, e funciona.

## O que fazer

Passar `-n` para forçar o build nativo:

```sh
platform/scripts/build.sh -a x86_64 -c ai-developer -n
```

É o que os jobs de boot do CI fazem, e o que `build.sh` avisa ao detectar
podman.

## Para tornar o podman viável

Não é uma flag, é um trabalho: o include relativo teria de deixar de existir.
As saídas razoáveis são mover os profiles para dentro da árvore upstream, no
layout que o Redox já espera (`config/$(ARCH)/$(CONFIG_NAME).toml`), ou
reescrever o include ao gerar o config no container. Nenhuma das duas foi
feita, e nenhuma deve ser feita sem decidir antes onde os profiles são a fonte
da verdade.
