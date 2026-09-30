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
UAF was a real bug worth fixing on its own merits, but it is not this bug, and
fixing it roughly halved aarch64's crash rate for reasons not yet understood.

The fault is a data abort on the process's own stack pointer, on both
architectures:

```
# aarch64
ESR_EL1: 0000000092000007     # data abort from a lower EL
SP_EL0:  00007FFFFFFFC990
  00007fffffffc990: GUARD PAGE
UNHANDLED EXCEPTION ... NAME /usr/bin/ls

# x86_64
FP 00007fffffffe7b0: PC 0000000000db8138
kernel::arch::x86_shared::interrupt::exception::page::inner
  00007fffffffe7b0: GUARD PAGE
UNHANDLED EXCEPTION ... NAME /usr/bin/cat
```

The faulting address is always the top of the process's own stack, so these are
**stack overflows inside the `uutils` binaries**, not wild pointers from another
process. The binaries come from `recipes/core/uutils/recipe.toml` (`coreutils`
0.11.0), whose recipe already carries a standing TODO about a Redox-specific
locale init bug involving `OnceLock` plus `thread_local`. Recursion depth or
thread stacks in those binaries, not NVMe, is where to look next.

This is an open, pre-existing Redox bug. It is aarch64's real blocker, and
because it reproduces on x86_64 it also puts that earlier "x86_64 fully
validated" claim under suspicion. Do not claim memory safety on either
architecture. `test-stability.sh` is the gate: 10/10 with zero crashes
before any such claim.

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