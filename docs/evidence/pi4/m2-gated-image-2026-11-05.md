# M2 gated — imagem pronta, ainda não no cartão (2026-11-05)

Login M1 confirmado no Pi. Próximo passo é `network.genet` **sem** substituir o binário default.

## Segurança
- Código: `NetworkScheme` só com `--features network-scheme`.
- Unit no cartão actual e na imagem nova: `oneshot_async` (init não espera o driver).
- `pi4-regression-guard` passa no fonte default.
- Binário default recompilado (`fedef096…`) **não** foi gravado. O Pi continua com `96ceeaa6…`.

## Imagem de teste
- `/tmp/aios-edge-pi4-sd-m2-gated.img` md5 `e2693fa93e5622a1290e21dd99237758`
- genetd feature md5 `a45bb0e9f1998a38a478cf96d30a8ad4`
- nologdump (NOP+RET) mantido
- Base: full flash M1 estável

Gravação quando o cartão estiver no leitor USB (`/dev/sda` removível, `14cd:1212`).
