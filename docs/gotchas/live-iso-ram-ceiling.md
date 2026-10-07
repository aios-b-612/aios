# A ISO live tem teto de RAM: o filesystem inteiro é copiado para a memória

A Fase 10 pede uma "ISO Developer OS regenerável". A ISO existe e boota, mas
o tamanho do filesystem do perfil não pode passar de ~3 GiB — e o motivo não é
escolha nossa: é o bootloader do upstream.

## O que acontece no live

Um CD-ROM é somente-leitura, então a sessão live não pode trabalhar sobre a
imagem. O bootloader do upstream copia o RedoxFS **inteiro** para a RAM antes de
passar o controle pro kernel:

```rust
// bootloader/src/main.rs
let size = fs.header.size();
print!("live: 0/{} MiB", size / MIBI as u64);
let ptr = os.alloc_zeroed_page_aligned(size as usize);
```

E a alocação é limitada por endereço, não por "quanto tiver livre":

```rust
// bootloader/src/os/uefi/mod.rs
let mut ptr = 0x2_0000_0000;   // 8 GiB
AllocatePages(AllocateMaxAddress, EfiRuntimeServicesData, pages, &mut ptr)
```

Ou seja: **um bloco contíguo de RSS, inteiro, abaixo de 8 GiB**. A RAM acima
de 8 GiB não ajuda — a alocação é rejeitada.

## Por que ~3 GiB e não ~7 GiB

A janela abaixo de 8 GiB não é toda utilizável. O QEMU (machine `q35`) reserva
um buraco MMIO de baixa memória, e o firmware UEFI fragmenta o que sobra em
vários blocos disjuntos. `AllocateMaxAddress` só retorna **um** bloco
contíguo, então o teto é o maior bloco livre, não o total.

Medido neste host com `-m 8192`:

| `filesystem_size` | RedoxFS | Resultado |
| --- | --- | --- |
| 1024 | ~1017 MiB | build OK (conteúdo cabe, mas folga zero) |
| 3072 | 3069 MiB | **boota** até `redox login:` |
| 3584 | 3581 MiB | `SETUP PANIC ... "out of resources"` |
| 6144 | 6141 MiB | `SETUP PANIC ... "out of resources"` |
| 8192 | 8189 MiB | `SETUP PANIC ... "out of resources"` |

A falha aparece em `0/N MiB`, antes de copiar um único byte, que é a assinatura
de que a alocação falhou e não de um problema de leitura:

```
live: 0/3581 MiBSETUP PANIC: panicked at src/os/uefi/mod.rs:56:10:
called `Result::unwrap()` on an `Err` value: Status(0x8000000000000009) "out of resources"
```

## A pegadinha: `harddrive.img` continua funcionando

O `harddrive.img` **não** faz essa cópia — o RedoxFS fica no disco e o kernel
mapeia direto. Ele sobe com 8192 MiB sem reclamar. Como o `test.sh` prefere a
ISO quando ela existe, dá para você aumentar o perfil, ver o `harddrive` bootar
normal, e só descobrir que a ISO morreu. Um tamanho de filesystem que é
perfeito para a imagem de disco é inválido para a ISO.

## O que fizemos

`filesystem_size = 3072` no perfil `x86_64/ai-developer`: o conteúdo instalado
ocupa ~0.9 GiB (932 MiB de blocos alocados), então sobram ~2 GiB de rascunho
para `cargo`/`rustc` dentro do guest, e a ISO sobe.

Para confirmar que 3072 é folgado e não sorte, dá para forçar overflow: com
`FILESYSTEM_SIZE=512` o installer falha de verdade —

```
installer: failed to install: pkgar error: No space left on device (os error 28)
```

— então o 512 era pequeno demais de verdade, e o 1024 já passava. O conteúdo
real está entre 512 MiB e 1024 MiB.

## Consequências práticas

- **Para subir a ISO, o guest precisa de RAM.** `test.sh` usa `-m 8192` no
  caminho de ISO. Com os 2048 MiB do caminho de disco, a cópia do FS não cabe
  e o boot morre do mesmo jeito.
- **O runner do GitHub não aguenta.** `ubuntu-latest` tem ~7 GB; um QEMU com
  `-m 8192` não é viável lá. Por isso o job de boot do CI continua no
  `harddrive.img`, e a ISO é validada localmente.
- **A ISO é UEFI-only.** Ela traz `bootloader-live.efi` e nenhum
  `bootloader-live.bios` utilizável, então SeaBIOS não sobe. `test.sh` monta
  OVMF via pflash só nesse caminho. Sem isso o QEMU morre em silêncio, sem uma
  linha de log.
- Se algum dia o upstream deixar a cópia ser paginada (ou alocar acima de 8 GiB),
  o teto de 3 GiB deixa de valer e o perfil pode voltar a 8192.
