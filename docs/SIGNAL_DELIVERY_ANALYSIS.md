# Entrega de sinais no kernel Redox — análise, fix validado e o defeito que sobra

Data: 2026-10-08. Continuação de `docs/FORK_ION_DIAG.md` (que fechou a causa como
"corrupção na entrega de sinais"). Este documento registra a tentativa de fix, o
que ela resolveu, o que ela não resolveu, e o fix que sobra para o upstream.

## O fix tentado — e o que mudou

Hipótese do FORK_ION_DIAG: o `signal_handler` captura `ip`/`x0` do trap frame
mesmo quando o contexto está suspenso dentro de um syscall — e nessa janela o
`x0` do frame ainda guarda o **argumento** do syscall (o retorno só é escrito
no frame na saída do handler arch). O sigreturn devolve esse argumento como se
fosse o retorno: `verify()` do relibc vê `x0=-1` → `brk #1` → FATAL.

Fix aplicado no kernel (`bbb5d49f`, instrumentado local):

1. `src/context/signal.rs::signal_handler`: se o contexto está com
   `inside_syscall == true`, adiar a entrega (a entrega continua pendente e
   ocorre no próximo tick/switch, quando o frame já contém o retorno).

2. Estender a janela de `inside_syscall` até o frame estar pronto: remover o
   `set(false)` de `src/syscall/mod.rs` e setar `inside_syscall = false` nos
   handlers de arch DEPOIS de escrever o retorno no trap frame:
   - `src/arch/aarch64/interrupt/exception.rs` (após `stack.scratch.x0 = ret`)
   - `src/arch/x86_64/interrupt/syscall.rs` (após `scratch.rax = ret`)
   - `src/arch/x86/interrupt/syscall.rs` (após `scratch.eax = ret`)
   - `src/arch/riscv64/interrupt/exception.rs` (após `r.x10 = ret`)

Diff aplicado:

```text
# src/context/signal.rs (na verificação de INHIBIT_DELIVERY)
+    if PercpuBlock::current().inside_syscall.get() {
+        trace!("inside syscall, deferring delivery");
+        return;
+    }

# src/syscall/mod.rs
-    percpu.inside_syscall.set(false);

# src/arch/aarch64/interrupt/exception.rs, no ramo SVC
     stack.scratch.x0 = ret;
+    crate::percpu::PercpuBlock::current().inside_syscall.set(false);

# (idem nos demais arches com o registro equivalente)
```

## Medição antes/depois

Reprodutor: `/tmp/opencode/aarch64-work/run-stability.sh` (12× `ls /var/lib/ai` +
`cat /etc/ai-platform`, QEMU `virt`, `-smp 1`, TCG), kernel buidado localmente com
o fix (`/tmp/opencode/ksrc/build/aarch64/kernel` → injetado no `work.img`).

| Run | Crashes (UNHANDLED EXCEPTION) | Nota |
| --- | --- | --- |
| Baseline (stab-01.log) | 3 FATALs/12 runs (padrão `brk #1`) | x0=-1 documentado |
| Com o fix (stab-fix01.log) | 2 crashes/12 runs | padrão mudou |

O padrão do `brk #1` com `x0=-1` NÃO reaparece. O fix funciona para a janela
syscall. Os 2 crashes restantes têm assinatura diferente: `ESR=0x92000007` (data
abort, write, L3 translation) com `FAR_EL1 = 0xb` / `0xc` (nulos próximos de
zero) e `x0=0`.

## O defeito que sobra (slot único reentrante)

Os logs mostram o padrão repetitivo: `S → S → S` no mesmo contexto, separadas por
`Y` (o yield do stub do handler de sinal). Cada entrega sobrescreve
`thread_ctl.saved_ip` / `thread_ctl.saved_archdep_reg` — um slot único por
thread, por construção não-reentrante. Se duas entregas se seguem antes do stub
terminar (a relibc limpa `INHIBIT_DELIVERY` antes de restaurar/saltar), a
sigreturn da primeira restaura o par da segunda — o userspace volta ao ponto
errado com o `x0` errado, e o uso subsequente como ponteiro dá fault de escrita
em `0xb`/`0xc`.

## O fix que sobra (upstream: `redox-os/kernel`)

Duas opções, em ordem de preferência upstream:

1. **Sigframe por entrega em userspace** (o caminho POSIX): o kernel empilha um
   sigframe no stack do processo por entrega, em vez de salvar em slots únicos.
   É o formato que relibc já meio-implementa (o stub assume que pode restaurar
   ip/x0 depois do handler). Invadir esse design é o fix "de verdade".

2. **Adiar também a reentrega**: manter `INHIBIT_DELIVERY` setado até o
   `sigreturn` explicitamente limpar (hoje o stub limpa antes de restaurar).
   Menor, mais fácil de provar correto, mas não resolve casos onde a ordem de
   entrega importa.

A PR upstream fica como follow-up de projeto. Não é para ser incluída como patch
no AIOS (ADR-001: kernel não é modificado).

## Ficheiros da medição

- Kernel instrumentado + fix: `/tmp/opencode/ksrc/` (clone de `bbb5d49f`,
  `src/diag.rs` + hooks em `exception.rs`, `signal.rs`, `syscall/mod.rs`).
- Log com o fix: `/tmp/opencode/aarch64-work/stab-fix02.log`.
- Kernel buildado: `/tmp/opencode/ksrc/build/aarch64/kernel`.
- work.img atualizado com o kernel com fix (baseline: `kernel.img-baseline-20261008`).

## Estado no repo AIOS

- O loader fix (`platform/patches/*/relibc-mmap_and_copy-fix.patch`, PR #22)
  fecha a `write-past-end` de `ld.so::mmap_and_copy` quando `bounds.0 ≠ 0`.
  Medido: o crash de `cat`/`ls` NÃO é esse (cat é PIE com `p_vaddr=0`, bounds.0=0).
- O crash dominante observado em aarch64 é a entrega de sinais — follow-up upstream.
