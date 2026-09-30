#!/usr/bin/env bash
# Repeated-command stability test for a built AIOS image.
#
# WHY THIS EXISTS, SEPARATE FROM test.sh
#
# test.sh asks "did the image boot?". That question cannot see intermittent
# crashes. On this image, `uutils` binaries (`ls`, `cat`) intermittently
# overflow their own stack and take a guard-page fault. A boot canary logs in
# and runs each command once, so it passes while the underlying rate is roughly
# 1 failure in 10.
#
# The rate only shows up when the same command is repeated inside a single
# boot. That is what this script does: it runs each command N times and
# requires every single one to succeed, with zero unhandled exceptions.
#
# It runs on x86_64 too, and that is the point: the control run proved the
# crash is NOT caused by the aarch64 NVMe patch, since x86_64 never applies it
# and still fails. See docs/gotchas/security-isolation.md.
#
# Measured, 10 repeats per command, one boot each:
#   aarch64 (patch applied): ls 6-8/10, cat 8/10
#   x86_64 (no patch at all): ls 10/10,  cat 9-10/10
#
# Usage:
#   test-stability.sh [-a ARCH] [-c CONFIG] [-n REPEATS] [-t SECONDS]
#
#   -a ARCH     x86_64 or aarch64 (default: aarch64)
#   -c CONFIG   image profile (default: ai-edge)
#   -n REPEATS  invocations per command, per boot (default: 10)
#   -t SECONDS  test timeout (default: 900)
#
# Exit codes:
#   0  PASS  every repeat produced correct output, zero crashes
#   1  FAIL  a repeat lost output, or a process took an unhandled exception
#   2  ERROR the test could not run (missing QEMU, firmware, or image)
#
# Environment:
#   REDOX_SOURCE  upstream redox tree (default <platform>/../redox-os)
#   BOOT_LOG      where to keep the console log (default /tmp/aios-stability-<arch>.log)
#   LOGIN_DELAY   seconds to wait before logging in (default: 200 aarch64, 100 x86_64)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE="${REDOX_SOURCE:-$(cd "${PLATFORM_DIR}/../redox-os" 2>/dev/null && pwd || echo "${PLATFORM_DIR}/../redox-os")}"

ARCH="aarch64"
CONFIG_NAME="ai-edge"
REPEATS=10
TIMEOUT_SECS=900

while getopts ":a:c:n:t:h" opt; do
    case "$opt" in
        a) ARCH="$OPTARG" ;;
        c) CONFIG_NAME="$OPTARG" ;;
        n) REPEATS="$OPTARG" ;;
        t) TIMEOUT_SECS="$OPTARG" ;;
        h) echo "Usage: test-stability.sh [-a ARCH] [-c CONFIG] [-n REPEATS] [-t SECONDS]"; exit 0 ;;
        \?) echo "Unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

case "${REPEATS}" in
    ''|*[!0-9]*) echo "ERROR: -n needs a positive integer" >&2; exit 1 ;;
esac
[ "${REPEATS}" -gt 0 ] || { echo "ERROR: -n must be greater than zero" >&2; exit 1; }

case "${ARCH}" in
    aarch64)
        QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
        # aarch64 `virt` has no BIOS, so the image needs UEFI firmware.
        BIOS="${QEMU_BIOS:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}"
        [ -f "${BIOS}" ] || BIOS="/usr/share/qemu/edk2-aarch64-code.fd"
        [ -f "${BIOS}" ] || { echo "ERROR: no aarch64 UEFI firmware found" >&2; exit 2; }
        LOGIN_DELAY="${LOGIN_DELAY:-200}"
        # x86_64 keeps KVM when available; aarch64 on an x86_64 host cannot, so
        # it is always TCG and always slow.
        ARCH_ARGS="-accel tcg -machine virt -cpu max -smp 1 -m 2048 -bios ${BIOS}"
        ;;
    x86_64)
        QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
        LOGIN_DELAY="${LOGIN_DELAY:-100}"
        # -machine accel= is used instead of -accel because passing both is an
        # error in current QEMU.
        ARCH_ARGS="-machine q35,accel=kvm:tcg -cpu qemu64 -smp 1 -m 2048"
        ;;
    *)
        echo "ERROR: stability test not defined for ARCH ${ARCH}" >&2
        exit 2
        ;;
esac

command -v "${QEMU_BIN}" >/dev/null 2>&1 || { echo "ERROR: ${QEMU_BIN} not installed" >&2; exit 2; }

BUILD="${REDOX_SOURCE}/build/${ARCH}/${CONFIG_NAME}"
IMG="${BUILD}/harddrive.img"
[ -f "${IMG}" ] || { echo "ERROR: no image found in ${IMG}" >&2; exit 2; }

BOOT_LOG="${BOOT_LOG:-/tmp/aios-stability-${ARCH}.log}"

# Each command below must print its marker on every single repeat. The marker is
# what proves the guest-side command actually ran and returned real data, rather
# than the shell silently accepting a dead process.
CMD_LS="ls /var/lib/ai"
LS_MARKER="models"
CMD_CAT="cat /etc/ai-platform"
case "${CONFIG_NAME}" in
    ai-developer) CAT_MARKER="aios-developer-os" ;;
    ai-edge) CAT_MARKER="aios-edge-os" ;;
    *) CAT_MARKER="${CONFIG_NAME}" ;;
esac

echo "==> AIOS ${ARCH} stability test"
echo "    image:   ${IMG}"
echo "    repeats: ${REPEATS} per command, single boot"
echo "    timeout: ${TIMEOUT_SECS}s"
echo "    log:     ${BOOT_LOG}"

OUT=$(mktemp)
cleanup() { rm -f "${OUT}"; }
trap cleanup EXIT

# Scripted stdin. trap '' PIPE because once the guest stops reading -- which is
# what a crash looks like -- printf takes SIGPIPE, and that is expected here.
set +e
(
    trap '' PIPE
    sleep "${LOGIN_DELAY}"
    printf 'user\n' || true
    sleep 2
    i=0
    while [ "${i}" -lt "${REPEATS}" ]; do
        printf '%s\n' "${CMD_LS}" || true
        sleep 1
        printf '%s\n' "${CMD_CAT}" || true
        sleep 1
        i=$((i + 1))
    done
    printf 'exit\n' || true
    sleep 2
) 2>/dev/null | timeout --foreground "${TIMEOUT_SECS}" "${QEMU_BIN}" \
    ${ARCH_ARGS} \
    -drive file="${IMG}",format=raw,if=none,id=drv0 \
    -device nvme,drive=drv0,serial=NVME_SERIAL \
    -device e1000,netdev=net0 -netdev user,id=net0 \
    -display none -vga none -serial stdio -monitor none -no-reboot > "${OUT}" 2>&1
status=${PIPESTATUS[1]}
set -e

cat "${OUT}" > "${BOOT_LOG}"

if [ "${status}" -ne 0 ] && [ "${status}" -ne 124 ]; then
    echo "RESULT: QEMU exited early with status ${status}" >&2
    exit 1
fi

# The guest never powers off, so a timeout (124) after the milestones is the
# expected end state. A short console log means the guest died before login.
if ! grep -qF "login:" "${OUT}"; then
    echo "RESULT: FAIL (never reached a login prompt)" >&2
    exit 1
fi

count_marker() {
    grep -acF "$1" "${OUT}" || true
}

ls_ok=$(count_marker "${LS_MARKER}")
cat_ok=$(count_marker "${CAT_MARKER}")

# An unhandled exception in a specific binary. Matched per-binary because a
# crash in virtio-netd is a separate, known aarch64 gap (no MSI-X support in
# Redox's PCID layer) and must not be charged to this test.
count_crashes() {
    grep -ac "UNHANDLED EXCEPTION.*NAME $1" "${OUT}" || true
}
ls_crashes=$(count_crashes "/usr/bin/ls")
cat_crashes=$(count_crashes "/usr/bin/cat")
guard_pages=$(grep -ac "GUARD PAGE" "${OUT}" || true)

echo
echo "  ls    ${CMD_LS}    ok ${ls_ok}/${REPEATS}  crashes ${ls_crashes}"
echo "  cat   ${CMD_CAT}   ok ${cat_ok}/${REPEATS}  crashes ${cat_crashes}"
echo "  guard-page faults in console: ${guard_pages}"

ok=1
[ "${ls_ok}" -eq "${REPEATS}" ] || { echo "  [MISS] ${LS_MARKER}: ${ls_ok}/${REPEATS}"; ok=0; }
[ "${cat_ok}" -eq "${REPEATS}" ] || { echo "  [MISS] ${CAT_MARKER}: ${cat_ok}/${REPEATS}"; ok=0; }
[ "${ls_crashes}" -eq 0 ] || { echo "  [FAIL] ${ls_crashes} unhandled exception(s) in /usr/bin/ls"; ok=0; }
[ "${cat_crashes}" -eq 0 ] || { echo "  [FAIL] ${cat_crashes} unhandled exception(s) in /usr/bin/cat"; ok=0; }

if [ "${ok}" -eq 0 ]; then
    echo "RESULT: FAIL (intermittent corruption -- see ${BOOT_LOG})" >&2
    exit 1
fi

echo "RESULT: PASS"
exit 0
