# Reproducibility

What "reproducible" means for AIOS, and where it currently stops.

## The three pins

An AIOS image is determined by three inputs. All three are recorded in the
release manifest (`platform/scripts/release.sh` writes `dist/MANIFEST.txt`):

| Input | Pinned in | Value for the validated images |
|---|---|---|
| Upstream Redox tree | `platform/upstream.lock` | `e2bf6961ec313764ef7a624e272d72d2158aa5ae` (2026-09-23) |
| Kernel package | fetched by upstream `cook` from `redox-os/recipes/core/kernel/recipe.toml` | `source_identifier = bbb5d49f0e81dded9ff73829ee56f96c83092263` |
| AIOS layer | this repo's git commit | recorded as `aios_commit` |

The upstream tree is **not vendored** — it is ~1 GB of separate history. A clean
clone has no `redox-os/` and cannot build. `platform/scripts/bootstrap.sh`
materializes the pinned revision:

```sh
./platform/scripts/bootstrap.sh            # clone if missing, verify if present
./platform/scripts/bootstrap.sh --verify   # check the pin, fail on mismatch
./platform/scripts/bootstrap.sh --update   # re-checkout the pin
```

`make build` and `make release` both run `--verify` first, so a drifted
`redox-os/` fails loudly instead of silently producing a different image.

### Bumping the pin

Bump `platform/upstream.lock` deliberately, never as a side effect of
`git pull` in the redox tree. Record the reason in `docs/DECISIONS.md`, and
re-run the boot test (`make test ARCH=aarch64 CONFIG_NAME=ai-edge`) — an
upstream bump can change the kernel package without the tree commit changing,
because the kernel is resolved from the Redox package repository.

## The kernel is the weak link

The kernel does not come from the pinned commit. `redox-os/recipes/core/kernel/recipe.toml`
points at `gitlab.redox-os.org/redox-os/kernel.git`, and with the default
`REPO_BINARY=1` the build downloads a **prebuilt** `source.pkgar` rather than
compiling sources. Consequences:

- Two different `upstream.lock` commits can yield the same kernel package.
- A locally patched kernel is invisible to the pin and is **not** reproducible
  from a clean checkout. This already happened once — see
  `docs/gotchas/aarch64-nvmed-not-reproducible.md`, where the aarch64 NVMe fix
  that made the userland boot to `login:` was never committed as a patch.

`release.sh` therefore records the resolved kernel `source_identifier` for every
artifact instead of trusting the tree commit alone.

## What is *not* bit-reproducible

Upstream's build embeds timestamps and absolute build paths, so two builds of
the same commit on different hosts or at different times produce different image
bytes. Consequences for the release criteria:

- **Reproducible:** source selection (the three pins above), the checksums
  manifest, `SHA256SUMS` over a given artifact set, and the ability to attribute
  an artifact to exact inputs.
- **Not reproducible:** image bit-identity across hosts or rebuilds.

To get bit-identity you would need a hermetic build (fixed `SOURCE_DATE_EPOCH`,
normalized paths, no network except pinned sources) — that is upstream work in
`redox-os/`, not something this repository can guarantee.

## Validated targets

| Target | Status | Evidence |
|---|---|---|
| x86_64 `ai-developer` | boot → login → real TinyLlama inference in QEMU/KVM | `make test ARCH=x86_64 CONFIG_NAME=ai-developer` |
| aarch64 `ai-edge` | image builds; boot previously observed to `login:` on this host, but **not reproducible** from a clean checkout | `docs/gotchas/aarch64-nvmed-not-reproducible.md` |
| Raspberry Pi | **not validated** — no hardware | `docs/RASPBERRY_PI.md` |
