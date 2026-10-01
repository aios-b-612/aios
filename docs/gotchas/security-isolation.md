# AIOS Security Isolation - Gotchas

## Containment (Redox `contain` scheme)

### Status
The `ContainManager` in `security/src/contain.rs` provides the API surface for
isolating AI models using Redox's `contain` scheme, but the actual kernel-level
containment is **not yet implemented**.

### Why
Redox's `contain` scheme is a kernel-level isolation mechanism that requires:
1. The kernel to expose `/scheme/contain` as a writable filesystem
2. The `contain` recipe to be built into the image
3. The kernel to support the `contain` syscall

### What works
- `ContainManager::with_builtin_profiles()` - loads the `ai-model` and `dev`
  profiles as data. Unlike `new()`, it does **not** require `/scheme/contain`, so
  profile handling is usable and testable on a dev host.
- `register_profile()` / `get_profile()` / `profile_names()` - profile management
- `plan_container(name, profile)` - returns a `ContainerPlan`: the mounts,
  network grants, and resource limits the profile resolves to. Starts nothing.
  This is the surface for reviewing what a policy *claims* to isolate.
- `is_available()` - whether `/scheme/contain` is mounted

### What doesn't work
- `create_container()` - returns `NotImplemented`. It used to return a
  `ContainerInfo` with a fresh UUID and `ContainerStatus::Created`, which read
  as success: a caller could cache that id and believe an isolated process was
  running when none was. With no `contain` scheme to talk to, an error is the
  only honest answer.
- `start_container()` / `stop_container()` - return `NotImplemented`
- `list_containers()` - empty Vec, and `get_container()` returns `None`, for the
  same reason: nothing is ever created.

### Why not fabricate a `ContainerInfo`
A fabricated success is worse than an error here. The failure mode is silent: an
inference pipeline logs "container started", caches an id, and then runs the
model unisolated — while every log line claims isolation was applied. Prefer
`plan_container` when you want to inspect the intended isolation.

### To enable
1. Ensure the `contain` recipe is in the image profile
2. Add `contain` to `recipes/groups/dev-essential` or similar
3. Implement the actual scheme interaction in `create_container()`:
   ```rust
   // Pseudo-code for actual contain scheme interaction
   let mut contain = std::fs::File::open("/scheme/contain")?;
   // Write container config, read container ID, spawn process
   ```
4. Change `create_container` to return the real `ContainerInfo` and drop the
   `NotImplemented` return, then add integration tests with a real Redox image

## AI Permissions

### Status
The decision layer is implemented and tested: `security/src/enforce.rs` plus 20
negative tests in `security/tests/isolation.rs`. Kernel-level enforcement still
depends on the `contain` scheme.

### What works
- `Enforcer` evaluating an `AccessRequest` to a `PolicyDecision` with the
  matched rule id, plus a retained audit log of denials
- Default-deny: an unmatched request falls through to `policy.default_effect`,
  which the shipped templates set to `Deny`
- `PermissionSet` with `ResourceType` and `AccessLevel`
- `SecurityPolicy` with priority-based rules, deny-before-allow on ties
- `validate_deployment()` checks compatibility
- `aios-security` CLI: `authorize`, `check`, `describe`, `contain-profiles`,
  `contain-plan`

```sh
# Denies, exit 1:
aios-security authorize tinyllama filesystem read --scope /etc/shadow
# Allows, exit 0:
aios-security authorize tinyllama filesystem read --scope /var/lib/ai/models/m.gguf
```

### What doesn't work
- Kernel-level enforcement. This crate is the userland *decision* layer; the
  Redox kernel enforces what the policy tells it to, and a policy the kernel
  cannot express is not enforced at all.
- The tests prove a restricted policy denies the accesses it should. They are
  not a proof of isolation in the running system.

### To enable
1. Implement `ContainManager::create_container()` to actually spawn processes
2. Have the kernel consult the policy, or restrict via the `contain` scheme
3. Add integration tests against a real Redox image

## Scope matching holes (fixed — keep these regressions covered)

These were real grant-escalation bugs in `PolicyRule::matches`, both caused by
treating a scope as a string prefix. Both are now covered by tests; the
reasoning matters if the matching code is ever rewritten.

1. **Shared prefix.** `"/var/lib/ai/models_backup"` satisfied
   `starts_with("/var/lib/ai/models")`. Requiring a trailing separator fixes this
   one.
2. **Traversal.** `"/var/lib/ai/models/../../../etc/shadow"` also satisfies that
   prefix check — with *and* without the separator requirement, since the string
   really does start with the granted directory. A prefix check cannot catch it.

So `enforce::scope_contains` normalizes both sides, collapsing `.` and `..`, and
compares path components. Non-filesystem scopes still use a plain prefix, which
is the intended semantic for hosts and device nodes.

Known limit: normalization is lexical and does not resolve symlinks, so a
symlink inside an allowed directory pointing outside it is not caught at this
layer. That needs the caller's real path.

## Two more that were fixed in the same pass

- **Deny could be dead code.** `evaluate` returns the first matching rule, and
  rules were ordered by priority alone, so two rules at equal priority resolved
  by insertion order — a `deny` added after an `allow` never ran. Rules now sort
  by priority descending then effect, with `Deny` first. `normalize()`
  re-asserts the order for policies loaded from disk, so evaluation never
  depends on file order.
- **Unscoped allow silently became a deny.** `to_permission_set()` wrote
  `Some("")` for a rule with no scope, and `PermissionRule::allows` treats an
  empty scope as matching nothing. Every unscoped allow was inverted on the
  runtime path. It now leaves the scope unset.

## Netstack (Redox userspace TCP/IP)

### Status
The Redox `netstack` daemon **aborts on boot** under QEMU aarch64 with
`UNHANDLED EXCEPTION` at `src/header/stdlib/mod.rs:121`. This is an upstream
Redox bug, not an AIOS issue.

### Impact
- `edge status` and `edge models` fail in-guest because they require TCP
- `aios-deploy deploy` cannot transfer models to edge devices
- The `edge-ai` daemon can only serve on loopback (127.0.0.1)

### Workaround
None. This is a kernel/userspace bug in upstream Redox.

### To fix
This requires an upstream fix in the Redox `netstack` crate. The AIOS project
cannot fix this without modifying the Redox kernel, which is out of scope.

## NVMe Driver (aarch64 QEMU `virt`)

### Status
Resolved in-tree (2026-09-29). The NVMe driver hung at namespace
enumeration on aarch64 QEMU `virt` because it relied on interrupt delivery
that never arrived. Fixed by executor poll mode plus DMA fences on the queue
doorbells, in `platform/patches/aarch64/nvmed-aarch64-poll-fence.patch`.

Two corrections to what this section previously claimed:

- The driver is **userspace**, in `base.git/drivers/storage/nvmed`, not in
  the Redox kernel. The fix is a userspace patch, so it does not conflict
  with ADR-001.
- GICv3/ITS was **not** the cause and is **not** a workaround. It was tried as
  one while the hang was still open and never verified either way. Running the
  boot test with `--gic-v3` now makes userspace crash outright: `ls` and `cat`
  die with `UNHANDLED EXCEPTION ... synchronous_exception_at_el0` and a
  guard-page fault, reproducible locally. Without `--gic-v3` the same image
  passes every milestone.

### Impact
None on the default configuration. `ai-edge` aarch64 boots to a login prompt
and an interactive shell, and the headless canary passes.

### The first version of this fix corrupted memory (found and fixed 2026-09-30)

The poll-mode wakeup was originally written as:

```ignore
let waiters: Vec<_> = self.external_event.borrow_mut().drain().collect();
for (_, (task, flags_ptr)) in waiters {
    unsafe { flags_ptr.as_ptr().write(EventFlags::READ) };
    enqueue::<Hw>(task);
}
```

That is a use-after-free. `flags_ptr` points *into* the caller's
`ExternalEventHandle`, and an entry may only be removed by that handle's own
`Drop`. Draining removed every entry out from under the still-live handles, so
`Drop`'s `remove` became a no-op: the map forgot the waiter while the queued
task still held a pointer into it. Once the handle was freed, the queued task
wrote to recycled memory.

The symptom looked nothing like a memory bug. The image booted fine, the canary
passed, and the corruption showed up as **unrelated processes dying
intermittently**. The DMA fences are unrelated to this — they were never wrong;
the poll mode that fixed the hang introduced the corruption, trading a
deterministic hang for silent cross-process memory damage.

The fix snapshots `external_event`'s keys and looks each entry up, leaving
removal to `Drop`. `enqueue` already dedupes on `ready_link`, so re-notifying
every 10ms is harmless.

`security/tests/nvmed_patch.rs` fails on a reintroduced `drain()` so this
cannot come back silently.

**Why the boot canary did not catch it:** `cat` is only invoked after login, and
a single `cat` succeeds most of the time. A canary that checks "did it reach a
login prompt" walks straight past it. The failure rate only shows up when the
same command is repeated inside one boot.

### The `drain()` fix did not eliminate the corruption, and is not the cause

Measuring it properly, with
`platform/scripts/test-stability.sh` (10 repeats of `ls` and `cat` in a
single boot):

| build | `ls` ok | `ls` crashes | `cat` ok | `cat` crashes |
| --- | --- | --- | --- | --- |
| aarch64, with the `drain()` | — | — | 2/6 | 4 |
| aarch64, after the fix (run 1) | 8/10 | 2 | 8/10 | 1 |
| aarch64, after the fix (run 2) | 6/10 | 3 | 8/10 | 2 |
| **x86_64, no patch at all** | **10/10** | **0** | **9/10** | **1** |

A 6-repeat run that came back 6/6 was a small sample, not the fix working: at an
80% success rate, 6/6 happens by chance about 26% of the time. Treat 6/6 as
noise, not as a verdict.

**The control run settles it: x86_64, which never applies this patch, also
crashes** (9/10, one guard-page fault, same signature). So the corruption is
**not** caused by the NVMe patch, the poll mode, or the DMA fences. The `drain()`
UAF was a real bug worth fixing on its own merits, but it is not this bug. Any
apparent improvement in the aarch64 rate after the fix was sampling noise at
this crash rate, not an effect of the fix.

### The fault is a wild/near-null pointer dereference, not a stack overflow

An earlier revision of this document called these stack overflows inside the
`uutils` binaries. That was wrong, and both halves of the claim are now refuted.

**It is not `uutils`.** Binaries from other crates fail at the same rate. Across
seven further runs, six invocations each of seven commands, every one of the ten
exceptions in the log was attributable to one of those commands:

| binary | link | crate | crashes |
| --- | --- | --- | --- |
| `uptime` | dynamic | native coreutils | 4/6 |
| `id` | dynamic | userutils | 3/6 |
| `free` | dynamic | native coreutils | 2/6 |
| `df` | dynamic | native coreutils | 1/6 |
| `cat` | dynamic | `uutils` | 3/10 |
| `wc` | dynamic | `uutils` | 3/8 |
| `basename` | dynamic | `uutils` | 2/8 |
| `find` | dynamic | findutils | 3/8, then 2/12 |
| `which` | dynamic | native coreutils | **0/6** |
| `true` | dynamic | `uutils` | **0/13** |
| `grep` | static | extrautils | 0/10 |
| `calc` | static | extrautils | 0/4 |
| `tar` | static | extrautils | 0/8 |

`ion` has no `true` builtin, so `true` really is a spawned process; and `df`,
`free`, `uptime` and `which` are separate binaries from the *same* crate and the
same link mode. The split is not between crates.

**It is not a stack overflow.** Decoding the register dumps of the `find`
crashes shows data aborts on near-null and wild addresses:

```
ESR_EL1: 0000000092000007   # data abort, lower EL; translation fault L1; READ
FAR_EL1:  0x4                # a second occurrence faults at 0xd
ESR_EL1: 00000000F2000001   # data abort, lower EL; translation fault L0; WRITE
FAR_EL1:  0x103010
ELR_EL1: 00000000002A4E2C    # kernel text, not the faulting process
kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL:
  Not an SVC induced synchronous exception
```

The `GUARD PAGE` lines in the dumps are part of Redox's own stack map, printed
alongside the registers; they are not the faulting address. A stack overflow
faults at a stack address near the top of the mapped region, not at `0x4`. The
kernel then faults in kernel mode while handling the user-space abort. The
`Lacks grant` line that precedes it is expected: page 0 has no grant, so it is a
consequence of the null deref rather than a grant race.

**It is not the tools' work, and not early startup.** Splitting a run at
sentinel markers:

| path | crashes |
| --- | --- |
| `cat --zzz-invalid-flag` (parse, print, exit — never touches a file) | 5/10 |
| `cat /etc/ai-platform` (full work) | 4/10 |
| `true` (control) | 0/5 |

The error path fails as often as the real one, so the fault is early. But
`which` and `true` survive 19 invocations between them while sharing the loader
and the crate with binaries that crash, so it is not `ld.so` startup either.

### Hypotheses already eliminated

Do not re-run these; each was tested and failed.

- **Not `uutils`** — native `find`, `df`, `free`, `uptime` and `id` all crash.
- **Not a stack overflow** — faults are at `0x4`, `0xd` and `0x103010`.
- **Not Rust-specific** — every binary tested is Rust, including all the clean
  ones. `grep`, `tar` and `calc` are statically linked Rust from `extrautils`.
- **Not static versus dynamic alone** — this held at first (0/22 static versus
  10/46 dynamic) but `which` and `true` are dynamically linked and never crash.
  Linkage is at most a contributing factor.
- **Not `clap`** — `find` crashes and does not depend on `clap`; the clean
  `extrautils` binaries do not either.
- **Not the NVMe patch, poll mode or DMA fences** — x86_64 never applies them and
  still crashes.
- **Not a memory-grant race** — `Lacks grant` refers to page 0.

### Where to look next

A subset of dynamically-linked userspace binaries fault on a near-null or wild
pointer roughly a third of the time, and the kernel then faults in kernel mode
while handling the signal. The most promising untested area is relibc's
`ld.so` TLS handling, which is aarch64-specific and visibly unfinished:
`src/ld_so/linker.rs:691-698` carries a `FIMXE` and an unresolved `FIXME` about
placing the TLS block relative to the thread pointer, while
`src/ld_so/tcb.rs` hardcodes the first master's TLS offset to `0` on aarch64
("experimentally determined"). Those two places disagree about where the first
module's TLS lives, which would matter for any `thread_local!` and matches the
`OnceLock` plus `thread_local` TODO in `recipes/core/uutils/recipe.toml`. That
lead is **not confirmed** — see the x86_64 section below for the hard evidence
that now supersedes "the user PC was never obtained".

### x86_64 gives the faulting user-space PC (2026-09-30)

The statement above ("getting it needs a debugger in the guest") is now
**partly obsolete**. The aarch64 dump only prints the kernel's `ELR_EL1`, but the
**x86_64 page-fault dump includes the user-space `RIP`**, and x86_64 never
applies the aarch64 NVMe patch. Reproduced with
`test-stability.sh -a x86_64 -c ai-developer`: `ls` **10/10**, `cat` **9/10**,
1 unhandled exception in `/usr/bin/cat`, 1 guard-page fault in the console.

That `ls` vs `cat` split is the sharpest discriminator found so far. On x86_64
`cat`, `ls` and `true` are **all symlinks to the same `uutils` `coreutils`
binary** (`target/x86_64-unknown-redox/stage/usr/bin/`). One binary, one
loader, one process startup, two outcomes — so the fault is **not** the loader,
not TLS setup at startup, and not the binary. It is triggered by the specific
work `cat` does (open and read a file) and not by `ls` (read a directory).

The captured fault, verbatim from the console:

```
Page fault: 0000000001C88000 WR | US
RIP:   0000000000d85e69
RSP:   00007fffffffe7b0
FSBASE 0000000000f70000
RAX:   0000000001bf0000
RDI:   0000000000098000
RCX:   0000000000000011
RDX:   000000000008e5b8
R11:   67696e6f62696c2f
```

Read together, `RAX + RDI == 0x1bf0000 + 0x98000 == 0x1c88000` — exactly the
faulting address. So this is a **userspace write through `base + 0x98000`**
where the base is `0x1bf0000`, and it is a *write* into a page that is not
mapped writable. `RDI` is `0x98000` = 608 KiB, which looks like a length or a
size rather than a small field offset, and `R11` decodes (little-endian) to the
ASCII bytes `/libonig` — plausibly a fragment of a path being walked. Both
point at a buffer/length computation rather than a null struct field.

Contrast with aarch64, where the same failure showed `ESR_EL1` reads against
`0x4`/`0xd` and a write against `0x103010` — near-null. The x86_64 fault is at
`0x1c88000`, a much less "null" address, so the two may share a root cause
without sharing a fault address.

**Not yet symbolized, and here is exactly why.** The user PC is a PIE runtime
address, and the load base is still unknown, so it cannot yet be mapped to a
file offset. `.text` of the x86_64 `coreutils` spans `0xaa5c0`–`0x7c7232`, which
pins the base only to `0x796eb2 <= base <= 0xb84925` — too wide to pick an
instruction. Guessing `0x400000` is refuted: it puts the PC at `0x985e69`,
which is **past the end of `.text`**. To finish, in order of cost:

1. Rebuild `uutils` for x86_64 with debug info (`[profile.release] strip = false`)
   and re-run; then the load base plus symbols resolve the PC exactly.
2. Or attach gdb via the existing `platform/scripts/debug-qemu.sh`
   (`make gdb-userspace`) and read the base and backtrace live.

The kernel's own stack walk is intact and already gives the call chain as raw
PCs, innermost first, so once the base is known every frame is recoverable:

```
0xdb8138  0xd31a7e  0xd31f78  0xd2e12a
0xd2fc91  0xd09680  0xc2aee5  0xf5e0e4
```

Note this also weakens the relibc-TLS theory as the *sole* explanation: TLS
layout is fixed at load time and shared by all three symlinks, yet `ls` never
faults in this run. A TLS bug can still be the trigger if the faulting path
touches a `thread_local` that `ls` never reaches, but it is no longer the
obvious first suspect.

### `libonig`: the faulting run was actively handling the Oniguruma library

This is the strongest lead so far and it was not on anyone's list, including
the aarch64 work. The x86_64 register dump happens to contain two values that
identify a specific shared library beyond coincidence:

- `RDX = R8 = 0x8e5b8`. `libonig.so.5.5.0`'s first `LOAD` segment has
  `memsz` exactly `0x8e5b8`. No other library on the system matches: `libc.so.6`
  is `0x276354` and `libgcc_s.so.1` is `0x1e764`. A value appearing in *two*
  registers is the shape of a length/size operand (a copy, a fill, or a loop
  bound), so the faulting code was working with the size of libonig's mapped
  image.
- `R11 = 0x67696e6f62696c2f`, which little-endian is the ASCII `/libonig` — the
  tail of the path `/lib/libonig.so.5`, with `R11` pointing at index 4 of it.
  Code holding a pointer into a library's own pathname is walking the loaded
  library list.

Put together with the fault address, the picture is a **write past the end of a
libonig-sized buffer**: the buffer starts at `RAX = 0x1bf0000` and is `0x8e5b8`
long, so it ends at `0x1c7e5b8`; the write went to `RAX + RDI = 0x1c88000`,
which is `0x9a48` beyond that end and into a page that is not mapped writable.

`libonig` is the Oniguruma regex engine (C), pulled into `uutils` by the Rust
`onig` crate:

```
# recipes/core/uutils/source/Cargo.toml
onig = { version = "~6.5.1", default-features = false }
```

It is a `DT_NEEDED` of the `coreutils` binary on **both** architectures
(`libonig.so.5`, alongside `libgcc_s.so.1` and `libc.so.6`). It arrives via the
`expr` crate, and unlike `openssl` there is **no cargo feature to drop it** —
`onig` is a plain workspace dependency.

**What this does and does not explain.** It does not explain everything, and it
would be wrong to write it up as the root cause:

- It does not discriminate `ls` from `cat`. `ls`, `cat`, `true`, `wc` and
  `basename` are all symlinks to the *same* `coreutils` binary, so every one of
  them links libonig — yet `ls` is 10/10. Merely having the library loaded is
  therefore not sufficient; the trigger is a specific code path.
- On aarch64 the crash set also includes native `find`, `df`, `free`, `uptime`
  and `userutils` `id`, which do not go through `expr` and most likely do not
  link libonig at all. So there is more than one failure mode, or a cause that
  libonig merely participates in.

**Why it is still worth acting on.** The single multi-call `coreutils` binary
means `cat` and `ls` carry `expr` and its C regex dependency whether they need
it or not, which maximises the surface exposed to whatever the fault is. Two
concrete, bounded experiments follow from this:

1. Rebuild `uutils` with `expr`'s oniguruma dependency stubbed out, and check
   whether `cat` still faults. If it stops, the dependency is the trigger; if it
   does not, the dependency is ruled out cheaply. This is a build-time change
   only — no upstream patch is involved, so ADR-014 is not engaged.
2. Compare a command that never touches regex against one that does, within the
   same binary, to see whether regex use correlates with the fault.

Experiment 1 is the higher-value one and is the next thing to try.


This is an open, pre-existing Redox bug. It is aarch64's real blocker, and
because it reproduces on x86_64 it also puts that earlier "x86_64 fully
validated" claim under suspicion. Do not claim memory safety on either
architecture. `test-stability.sh` is the gate: 10/10 with zero crashes
before any such claim.

A note on method, because two intermediate runs looked like clean results and
were not: one boot stalled after `dmesg` flooded the serial console, so the
commands queued behind it never ran, and another silently lost the image lock
and never booted. Only runs where sentinel markers confirmed the whole script
executed to the end are counted in the table above. Check that the log actually
grew before trusting a "no crashes" result.

### Known limitation
`--gic-v3` is retained in `test.sh` as an option, but the aarch64 CI job no
longer uses it, because under GICv3/ITS this image cannot reach the milestones
it is meant to verify.

### `virtio-netd` cannot start on aarch64 (separate, unrelated)
`virtio-netd` aborts on every boot, before the NVMe fix is even relevant:

```
panicked at drivers/pcid/src/driver_interface/irq_helpers.rs:320:
not implemented: virtio: MSI-X is not implemented on this architecture
```

This is a distinct pre-existing gap — aarch64 lacks MSI-X support in Redox's
PCID layer, so the emulated e1000/virtio NIC has no way to deliver interrupts.
It is *not* the memory corruption above, and it is what likely produced the
`netstack` failures previously blamed on NVMe. Networking in-guest is
consequently untested; see the ROADMAP TCP gap.

### To fix GICv3/ITS userspace crashes
Not addressed. Diagnosing why coreutils faults under GICv3/ITS is upstream
work on the Redox aarch64 userspace; per ADR-014 nothing is sent upstream, so
this is recorded and left alone.