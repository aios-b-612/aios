#!/usr/bin/env bash
# Run a built AIOS image in QEMU.
#
# Usage:
#   run-qemu.sh [-a ARCH] [-c CONFIG] [qemu extra args...]
#
# Forwards to the upstream `make qemu` (mk/qemu.mk). See that file for
# per-architecture defaults (machine, firmware, net, disk, gpu).
#
# Environment:
#   REDOX_SOURCE  upstream redox tree (default <platform>/../redox-os)
#   QEMUFLAGS     extra qemu flags appended by upstream make

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
        h) echo "Usage: run-qemu.sh [-a ARCH] [-c CONFIG]"; exit 0 ;;
        \?) echo "Unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

for tool in qemu-system-${ARCH} qemu-system-${ARCH%%64}; do
    :
done

case "${ARCH}" in
    x86_64) QEMU_BIN="qemu-system-x86_64" ;;
    aarch64) QEMU_BIN="qemu-system-aarch64" ;;
    i586) QEMU_BIN="qemu-system-i386" ;;
    riscv64gc) QEMU_BIN="qemu-system-riscv64" ;;
    *) echo "ERROR: unknown ARCH ${ARCH}" >&2; exit 1 ;;
esac

if ! command -v "${QEMU_BIN}" >/dev/null 2>&1; then
    echo "ERROR: ${QEMU_BIN} not installed" >&2
    echo "  x86_64:  install qemu-system-x86 / qemu-system"
    echo "  aarch64: install qemu-system-aarch64" >&2
    exit 1
fi

[ -d "${REDOX_SOURCE}" ] || { echo "ERROR: source not found: ${REDOX_SOURCE}" >&2; exit 1; }

export ARCH
export CONFIG_NAME

cd "${REDOX_SOURCE}"
exec make qemu "$@"