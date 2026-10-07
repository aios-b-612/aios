# Fork do ion no aarch64 — diagnóstico FECHADO: a corrupção vem da entrega de sinais

Data do reprodutor inicial: 2026-09-27. Resolução da pergunta aberta: 2026-10-06.
Kernel de trabalho: [Redox](https://redox-os.org/) `kernel` @ `bbb5d49f` (“Move non-p2 frame allocation logic into the buddy allocator”).
Imagem: `/tmp/opencode/aarch64-work/work.img`, [QEMU](https://www.qemu.org/) `virt`, backend NVMe, `-smp 1`, TCG.

## Pergunta aberta da sessão anterior

> A função de `SYS_YIELD` devolve 0. O filho, no `b.cs` do `verify()`, observa um `W0` na gama de errno. O 0 da função não é o `X0` com que o filho retoma. O sítio a medir, numa só iteração, é o valor escrito no trap frame desse yield contra o `X0` no `brk`.

## Resposta medida

Instrumentação: ring buffer de 1024 entradas no kernel (sem locks, `write_volatile`),
com três tipos de evento:

- `Y`: todo o `SYS_YIELD` — valor escrito no trap frame e valor relido
- `S`: toda a entrega de sinal — o `x0`/`elr` capturados do frame antes de o redirect
- `B`: a excepção fatal — o `x0`/`elr`/`esr`/`far` no momento do crash

Resultado (boot `stab-01.log`, 12× `ls` + `cat`, 3 FATALs — todos com o mesmo padrão):

```text
DIAG 59254 Y ctx=…13e0 a=0x9e b=0x0 c=0x0 d=0xbd8e30   <- yield escreveu ret=0
DIAG 59255 S ctx=…13e0 a=0xffff…ffff b=0xbd8e30      <- entrega apanha x0=-1 (o ARG!)
DIAG 59256 Y ctx=…13e0 a=0x9e b=0x0 c=0x0 d=0xb54ee0 <- yield DENTRO do handler de sinal
DIAG 59257 B ctx=…13e0 a=0xffff…ffff b=0xbd9920      <- brk com X0=-1 (ESR=0xf2000001)
```

**O yield escreve 0 e o `brk` mais tarde vê -1: a pergunta está respondida — o valor -1 não vem do syscall. É introduzido pelo protocolo de sinais.**

## A cadeia causal

1. O filho (fork/exec do ion, p.ex. `cat`) faz o `SYS_YIELD` inicial de `relibc_start_v1` — ou
   qualquer syscall — e pode ficar **suspenso dentro do syscall** (o próprio `sched_yield`
   troca de contexto; um `mmap` demorado idem). Nesse instante, o trap frame tem
   `x0 = argumento` do syscall (o `verify` chama-se com todos os args a `-1`: `syscall5(YIELD, -1,…)`),
   **não o valor de retorno** — a linha `stack.scratch.x0 = ret` ainda não correu.

2. Quando o contexto é re-escolhido por um tick, o hook corre
   `context/signal.rs::signal_handler`, que — se houver sinal pendente — captura do frame
   o `instr_pointer` e o `sig_archdep_reg()` (= `X0`) para os campos **únicos** por thread
   `thread_ctl.saved_ip` / `thread_ctl.saved_archdep_reg`, e redireciona o `elr` do frame
   para o handler de sinal userspace (`0xb54ee0` nos logs — o stub da relibc).

3. O stub userspace corre e, no fim, restaura `x0 = saved_archdep_reg` e salta para
   `saved_ip` — devolvendo ao ponto interrompido o valor **capturado quando o syscall
   estava a meio**. No caso: `-1`. Retoma em `cmn w0, #0x84` a seguir ao `svc`, e o
   `verify()` vê errno → `brk #1` → `FATAL: Not an SVC induced synchronous exception`.

4. Agravante: o stub limpa `INHIBIT_DELIVERY` cedo (todas as entregas nos logs têm
   `control_flags=0` à entrada), por isso uma **segunda entrega reentrante sobrescreve
   o slot único** `saved_ip`/`saved_archdep_reg` do primeiro. Nos logs há 5 entregas
   encadeadas para o mesmo contexto; cada uma destrói o par guardado da anterior.
   O slot único não é reentrante **por construção**.

## O terceiro FATAL une as duas archs

O FATAL #3 desta rodada é `ty=100100` (data abort), não `brk`:

```text
DIAG 59281 S … a=0x1985000 b=0xbf0dd8            <- entrega captura x0=0x1985000 a meio
DIAG 59282 B … a=0x1985000 c=0x92000047 d=0x19b5000 <- data abort WRITE em 0x19b5000
```

`FAR = x0 + 0x20000` — o userspace recebeu `x0` restaurado pelo sigreturn e usou-o como
base de escrita, passando 0x20000 adiante e caindo numa página não mapeada. É a mesma
assinatura do crash de x86_64 no `relibc/ld_so/dso.rs::mmap_and_copy`
(write-past-end do mapping da DSO — ver `docs/gotchas/security-isolation.md`):
**o ponteiro que o loader usa sai corrompido de um syscall interrompido por entrega de
sinal.** A corrupção de `cat`/`find`/`df`/`expr` e o `Not an SVC` do ion são o MESMO
bug. As taxas de falha diferentes por binário (que o documento anterior não explicava)
seguem simplesmente da duração das syscalls de `mmap` que cada execução faz — quanto
mais tempo dentro, mais provável apanhar um tick+entrega a meio.

## Por que só filho de pai multi-threaded (reprodutor original)

O reprodutor original pedia um pai multi-threaded porque a probabilidade de haver
sinal pendente para o processo recém-nascido, na janela do primeiro syscall, é muito
maior quando o pai corre várias threads (o ion interativo mantém state/sinais
relacionados com o terminal e job control). Mas o bug não precisa do ion: qualquer
processo dinâmico com sinais pendentes a entrar num syscall longo serve.

## O que fica como defeito do protocolo de sinais (upstream)

No kernel `src/context/signal.rs`:

- `signal_handler` corre no hook pós-switch e captura `ip`/`x0` do frame **mesmo quando
  o contexto está suspenso dentro de uma syscall** (devia adiar; o contexto tem já a
  noção de `inside_syscall`).
- `saved_ip`/`saved_archdep_reg` são um slot único por thread, não uma pilha de
  sigframes em userspace ao estilo POSIX/Linux — qualquer entrega reentrante é
  destrutiva.

E na relibc o stub de handler liberta `INHIBIT_DELIVERY` cedo demais em relação à
leitura dos campos guardados. (A dupla razão de a janela ser grande.)

## Ficheiros desta medição

- Kernel instrumentado (não commitado; para diagnóstico): clone de
  `bbb5d49f` em `/tmp/opencode/ksrc`, `src/diag.rs` novo + 1 hook em
  `src/arch/aarch64/interrupt/exception.rs` (path do SVC e ramo FATAL) +
  1 hook em `src/context/signal.rs`. `/tmp/opencode` é volátil: re-clonar se preciso.
- Boot reprodutor: `/tmp/opencode/aarch64-work/run-stability.sh`
  (12× `ls /var/lib/ai` + `cat /etc/ai-platform`, `-smp 1`, snapshot).
- Log com os 3 FATALs: `/tmp/opencode/aarch64-work/stab-01.log`.
