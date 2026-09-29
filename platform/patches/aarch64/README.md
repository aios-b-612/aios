# aarch64 platform patches

Patches applied on top of the pinned upstream Redox tree. The upstream tree in
`redox-os/` stays read-only (see ADR-001); everything that has to deviate lives
here so the deviation is visible and reviewable.

## `nvmed-aarch64-poll-fence.patch`

| | |
|---|---|
| Target repo | `https://gitlab.redox-os.org/redox-os/base.git` |
| Target path | `drivers/executor/`, `drivers/storage/nvmed/` |
| Verified against | `8fdf4e4bf9a61b240aaf49e23a6541682cf30d6c` (`main`, 2026-09-24) |
| Size | 3 files, +119 / -5 |
| Status | applies cleanly; compiles for `aarch64-unknown-redox` with no new warnings |

### Why the fix is needed

On `aarch64` QEMU `virt` the NVMe controller's legacy INTx interrupt is never
delivered to the guest, so `nvmed` never reaps completions and the boot wedges
while the root filesystem is being read. The upstream driver assumes the IRQ
path always fires, so it blocks forever waiting on an event that never arrives.

### What it changes

1. **Poll mode in the executor** (`drivers/executor/src/lib.rs`)
   - New `poll_mode` / `poll_timer` state plus `set_poll_mode()`.
   - When a command is in flight, `block_on` yields and re-polls the completion
     queue instead of blocking in `react()`. When idle it still blocks, so the
     driver does not busy-loop and starve other contexts on a single CPU.
   - A periodic `/scheme/time` timer (10 ms) is subscribed to the event queue.
     On expiry it re-arms itself and gives every external-event waiter a
     spurious wakeup, bounding the cost of a lost kernel wakeup.

2. **DMA fences on the NVMe queues** (`drivers/storage/nvmed/src/nvme/queues.rs`)
   - `fence(Ordering::Release)` before writing the submission/CQ doorbells and
     `fence(Ordering::Acquire)` after reading a completion entry, so the
     descriptor contents are visible to the device before the doorbell and the
     device's writes are visible to the CPU before the phase check.

3. **Submission-queue full check** (`queues.rs`)
   - `is_full()` was `head == tail + 1`, which misses the wrap-around case
     (`tail == len - 1`, `head == 0`). On a circular buffer that lets
     `submit_unchecked` overwrite an entry the controller has not consumed yet,
     silently dropping the command. Now masks the tail with `len - 1`.

4. **Enable it for nvmed** (`drivers/storage/nvmed/src/nvme/executor.rs`)
   - `set_poll_mode(true)` in the driver init.

Note: the CQ is already created with `Some(0)` upstream, so the interrupt vector
needs no change.

### Reproducing / applying

```sh
git clone https://gitlab.redox-os.org/redox-os/base.git
cd base
git apply /path/to/nvmed-aarch64-poll-fence.patch
```

### Integration status

**Not yet wired into the automated build.** The cookbook's supported mechanism
is a `patches` entry in the recipe's `[source]` table:

```toml
[source]
git = "https://gitlab.redox-os.org/redox-os/base.git"
patches = ["nvmed-aarch64-poll-fence.patch"]
```

but `recipes/core/base/recipe.toml` lives inside the read-only pinned
`redox-os/` tree, so this cannot be edited in place. `repo cook` accepts
`--cookbook=<dir>` to point at a different recipes directory, which is the
supported way to shadow recipes. The `base.git` revision is currently fetched
**unpinned** by the recipe, so the patch is re-checked against `main` at build
time until that is addressed.

Because `base.git` is unpinned, re-verify with `git apply --check` whenever the
upstream `main` moves.

### Verification performed

```
$ git apply --check nvmed-aarch64-poll-fence.patch   # clean
$ cargo build --target aarch64-unknown-redox         # executor: Finished
$ cargo build --target aarch64-unknown-redox         # nvmed: 0 warnings in patched files
```

The final link of `nvmed` under a bare `cargo build` fails on an unresolved
`futex` symbol inside the upstream `redox_rings` crate, because Redox userland
binaries are linked by the `base` makefile with its own link recipe rather than
by cargo's default. That is unrelated to this patch and does not occur in a
real image build.

Booting to `login:` on `aarch64` QEMU with the patch applied is **not yet
verified**; see `docs/gotchas/aarch64-nvmed-not-reproducible.md`.
