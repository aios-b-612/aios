#!/usr/bin/env bash
# Headless boot smoke-test for a built AIOS image.
#
# Boots the image in QEMU without a display, watches the serial console,
# and reports PASS/FAIL. Used as the Phase 1 boot canary and in CI.
#
# Usage:
#   test.sh [-a ARCH] [-c CONFIG] [-t SECONDS] [--gic-v3]
#
#   -t SECONDS   test timeout (default: 600 for aarch64, 120 otherwise)
#   --gic-v3     enable GICv3/ITS on QEMU virt machine (aarch64 only)
#
# Environment:
#   REDOX_SOURCE  upstream redox tree (default <platform>/../redox-os)
#   QEMU_BIN      override qemu binary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE="${REDOX_SOURCE:-$(cd "${PLATFORM_DIR}/../redox-os" 2>/dev/null && pwd || echo "${PLATFORM_DIR}/../redox-os")}"

ARCH="${ARCH:-x86_64}"
CONFIG_NAME="${CONFIG_NAME:-ai-developer}"
TIMEOUT_SECS=0
GIC_V3=0

# Pre-process long options
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --gic-v3) GIC_V3=1 ;;
        --gic-v3=*) echo "ERROR: --gic-v3 does not take a value" >&2; exit 1 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

while getopts ":a:c:t:h" opt; do
    case "$opt" in
        a) ARCH="$OPTARG" ;;
        c) CONFIG_NAME="$OPTARG" ;;
        t) TIMEOUT_SECS="$OPTARG" ;;
        h) echo "Usage: test.sh [-a ARCH] [-c CONFIG] [-t SECONDS] [--gic-v3]"; exit 0 ;;
        \?) echo "Unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Default timeout: 600s for aarch64 (needs more time for NVMe/GIC), 120s otherwise
if [ "${TIMEOUT_SECS}" -eq 0 ]; then
    if [ "${ARCH}" = "aarch64" ]; then
        TIMEOUT_SECS=600
    else
        TIMEOUT_SECS=120
    fi
fi

BUILD="$(cd "${REDOX_SOURCE}" 2>/dev/null && pwd)/build/${ARCH}/${CONFIG_NAME}"

# Marker written into /etc/ai-platform by each image profile (see config/)
case "${CONFIG_NAME}" in
    ai-developer) VARIANT_MARKER="aios-developer-os" ;;
    ai-edge) VARIANT_MARKER="aios-edge-os" ;;
    *) VARIANT_MARKER="${CONFIG_NAME}" ;;
esac

case "${ARCH}" in
    x86_64) QEMU_BIN_DEFAULT="qemu-system-x86_64" ;;
    aarch64) QEMU_BIN_DEFAULT="qemu-system-aarch64" ;;
    i586) QEMU_BIN_DEFAULT="qemu-system-i386" ;;
    riscv64gc) QEMU_BIN_DEFAULT="qemu-system-riscv64" ;;
    *) echo "ERROR: unknown ARCH ${ARCH}" >&2; exit 1 ;;
esac
QEMU_BIN="${QEMU_BIN:-${QEMU_BIN_DEFAULT}}"

command -v "${QEMU_BIN}" >/dev/null 2>&1 || { echo "ERROR: ${QEMU_BIN} not installed" >&2; exit 2; }

# Prefer live iso (aarch64 default in qemu.mk), else harddrive image
IMG="${BUILD}/redox-live.iso"
[ -f "${IMG}" ] || IMG="${BUILD}/harddrive.img"
if [ ! -f "${IMG}" ]; then
    echo "ERROR: no image found in ${BUILD}" >&2
    exit 2
fi

# Per-architecture QEMU args (mirrors upstream mk/qemu.mk defaults)
case "${ARCH}" in
    x86_64)
        MACHINE="q35"
        CPU="core2duo"
        SMP=4
        MEM=2048
        DISK_ARGS="-drive file=${IMG},format=raw,if=none,id=drv0 -device nvme,drive=drv0,serial=NVME_SERIAL"
        NET_ARGS="-device e1000,netdev=net0 -netdev user,id=net0"
        ;;
    aarch64)
        MACHINE="virt"
        CPU="max"
        SMP=1
        MEM=2048
        DISK_ARGS="-drive file=${IMG},format=raw,if=none,id=drv0 -device nvme,drive=drv0,serial=NVME_SERIAL"
        NET_ARGS="-device e1000,netdev=net0 -netdev user,id=net0"
        # UEFI firmware required to boot aarch64 (no SeaBIOS on this machine).
        # Prefer the edk2 firmware shipped with qemu-efi-aarch64.
        BIOS="${QEMU_BIOS:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}"
        [ -f "${BIOS}" ] || BIOS="/usr/share/qemu/edk2-aarch64-code.fd"
        [ -f "${BIOS}" ] || { echo "ERROR: no aarch64 UEFI firmware found in /usr/share/qemu-efi-aarch64 or /usr/share/qemu" >&2; exit 2; }
        # GICv3/ITS support for NVMe IRQ delivery
        if [ "${GIC_V3}" -eq 1 ]; then
            MACHINE="virt,gic-version=3,its=on,iommu=smmuv3"
            echo "  [INFO] GICv3/ITS + SMMUv3 IOMMU enabled for NVMe IRQ delivery"
        fi
        ;;
    i586)
        MACHINE="pc"
        CPU="pentium2"
        SMP=1
        MEM=1024
        DISK_ARGS="-drive file=${IMG},format=raw"
        NET_ARGS="-device e1000,netdev=net0 -netdev user,id=net0"
        ;;
    *)
        echo "ERROR: no default QEMU args for ARCH ${ARCH}" >&2
        exit 2
        ;;
esac

# Prefer KVM acceleration when available; otherwise fall back to TCG (slow).
# On an x86_64 host KVM cannot run aarch64 guests, so aarch64 always uses TCG.
ACCEL_ARGS=""
BIOS="${BIOS:-}"
LOGIN_DELAY="${LOGIN_DELAY:-40}"
if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ "${ARCH}" != "aarch64" ]; then
    ACCEL_ARGS="-enable-kvm"
fi
if [ "${ARCH}" = "aarch64" ]; then
    LOGIN_DELAY="${LOGIN_DELAY:-120}"
fi
# Give extra time for GICv3 initialization
if [ "${GIC_V3}" -eq 1 ]; then
    LOGIN_DELAY=$((LOGIN_DELAY + 60))
fi
if [ -n "${BIOS}" ]; then BIOS_ARGS="-bios ${BIOS}"; else BIOS_ARGS=""; fi

echo "==> AIOS boot test"
echo "    arch:   ${ARCH}"
echo "    config: ${CONFIG_NAME}"
echo "    image:  ${IMG}"
echo "    qemu:   $(command -v "${QEMU_BIN}")"
echo "    accel:  ${ACCEL_ARGS:-tcg}"
echo "    timeout: ${TIMEOUT_SECS}s"

OUT=$(mktemp)
cleanup() { rm -f "${OUT}"; }
trap cleanup EXIT

# Headless serial console test. The serial console is used both to observe
# the boot and to drive a session: log in as `user` and verify the Phase 1
# image content placeholders are present in the guest.
set +e
(
    sleep "${LOGIN_DELAY}"
    printf 'user\n'
    sleep 2
    printf 'ls /var/lib/ai\n'
    sleep 2
    printf 'cat /etc/ai-platform\n'
    sleep 2
    printf 'exit\n'
    sleep 2
) | timeout --foreground "${TIMEOUT_SECS}" "${QEMU_BIN}" \
    ${ACCEL_ARGS} \
    ${BIOS_ARGS} \
    -machine "${MACHINE}" -cpu "${CPU}" -smp "${SMP}" -m "${MEM}" \
    ${DISK_ARGS} \
    ${NET_ARGS} \
    -vga none -serial stdio -monitor none -no-reboot > "${OUT}" 2>&1
status=${PIPESTATUS[1]}
set -e

echo
# The guest never powers itself off, so TIMEOUT (124) is the expected end
# state once the milestones were verified; any other early exit is a crash.
if [ "${status}" -ne 0 ] && [ "${status}" -ne 124 ]; then
    echo "RESULT: QEMU exited early with status ${status}" >&2
    exit 1
fi

# Boot milestones and image checks to look for in the console log.
# The typed commands themselves never contain these strings, so each
# match proves the corresponding guest-side milestone really ran.
check_milestone() {
    local needle="$1"
    if grep -qF "$needle" "${OUT}"; then
        echo "  [OK]   ${needle}"
    else
        echo "  [MISS] ${needle}"
        return 1
    fi
}

ok=1
if [ "${ARCH}" = "aarch64" ]; then
    # aarch64 currently reaches the kernel + initfs, but the NVMe driver
    # stack-overflows (guard page hit) on master, so login cannot be reached
    # under QEMU. Track the upstream blocker; fail the canary if even the
    # kernel no longer boots.
    check_milestone "Redox OS Bootloader" || ok=0
    check_milestone "Currently in EL1" || ok=0
    check_milestone "kernel_entry" || ok=0
    # With GICv3/ITS, we expect to reach the login prompt
    if [ "${GIC_V3}" -eq 1 ]; then
        check_milestone "login:" || ok=0
        check_milestone "models" || ok=0
        check_milestone "${VARIANT_MARKER}" || ok=0
    fi
    if [ "${ok}" -eq 1 ]; then
        if [ "${GIC_V3}" -eq 1 ]; then
            echo "  [INFO] aarch64 with GICv3: checking for login prompt"
        else
            echo "  [WARN] aarch64 userland blocked upstream: initfs nvmed stack-overflow"
            echo "         (see docs/REDOX_AUDIT.md, ROADMAP.md Phase 5)"
        fi
    fi
else
    check_milestone "login:" || ok=0
    check_milestone "models" || ok=0
    check_milestone "${VARIANT_MARKER}" || ok=0
fi

if [ "${ok}" -eq 1 ]; then
    echo "RESULT: PASS"
    exit 0
else
    echo "RESULT: FAIL (boot milestones not all reached)" >&2
    exit 1
fi