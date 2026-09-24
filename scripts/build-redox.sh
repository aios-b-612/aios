#!/usr/bin/env bash
# Cross-build the AIOS workspace for x86_64-unknown-redox using the upstream
# prefix toolchain (from a prior native Redox build).
#
# Usage: scripts/build-redox.sh [cargo args...]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${HERE}/.." && pwd)"
PREFIX="${REDOX_PREFIX:-${WORKSPACE}/redox-os/prefix/x86_64-unknown-redox}"
RUST="$PREFIX/rust-install"
GCC="$PREFIX/gcc-install"

[ -x "$RUST/bin/rustc" ] || { echo "error: prefix toolchain not found at $PREFIX" >&2; exit 1; }
[ -d "$GCC/bin" ] || { echo "error: cross gcc not found at $GCC" >&2; exit 1; }

export LD_LIBRARY_PATH="$PREFIX/sysroot/lib:$PREFIX/clang-install/lib:$RUST/lib/rustlib/x86_64-unknown-linux-gnu/lib:$RUST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$GCC/bin:$PATH"
# Make sure cargo uses the prefix rustc (not the host rustup toolchain).
export RUSTC="$RUST/bin/rustc"
export RUSTC_LINKER="x86_64-unknown-redox-gcc"

cd "$WORKSPACE"
export CARGO_TARGET_X86_64_UNKNOWN_REDOX_LINKER="x86_64-unknown-redox-gcc"
exec "$RUST/bin/cargo" build --target x86_64-unknown-redox "$@"