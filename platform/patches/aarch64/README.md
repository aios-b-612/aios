# aarch64 platform patches

Patches applied on top of the pinned upstream Redox tree. The upstream tree in
`redox-os/` stays read-only (see ADR-001); everything that has to deviate lives
here so the deviation is visible and reviewable.

## `nvmed-aarch64-poll-fence.patch`

| | |
|---|---|
| Target repo | `https://gitlab.redox-os.org/redox-os/base.git` |
| Target path | `drivers/executor/`, `drivers/storage/nvmed/` |
| Pinned revision | `8fdf4e4bf9a61b240aaf49e23a6541682cf30d6c` (`main`, 2026-09-24), recorded in `platform/upstream.lock` `[base]` |
| Size | 3 files, +119 / -5 |
| Status | applied by the build; compiles for `aarch64-unknown-redox` with no new warnings |

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

### Integration

Applied automatically by `platform/scripts/apply-patches.sh`, which
`build.sh` runs before the upstream build and `bootstrap.sh --verify` checks.

The script copies the patch next to the recipe it targets and rewrites that
recipe's `[source]` table to pin the revision and list the patch:

```toml
[source]
git = "https://gitlab.redox-os.org/redox-os/base.git"
rev = "8fdf4e4bf9a61b240aaf49e23a6541682cf30d6c"
patches = ["nvmed-aarch64-poll-fence.patch"]
```

That is the cookbook's own supported `patches` mechanism: the patch files are
resolved relative to the recipe directory, and the cookbook applies them with
`patch --strip=1` during `repo fetch`. Because `base` is a source (not binary)
recipe, the patch really is applied rather than bypassed by a prebuilt
`.pkgar` download.

### Why the recipe is edited in place

The cookbook advertises a `--cookbook=<dir>` flag for pointing at a different
recipes directory, but it is dead code in the pinned version. The recipe index
is built by

```rust
// redox-os/src/staged_pkg.rs
static RECIPE_PATHS: LazyLock<HashMap<PackageName, PathBuf>> = LazyLock::new(|| {
    for entry_res in ignore::Walk::new("recipes") {   // relative to CWD
```

and `config.cookbook_dir`, which the flag sets, is never read anywhere else in
`src/`. Passing a directory is silently ignored, so a recipe cannot be shadowed
that way. Verified directly: with an invalid patch file in the alternate
directory, `repo fetch base --cookbook=<dir>` still reported success and
fetched an unpatched source.

Editing the recipe in place is therefore the only mechanism the cookbook
honours. The trade-off is that `redox-os/` is no longer byte-identical to
upstream, which ADR-001 assumes. What is preserved: the git pin and its history
stay intact, the patch content lives in this repository, and the overlay is
deterministic, idempotent, and verified.

`bootstrap.sh --update` re-checks-out the pinned commit, which discards the
overlay, so it re-applies it afterwards. `bootstrap.sh --verify` fails (exit 2)
if the recipe or the patch files have drifted from `platform/patches/`.

### Verification performed

```
$ platform/scripts/apply-patches.sh --verify            # overlay matches
$ repo fetch base                                       # patching file drivers/executor/src/lib.rs
                                                     # patching file .../nvmed/executor.rs
                                                     # patching file .../nvmed/queues.rs
$ git -C recipes/core/base/source rev-parse HEAD       # 8fdf4e4b (pin honoured)
$ grep -c poll_mode <source>/drivers/executor/src/lib.rs   # 6
$ grep 'fence(Ordering' <source>/.../queues.rs          # Acquire + 2x Release
$ cargo build --target aarch64-unknown-redox            # executor: Finished
```

The final link of `nvmed` under a bare `cargo build` fails on an unresolved
`futex` symbol inside the upstream `redox_rings` crate, because Redox userland
binaries are linked by the `base` makefile with its own link recipe rather than
by cargo's default. That is unrelated to this patch and does not occur in a
real image build.

Booting to `login:` on `aarch64` QEMU with the patch applied is **not yet
verified**; see `docs/gotchas/aarch64-nvmed-not-reproducible.md`.
