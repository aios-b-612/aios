# aarch64 nvmed fix is NOT reproducible

Date: 2026-09-28. Status: **open gap**. The aarch64 userland boot fix recorded in
commit `61d483a` and in ROADMAP.md (Phase 1/5) does not exist anywhere in this
repository, so `make build` from a clean checkout cannot reproduce it.

## What the docs claim

ROADMAP.md (Phase 1) and commit `61d483a` state that a DMA-barrier + poll-mode
fix in the `nvmed` block driver was applied on 2026-09-25 and that the aarch64
userland then booted to the `login:` prompt:

> fix aarch64 nvmed DMA fences + poll mode (local only) - add Release/Acquire
> fences in queue kick/complete - correct root-cause in docs

REDOX_AUDIT.md §2.15 and the gotcha index reference the same outcome.

## What is actually on disk

Nothing. Verified:

```
$ git -C redox-os status --short          # clean working tree
$ git -C redox-os rev-parse HEAD
e2bf6961ec313764ef7a624e272d72d2158aa5ae  # upstream master, 2026-09-23
$ find redox-os -name nvmed.rs            # no results
$ grep -rl "nvme" redox-os --include=*.rs # no results
```

The upstream `redox-os/redox` tree at that commit contains **no `kernel/` and no
`drivers/` directory at all**. The kernel is not vendored: it is consumed as a
prebuilt package declared by `redox-os/recipes/core/kernel/recipe.toml`:

```toml
[source]
git = "https://gitlab.redox-os.org/redox-os/kernel.git"
```

With the default `REPO_BINARY=1`, `cook` downloads a built `source.pkgar`
instead of cloning sources. The images on this machine were built against:

```
source_identifier = bbb5d49f0e81dded9ff73829ee56f96c83092263
time_identifier   = 2026-09-24T07:59:23Z
```

That is the stock Redox kernel package. The locally patched kernel that made
aarch64 reach `login:` was built once, dropped into `recipes/core/kernel/target/`,
and never committed as a patch — so it is gone.

## Why this matters

1. **Fase 1's reproducibility claim is false as written.** `make build` on a
   fresh host yields an aarch64 image whose block driver may again stack-fault
   at initfs, and there is no patch in-tree to reapply.
2. **`docs/gotchas/redox-netstack-abort-boot-blocker.md` is referenced by
   ROADMAP.md and `ai-edge.toml` but does not exist** — the aarch64 blocker
   record is incomplete. Only the `nvmed` slice was ever written down, and only
   in the ROADMAP prose.
3. **CI's aarch64 job is `continue-on-error: true`**, so a regression here is
   invisible: the job cannot fail the build.

## Resolution options

| Option | What it takes | Cost |
|---|---|---|
| **A. Vendor the patch** (recommended) | Recover the diff, add it under `platform/patches/aarch64/`, apply it in `bootstrap.sh`/build | Needs the original diff or a rebuild from the kernel git history to reproduce it |
| B. Pin a kernel package SHA that contains the fix | Land the fix upstream, then pin it in `platform/upstream.lock` | Depends on upstream accepting the patch |
| C. Drop aarch64 boot claims | Mark aarch64 as unvalidated-until-reproved, x86_64 only | Loses the Fase 6 target |

Option A needs the actual source. The kernel git history at
`gitlab.redox-os.org/redox-os/kernel.git` is the place to look for a branch or
commit carrying the fences/poll-mode change; the ROADMAP dates it 2026-09-25.

## Interim position

Until the patch is recovered, this repository's honest claim is:

- **x86_64 `ai-developer`: validated** (boot → login → real inference).
- **aarch64 `ai-edge`: built and previously observed booting to login on this
  host, but the fix is not in-tree and therefore not reproducible.**

`platform/scripts/release.sh` records the kernel `source_identifier` of every
artifact precisely so this cannot be silently forgotten again.
