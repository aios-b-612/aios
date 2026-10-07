#!/usr/bin/env bash
# Test TCP commands in-guest: boot the image, log in, run ping/curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE="${REDOX_SOURCE:-$(cd "${PLATFORM_DIR}/../redox-os" 2>/dev/null && pwd || echo "${PLATFORM_DIR}/../redox-os")}"

ARCH="x86_64"
CONFIG_NAME="ai-developer"
TIMEOUT_SECS=180

BUILD="$(cd "${REDOX_SOURCE}" 2>/dev/null && pwd)/build/${ARCH}/${CONFIG_NAME}"
IMG="${BUILD}/harddrive.img"
[ -f "${IMG}" ] || { echo "ERROR: no image found in ${IMG}" >&2; exit 2; }

# Copy image to avoid lock
TEST_IMG="/tmp/aios-tcp-test.img"
cp "${IMG}" "${TEST_IMG}"

QEMU_BIN="qemu-system-x86_64"
command -v "${QEMU_BIN}" >/dev/null 2>&1 || { echo "ERROR: ${QEMU_BIN} not installed" >&2; exit 2; }

ACCEL_ARGS="-enable-kvm"
MACHINE="q35"
CPU="core2duo"
SMP=4
MEM=2048
DISK_ARGS="-drive file=${TEST_IMG},format=raw,if=none,id=drv0 -device nvme,drive=drv0,serial=NVME_SERIAL"
NET_ARGS="-device e1000,netdev=net0 -netdev user,id=net0"
PFLASH0="/usr/share/OVMF/OVMF_CODE_4M.fd"
PFLASH_ARGS="-drive if=pflash,format=raw,readonly=on,unit=0,file=${PFLASH0}"

BOOT_LOG="/tmp/aios-tcp-cmd-test.log"
mkdir -p "$(dirname "${BOOT_LOG}")"

echo "==> AIOS TCP command test in-guest"
echo "    image:  ${TEST_IMG}"
echo "    log:    ${BOOT_LOG}"

OUT=$(mktemp)
cleanup() { rm -f "${OUT}" "${TEST_IMG}"; }
trap cleanup EXIT

# Scripted stdin: wait for login, run commands, exit
set +e
(
    trap '' PIPE
    sleep 60
    printf 'user\n' || true
    sleep 3
    printf 'ping -c 3 10.0.2.2\n' || true
    sleep 5
    printf 'which curl\n' || true
    sleep 2
    printf 'curl -s http://10.0.2.2:8989/api/health 2>&1 || echo "CURL_FAILED"\n' || true
    sleep 5
    printf 'ls /var/lib/ai\n' || true
    sleep 2
    printf 'cat /etc/ai-platform\n' || true
    sleep 2
    printf 'exit\n' || true
    sleep 2
) 2>/dev/null | timeout --foreground "${TIMEOUT_SECS}" "${QEMU_BIN}" \
    ${ACCEL_ARGS} \
    ${PFLASH_ARGS} \
    -machine "${MACHINE}" -cpu "${CPU}" -smp "${SMP}" -m "${MEM}" \
    ${DISK_ARGS} \
    ${NET_ARGS} \
    -display none -vga none -serial stdio -monitor none -no-reboot > "${OUT}" 2>&1
status=${PIPESTATUS[1]}
set -e

cat "${OUT}" > "${BOOT_LOG}"
echo "    log:    ${BOOT_LOG}"

if [ "${status}" -ne 0 ] && [ "${status}" -ne 124 ]; then
    echo "RESULT: QEMU exited early with status ${status}" >&2
    exit 1
fi

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
check_milestone "login:" || ok=0
check_milestone "PONG" || ok=0
check_milestone "models" || ok=0
check_milestone "aios-developer-os" || ok=0

# Check curl output
if grep -q "CURL_FAILED" "${OUT}"; then
    echo "  [MISS] curl command failed (no daemon running)"
    ok=0
elif grep -q '"status":"ok"' "${OUT}"; then
    echo "  [OK]   curl to daemon works"
else
    echo "  [WARN] curl ran but unexpected output"
fi

if [ "${ok}" -eq 0 ]; then
    echo "RESULT: FAIL (some milestones not reached)" >&2
    exit 1
fi

echo "RESULT: PASS - TCP commands work in-guest"
exit 0