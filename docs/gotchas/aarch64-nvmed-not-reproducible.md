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
- `repo fetch base --repo-binary` applies the patch: the cookbook logs
  `patching file` for all three files, checks out the pinned revision, and the
  fetched source contains `poll_mode`, the three fences and the corrected
  `is_full`.
- `apply-patches.sh` is idempotent, and `--verify` exits 2 when the recipe
  loses its `patches` line, when a patch file drifts from `platform/patches/`,
  or when the `cookbook.lock` source rule is missing.
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

## The silent one: a patched recipe still gets bypassed by default

Wiring `patches` into the recipe was not enough. The build defaults to
`REPO_BINARY=1`, which passes `--repo-binary` to the cookbook, and that makes a
recipe resolve to a downloaded prebuilt `source.pkgar` rather than its git
source. The patch is then never applied, because there is no source tree to
apply it to.

The failure mode is the dangerous kind: `repo fetch base --repo-binary` reports
`fetch base - successful` either way, and the build completes. Only the image
is wrong. Confirmed by inspection: before the fix, the fetch left no
`source/` directory and produced `recipes/core/base/target/<arch>/source.pkgar`.

`apply-patches.sh` therefore also pins the recipe to the `source` rule in
`cookbook.lock`, which overrides both the recipe default and `--repo-binary`.
With that in place, the same command clones the pinned revision and logs
`patching file` for all three files.

The general rule: **adding a patch to a recipe also has to force that recipe
off the binary path**, or it will be skipped without an error.

## Resolved: booting to `login:` on aarch64

A full image built with the patch boots to an interactive shell on QEMU
`virt` with the image on an emulated NVMe device. This closes the Phase 6
gate.

```
BdsDxe: starting Boot0001 "UEFI QEMU NVMe Ctrl NVME_SERIAL 1"
Redox OS Bootloader 1.0.0 on aarch64/UEFI
Looking for RedoxFS:
RedoxFS 5136f408-2c55-42fe-b3a2-518ccb28b902: 2045 MiB

redox login: user
Welcome to Redox OS!
us> id
uid=1000(user) gid=1000(user)
us> uname -a
Redox redox 0.5.12 b68957d4a3e1590c4f5b8d5608d94b3e45bd3b45 aarch64 Redox
```

The headless boot test reaches every milestone, including the guest-side
identity check that reads `/etc/ai-platform` over a serial login:

```
  [OK]   Redox OS Bootloader
  [OK]   Currently in EL1
  [OK]   kernel_entry
  [OK]   login:
  [OK]   models
  [OK]   aios-edge-os
RESULT: PASS
```

Getting there needed two host-level fixes that are easy to mistake for patch
problems, so both are recorded here.

**The image can silently be stale.** `$(BUILD)/harddrive.img` depends on
`$(REPO_TAG)`, and `cook` only reaches its `touch $(REPO_TAG)` when the cook
succeeds. After a failure the stamp is left older than the image, so make
considers the image up to date and a later "successful" build reuses it
without rebuilding. The `image` target exists for this: it removes only the
image and reruns, keeping the software cache. Check the image mtime against
`recipes/core/base/target/*/build/*/release/nvmed` before trusting a boot
result.

**`ninja` is not in the host dependency check.** `mk/depends.mk` checks rustup,
cbindgen, nasm and just, but the CMake-based cookbook recipes also need ninja,
and they fail with an opaque

```
CMake Error: CMake was unable to find a build program corresponding to "Ninja".
```

`platform/scripts/host-deps.sh` now installs it (apt package `ninja-build`, or
`pipx install ninja` when sudo needs a password).

## A stale canary can hide a fix

While the NVMe hang was open, `test.sh` reported `login:` and everything after
it as `[BLOCKED]` on aarch64 and exited 2, on the theory that userspace could
not start. That is a real trap: the canary stayed green while a milestone that
had started passing went unreported, and the text pointed at the NVMe hang long
after the hang was fixed.

`login:` is now a hard milestone on aarch64 like on x86_64, and a miss is a
plain FAIL. Exit 2 is reserved for "the test could not run" (no QEMU, no UEFI
firmware), which is a broken environment rather than a broken image.

## The edge image shipped without coreutils

Fixing the NVMe hang exposed a second, independent gap. `ai-edge.toml` had no
`[packages]` section, and the upstream `server.toml` it includes does not list
`coreutils`, so the image had no basic userspace tools. The boot test could
log in and list `/var/lib/ai`, but could not read `/etc/ai-platform`:

```
[ld.so]: failed to link '/usr/bin/cat': NotFound
```

That is not only a harness problem: someone inspecting a device over serial
has no `cat` either. `coreutils` is now in the profile's package list, and
`cat /etc/ai-platform` returns the file contents in-guest.

A milestone can also pass for the wrong reason, which is worth checking when
one is added: `models` first matched because `ls /var/lib/ai` printed a
directory named `models`, not because any model loaded.

## What is still open

1. `docs/gotchas/redox-netstack-abort-boot-blocker.md` is still referenced by
   ROADMAP.md and `ai-edge.toml` but does not exist.
2. `edge status` / `edge models` in-guest still need a working netstack for TCP
   round-trips, which is the open item above.

## Interim position

- **x86_64 `ai-developer**: boots and reaches real inference.** Not claimed
  validated: the repeated-command test faults `cat` intermittently here too.
- **aarch64 `ai-edge**: boots to a login prompt and a shell with the patch
  applied in-tree.** Not validated either, and worse than x86_64: `ls` and
  `cat` fail roughly 1 in 4 to 1 in 3 runs.

Both are limited by the same pre-existing `uutils` stack overflow, not by this
patch. See `security-isolation.md` and `platform/scripts/test-stability.sh`.
A boot canary runs each command once and cannot see an intermittent rate, so
passing the canary is not evidence of stability.

Neither of these says anything about physical Raspberry Pi hardware, which has
its own open problems: the SDHCI driver only matches `brcm,bcm2835-sdhci`, so
BCM2711 (Pi 4) is unsupported, and Pi 5 needs separate RP1/PCIe work.

`platform/scripts/release.sh` records the kernel `source_identifier` of every
artifact precisely so this cannot be silently forgotten again.

## Rebuilding after a source patch: three traps

Editing the tree under `recipes/core/base/source/` and re-running `build.sh`
does **not** reliably rebuild the image. All three of these have to be dealt
with, in order:

1. **`repo/<arch>/base.pkgar` shadows your source.** With `repo-bin: 0` the
   installer still extracts the prebuilt package if it is present, so the patch
   never reaches the image. Delete it (back it up first) to force a cook.
2. **`build/<arch>/<config>/repo.tag` gates the cook.** `make` treats it as up
   to date and skips `make cook` entirely, printing `Extracting base` and
   compiling nothing. Delete it.
3. **A `source_info.toml` written before your edit forces a re-cook** of every
   downstream package, and some of them need `autopoint` (from `gettext`),
   which is not installed and needs `sudo` to install. The cross-compiled
   `autopoint` in the Redox tree is a shell script and does run on the host,
   but it looks for its data in `/usr/share/gettext` and that directory is
   absent. A wrapper that exports `gettext_datadir` to the tree's copy under
   `recipes/tools/gettext/target/<host-arch>/stage/usr/share/gettext` is
   enough to get past it.

`platform/scripts/rebuild.sh` does all of this: it clears the three caches,
shims `autopoint` into `/tmp` (no root needed), forces `REPO_BINARY=0`, and
prints the resulting `nvmed` build timestamp so a stale binary is obvious.

Only after that does `cook base - successful` appear and a fresh `nvmed`
binary appear under `recipes/core/base/target/<arch>/build/`. Verify that
binary's timestamp before trusting any test result; a stale one silently
invalidates every measurement, which is how a 6/6 result was briefly mistaken
for a fix.
