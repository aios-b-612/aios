# aarch64 nvmed fix was unreproducible — now recovered and applied

Date: 2026-09-28. Status: **patch recovered, applied by the build, boot not
re-verified**.

The aarch64 userland boot fix recorded in commit `61d483a` and in ROADMAP.md
(Phase 1/5) is now recovered as a real patch at
`platform/patches/aarch64/nvmed-aarch64-poll-fence.patch`, pinned to
`base.git` `8fdf4e4b` in `platform/upstream.lock` `[base]`, and applied
automatically by `platform/scripts/apply-patches.sh`.

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
- `repo fetch base` applies the patch: the cookbook logs `patching file` for
  all three files, checks out the pinned revision, and the fetched source
  contains `poll_mode`, the three fences and the corrected `is_full`.
- `apply-patches.sh` is idempotent, and `--verify` exits 2 both when the recipe
  loses its `patches` line and when a patch file drifts from `platform/patches/`.
- `bootstrap.sh --update` re-applies the overlay after re-checking-out the pin.

## Integrating the patch was harder than expected

The cookbook advertises `repo cook --cookbook=<dir>` for using a different
recipes directory, which looked like the clean way to shadow
`recipes/core/base` without touching the pinned tree. **It is dead code in the
pinned version.** The recipe index is built by
`ignore::Walk::new("recipes")` (`redox-os/src/staged_pkg.rs:19`), a path
relative to the working directory, and `config.cookbook_dir` — which the flag
sets at `src/bin/repo/main.rs:475` — is never read anywhere in `src/`.

Verified directly rather than inferred: with a deliberately invalid patch file
in the alternate directory, `repo fetch base --cookbook=<dir>` still reported
`fetch base - successful` and produced an unpatched source.

So the recipe is edited in place instead. The overlay is deterministic and
verified, and the git pin is untouched, but `redox-os/` is no longer
byte-identical to upstream, which is the assumption ADR-001 makes. If the pin
is ever bumped, re-run `apply-patches.sh` and re-check the patch.

## What is still open

1. **Booting to `login:` on aarch64 with the patch has not been re-verified.**
   The patch is applied by the build and compiles, but "it boots" is still an
   assumption until an image is rebuilt and run. This is the remaining Phase 6
   gate.
2. `docs/gotchas/redox-netstack-abort-boot-blocker.md` is still referenced by
   ROADMAP.md and `ai-edge.toml` but does not exist.
3. CI's aarch64 job is `continue-on-error: true`, so a regression there stays
   invisible.
4. `platform/config/aarch64/ai-edge.toml` still describes the NVMe hang as an
   open upstream blocker. That text is now stale: the fix exists locally and is
   applied, and what remains unproven is only the boot.

## Interim position

- **x86_64 `ai-developer`: validated** (boot → login → real inference).
- **aarch64 `ai-edge: buildable, and previously observed booting to login on
  this host.** The fix is in-tree, pinned, and applied by the build, but the
  boot has not been re-verified since recovery, so treat a clean-checkout boot
  as unproven rather than as working.

`platform/scripts/release.sh` records the kernel `source_identifier` of every
artifact precisely so this cannot be silently forgotten again.
