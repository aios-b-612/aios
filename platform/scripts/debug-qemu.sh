#!/usr/bin/env bash
# Attach a Rust debugger (gdb) to a QEMU instance of an AIOS image.
#
# Usage:
#   debug-qemu.sh [-a ARCH] [-c CONFIG]
#
# Forwards to upstream `make gdb` / `make gdb-userspace` (see Makefile).
# Requires: rust-gdb or gdb-multiarch (set RUST_GDB env to override).
#
# Environment:
#   REDOX_SOURCE  upstream redox tree (default <platform>/../redox-os)
#   RUST_GDB      debugger binary (default gdb-multiarch)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE="${REDOX_SOURCE:-$(cd "${PLATFORM_DIR}/../redox-os" 2>/dev/null && pwd || echo "${PLATFORM_DIR}/../redox-os")}"

ARCH="${ARCH:-x86_64}"
CONFIG_NAME="${CONFIG_NAME:-ai-developer}"

while getopts ":a:c:h" opt; do
    case "$opt" in
        a) ARCH="$OPTARG" ;;
        c) CONFIG_NAME="$OPTARG" ;;
        h) echo "Usage: debug-qemu.sh [-a ARCH] [-c CONFIG]"; exit 0 ;;
        \?) echo "Unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

[ -d "${REDOX_SOURCE}" ] || { echo "ERROR: source not found: ${REDOX_SOURCE}" >&2; exit 1; }

export ARCH
export CONFIG_NAME
export RUST_GDB="${RUST_GDB:-gdb-multiarch}"

cd "${REDOX_SOURCE}"
echo "==> Start QEMU in another terminal with:"
echo "    ${PLATFORM_DIR}/scripts/run-qemu.sh -a ${ARCH} -c ${CONFIG_NAME}"
echo "==> Then attach gdb:"
echo "    make gdb           (kernel)"
echo "    make gdb-userspace (userspace app)"
echo
echo "Launching kernel gdb session now..."
exec make gdb "$@"