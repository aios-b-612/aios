# Fork do ion no aarch64 — diagnóstico, sem correção

Data: 2026-09-27.
Kernel de trabalho: [Redox](https://redox-os.org/) `kernel` @ `bbb5d49f` (“Move non-p2 frame allocation logic into the buddy allocator”).
Imagem: `/tmp/opencode/aarch64-work/work.img`, [QEMU](https://www.qemu.org/) `virt`, backend NVMe.

Não há correção. O que fica é o reprodutor, o que os testes eliminaram, e a pergunta que ainda está aberta.

## Reprodução

A sonda que substituiu `/usr/bin/login` (cópia em `/tmp/opencode/login.probe`) corre [ion](https://gitlab.redox-os.org/redox-os/ion) sem teclado:

- Fase A — `ion` só com builtins (`echo` / `exit`): zero crashes.
- Fase B — `ion` a fazer fork/exec de `cat /etc/hostname`: crash em todos os boots.

O disparador é um filho criado por um pai multi-threaded. Fork do `bash` com o `ion` limitado a builtins não chega ao FATAL.

## O que o FATAL é

Mensagem do kernel:

```text
FATAL: Not an SVC induced synchronous exception (ty=111100)
ESR_EL1 = 0xF2000001
ELR_EL1 = <libc_base> + 0x139A9C
```

`ty` é a classe da excepção, `(ESR >> 26) & 0x3f`. `0xF2000001` tem `EC=0x3C`, a classe `brk` do AArch64, imediato 1. O `ELR` é o `brk #1` dentro de `relibc_start_v1`, no [relibc](https://gitlab.redox-os.org/redox-os/relibc):

```text
138f54: mov  x0, #-1
138f5c: svc  #0          ; SYS_YIELD, X8 = 0x9E
138f60: cmn  w0, #0x84
138f64: b.cs 139a9c      ; aborta se W0 está em [-132, -1]
```

Esse `brk` é o aborto do `verify()`, que chama `syscall5(SYS_YIELD, -1, -1, -1, -1, -1)`. Três controlos no binário da libc da imagem fecharam o caminho:

- `b.cs` trocado por salto incondicional: o primeiro yield devolve `X0=0` e o aborto acontece na primeira chamada.
- Imagem intacta, mesma sequência de teclas: crashes com `X0=-1`, `X8=0x9E`.
- `b.cs` trocado por `nop`, mesma sequência: zero crashes, duas vezes.

O `verify()` comporta-se como foi escrito. O `brk` anuncia o valor que o filho observa; não é a causa.

`pf_inner` em `src/arch/aarch64/interrupt/exception.rs` compara essa classe. `0b111100` não é data abort (`0b100100` / `0b100101`) nem instruction abort. O `error!` “Not an SVC” é o ramo por omissão.

## Porque o loop de page fault apareceu

Encaminhar essa classe para `page_fault_handler` faz o handler devolver `Ok` e o `ERET` regressar ao mesmo `brk #1`. A instrução não é um acesso à memória, o `ELR` não avança, e a excepção repete. Vinte recuperações iguais são esse ciclo.

`FAR_EL1` só é actualizado em abort de dados ou de instrução. No `brk`, `FAR=0x7fffffffc340` (página de stack, com `GRANT PAGE` em `0x7fffffffbfe0`) é o fault anterior. O PTE correcto depois de `map_phys`, e o fault a repetir com `tlbi vmalle1`, são o resultado de tratar um `brk` como tradução.

A última imagem instrumentada piorou o arranque: depois de `[DIAGAFTER]` o kernel morre em EL1 com `ESR_EL1=0x96000005` (data abort no mesmo nível, `FAR_EL1=0xbcbd4000`). Log: `/tmp/opencode/aarch64-work/bootdiag-nvme.log`.

`fsc = iss & 0x3F` em data abort AArch64 é o `DFSC` (`ISS[5:0]`); o bit de escrita já é o `ISS[6]`. Deslocar esse campo partiria os faults reais. Não é uma correcção à parte.

## O que os testes tiraram de cena

- Writeback byte a byte (`strb` → `str x0, [x19]`): a contagem de `Not an SVC` manteve-se. A largura desse store não é o bug.
- Os 610335 `SYS_YIELD` registados no kernel devolveram `ret=0`. Isso mede o valor da função. No `brk`, `X0..X4=-1`, e o `b.cs` só é tomado com `W0` em `[-132, -1]`.
- `7a9f0279`, `ec70cf9b` (“page fault handling”) e `b68957d` reproduzem o mesmo.
- TLB stale: o PTE fica com `write: true` num frame novo, e o `tlbi vmalle1` forçado não impede a repetição — porque a excepção repetida é o `brk`, não uma tradução.
- A flag de kernel em `tpidr_el1+368` como selector do epílogo de errno foi retratada. Não é a causa.

## Pergunta aberta

A função de `SYS_YIELD` devolve 0. O filho, no `b.cs` do `verify()`, observa um `W0` na gama de errno. O 0 da função não é o `X0` com que o filho retoma. O sítio a medir, numa só iteração, é o valor escrito no trap frame desse yield contra o `X0` no `brk`.

## Estado deixado em disco

- Fonte em `/tmp/opencode/ksrc`: `bbb5d49f` limpo. Os três ficheiros de diagnóstico (`exception.rs`, `context/memory.rs`, `memory/mod.rs`) foram revertidos. Nada disto foi commitado.
- `work.img`: `/usr/bin/login` reposto a partir de `/tmp/opencode/login.orig` (ELF, mode 755, uid 0). `/usr/lib/boot/kernel` reposto a partir de `/tmp/opencode/kernel.img-orig`, sem as strings `DIAG*`.
- O binário instrumentado saiu de `ksrc/build/aarch64/` para `/tmp/opencode/diag-kernels/`, para não ser reinjectado.
- A sonda ficou só em `/tmp/opencode/login.probe`.
- Boot de verificação (`-snapshot`, log `/tmp/opencode/aarch64-work/bootdiag-restore.log`): chega a `redox login:` sem `DIAGAFTER` / `DIAGPF` e sem excepção síncrona em EL1.
- Os `bootdiag-*.log` de `/tmp/opencode/` são, na maior parte, stubs de uma linha a apontar para `aarch64-work/bootdiag-nvme.log`, que o script de boot reescreve. O registo duradouro desta sessão é este ficheiro e `/tmp/opencode/FORK-YIELD-FINDING.md` (a secção da flag `+368` está obsoleta).
