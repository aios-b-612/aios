# aarch64 nvmed fix was unreproducible — now recovered

Date: 2026-09-28. Status: **patch recovered, not yet wired into the build**.

The aarch64 userland boot fix recorded in commit `61d483a` and in ROADMAP.md
(Phase 1/5) is now recovered as a real patch at
`platform/patches/aarch64/nvmed-aarch64-poll-fence.patch`.

## What the docs claimed

ROADMAP.md (Phase 1) and commit `61d483a` state that a DMA-barrier + poll-mode
fix in the `nvmed` block driver was applied on 2026-09-25 and that the aarch64
userland then booted to the `login:` prompt:

> fix aarch64 nvmed DMA fences + poll mode (local only) - add Release/Acquire
> fences in queue kick/complete - correct root-cause in docs

## Why it looked lost

An earlier investigation (2026-09-28) concluded the fix did not exist anywhere,
and that it was unrecoverable. **That conclusion was wrong**, for two reasons:

1. **The wrong repositories were searched.** `nvmed` is not in the kernel. It
   lives in `redox-os/base.git` under `drivers/storage/nvmed/`, and the executor
   it depends on is `drivers/executor/`. The `redox` tree at the pinned commit
   contains neither `kernel/` nor `drivers/`, so searching only `redox-os/`
   could never find it.

2. **The fix was never a commit.** It existed only as uncommitted changes in a
   local checkout, so no `git log` in any repository could surface it.

The kernel is genuinely a prebuilt package (see `platform/upstream.lock`), but
that is unrelated to the `nvmed` change and should not be cited as the reason
the fix is missing.

## Where the fix actually was

A dirty checkout of `base.git` at `fd646c8` (`/tmp/opencode/base`) carried the
change as working-tree modifications, mixed together with throwaway diagnostic
instrumentation. The upstream `main` of `base.git` (`8fdf4e4`) has never touched
the files involved, so the patch applies cleanly.

The recovered diff contained both the real fix and a large amount of temporary
debug scaffolding (`DIAG_*` counters, watchdog threads, `log::error!` tracing,
a 5s→600s init timeout used to watch a hang). All of the scaffolding was
removed; the diagnostics were how the fix was originally found and are not
needed to keep it.

The real fix has four parts:

1. Poll mode in the executor, so a command in flight re-polls the completion
   queue instead of blocking on an interrupt that never arrives, with a 10 ms
   `/scheme/time` timer bounding the wait when idle.
2. `Release` fences before the doorbell writes and an `Acquire` fence after
   reading a completion entry, so descriptor contents are visible to the device
   before the doorbell and the device's writes to the CPU before the phase check.
3. A real bug in `is_full()`: `head == tail + 1` misses the wrap-around case
   (`tail == len - 1`, `head == 0`), letting `submit_unchecked` overwrite an
   entry the controller has not consumed. This drops commands silently and is
   not specific to aarch64.
4. `set_poll_mode(true)` in the `nvmed` driver init.

Full description, target revision and verification steps:
`platform/patches/aarch64/README.md`.

## What has been verified

- `git apply --check` against `base.git` `8fdf4e4`: clean.
- `cargo build --target aarch64-unknown-redox` for `executor`: succeeds.
- `cargo build --target aarch64-unknown-redox` for `nvmed`: the patched files
  introduce no new warnings (the four `never used` warnings in `queues.rs` are
  pre-existing and identical without the patch).

## What is still open

1. **The patch is not yet applied by the build.** The cookbook supports a
   `patches` entry in a recipe's `[source]` table, but
   `recipes/core/base/recipe.toml` is inside the read-only pinned `redox-os/`
   tree. `repo cook` accepts `--cookbook=<dir>` to shadow recipes, which is the
   supported route, but it is not implemented.
2. **`base.git` is fetched unpinned** by the recipe, so the patch is re-checked
   against a moving `main`. `platform/upstream.lock` pins the `redox` repo and
   the kernel package but not `base.git`.
3. **Booting to `login:` on aarch64 with the patch has not been re-verified.** The
   code compiles and the patch is a faithful recovery of what previously worked,
   but "it boots" is still an assumption until an image is rebuilt and run.
4. `docs/gotchas/redox-netstack-abort-boot-blocker.md` is still referenced by
   ROADMAP.md and `ai-edge.toml` but does not exist.
5. CI's aarch64 job is `continue-on-error: true`, so a regression there stays
   invisible.

## Interim position

- **x86_64 `ai-developer`: validated** (boot → login → real inference).
- **aarch64 `ai-edge`: buildable, and previously observed booting to login on
  this host.** The fix is now in-tree as a patch and compiles, but it is not yet
  applied by the automated build, so a clean-checkout build does not yet
  reproduce the boot.

`platform/scripts/release.sh` records the kernel `source_identifier` of every
artifact precisely so this cannot be silently forgotten again.
