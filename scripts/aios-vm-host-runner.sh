#!/usr/bin/env bash
# AIOS VM Host Runner - EXACT match of test.sh for harddrive.img (SeaBIOS, NVMe)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_IMG="${REPO_ROOT}/redox-os/build/x86_64/ai-developer/harddrive.img"
TEST_IMG="/tmp/aios-vm-test.img"

echo "=== AIOS VM Host Runner (test.sh exact match) ==="
echo "VM Image: ${VM_IMG}"
echo

# Copy image to avoid lock
cp "${VM_IMG}" "${TEST_IMG}"

# EXACT test.sh config for harddrive.img (x86_64)
TIMEOUT_SECS=1800
LOGIN_DELAY=120  # test.sh uses 120 for live ISO, 40 for disk; use 120 for safety

QEMU_BIN="qemu-system-x86_64"

MACHINE="q35"
CPU="core2duo"
SMP=4
MEM=2048
# EXACT test.sh disk args for harddrive.img (NVMe)
DISK_ARGS="-drive file=${TEST_IMG},format=raw,if=none,id=drv0 -device nvme,drive=drv0,serial=NVME_SERIAL"
NET_ARGS="-device e1000,netdev=net0 -netdev user,id=net0"
# NO PFLASH for harddrive.img (SeaBIOS, not UEFI) - this is the key difference!
ACCEL_ARGS="-enable-kvm"

BOOT_LOG="/tmp/aios-vm-full.log"

echo "Starting VM (SeaBIOS, NVMe) with automated test sequence..."
echo "Timeout: ${TIMEOUT_SECS}s, Login delay: ${LOGIN_DELAY}s"
echo "Log: ${BOOT_LOG}"
echo

# Scripted stdin - EXACT test.sh pattern
(
    trap '' PIPE
    sleep "${LOGIN_DELAY}"
    printf 'user\n' || true
    sleep 3
    
    # Build and test sequence
    printf 'export AIOS_MODELS_DIR=/var/lib/ai/models\n' || true
    sleep 1
    printf 'export AIOS_REGISTRY=/var/lib/ai/registry.tsv\n' || true
    sleep 1
    printf 'export XDG_CONFIG_HOME=/tmp/aios-test\n' || true
    sleep 1
    printf 'mkdir -p $AIOS_MODELS_DIR\n' || true
    sleep 1
    printf 'mkdir -p $XDG_CONFIG_HOME\n' || true
    sleep 1
    
    printf 'cd /home/user\n' || true
    sleep 1
    printf 'git clone https://github.com/aios/aios.git 2>/dev/null || cd aios && git pull\n' || true
    sleep 5
    printf 'cd aios\n' || true
    sleep 1
    
    printf 'echo "Building binaries (5-10 min)..."\n' || true
    sleep 1
    printf 'cargo build --release --bin ai --bin edge-ai --bin edge --bin aios-deploy --bin aios-security\n' || true
    sleep 600
    
    printf 'sudo cp target/release/ai /usr/bin/\n' || true
    sleep 2
    printf 'sudo cp target/release/edge-ai /usr/bin/\n' || true
    sleep 2
    printf 'sudo cp target/release/edge /usr/bin/\n' || true
    sleep 2
    printf 'sudo cp target/release/aios-deploy /usr/bin/\n' || true
    sleep 2
    printf 'sudo cp target/release/aios-security /usr/bin/\n' || true
    sleep 2
    
    # Validation tests
    printf 'python3 -c "import struct; magic=b\\"GGUF\\"; version=struct.pack(\\"<I\\",1); tc=struct.pack(\\"<Q\\",0); mk=struct.pack(\\"<Q\\",0); open(\\"/tmp/test-model.gguf\\",\\"wb\\").write(magic+version+tc+mk)"\n' || true
    sleep 2
    
    printf 'ai inspect /tmp/test-model.gguf | grep -q "Format: GGUF" && echo "PASS: ai inspect" || echo "FAIL: ai inspect"\n' || true
    sleep 2
    printf 'ai verify /tmp/test-model.gguf | grep -q sha256 && echo "PASS: ai verify" || echo "FAIL: ai verify"\n' || true
    sleep 2
    printf 'ai install /tmp/test-model.gguf test-model && echo "PASS: ai install" || echo "FAIL: ai install"\n' || true
    sleep 2
    printf 'ai list | grep -q test-model && echo "PASS: ai list" || echo "FAIL: ai list"\n' || true
    sleep 2
    printf 'ai info test-model | grep -q "Registered:  yes" && echo "PASS: ai info" || echo "FAIL: ai info"\n' || true
    sleep 2
    printf 'ai remove test-model && echo "PASS: ai remove" || echo "FAIL: ai remove"\n' || true
    sleep 2
    
    printf 'export XDG_CONFIG_HOME=/tmp/aios-test\n' || true
    sleep 1
    printf 'mkdir -p $XDG_CONFIG_HOME\n' || true
    sleep 1
    printf 'aios-security create-ai-model test && echo "PASS: create-ai-model" || echo "FAIL: create-ai-model"\n' || true
    sleep 2
    printf 'aios-security check test filesystem read --scope /var/lib/ai/models | grep -q "Decision: Allow" && echo "PASS: check allow" || echo "FAIL: check allow"\n' || true
    sleep 2
    printf 'aios-security check test filesystem read --scope /etc/shadow | grep -q "Decision: Deny" && echo "PASS: check deny" || echo "FAIL: check deny"\n' || true
    sleep 2
    printf 'aios-security authorize test filesystem read --scope /var/lib/ai/models | grep -q ALLOWED && echo "PASS: authorize" || echo "FAIL: authorize"\n' || true
    sleep 2
    printf 'aios-security contain-plan ai-model test | grep -q "rootfs: /var/lib/ai/models" && echo "PASS: contain-plan" || echo "FAIL: contain-plan"\n' || true
    sleep 2
    printf 'aios-security remove test && echo "PASS: security remove" || echo "FAIL: security remove"\n' || true
    sleep 2
    
    printf 'aios-deploy devices && echo "PASS: device registry" || echo "FAIL: device registry"\n' || true
    sleep 2
    
    printf 'edge ci-monitor --help | grep -q ci-monitor && echo "PASS: ci-monitor CLI" || echo "FAIL: ci-monitor CLI"\n' || true
    sleep 2
    
    printf 'edge-ai --host 127.0.0.1 --port 8989 &\n' || true
    sleep 5
    
    printf 'curl -s http://127.0.0.1:8989/api/health | grep -q "\\"status\\":\\"ok\\"" && echo "PASS: health endpoint" || echo "FAIL: health endpoint"\n' || true
    sleep 2
    printf 'curl -s http://127.0.0.1:8989/api/models | grep -q "\\"count\\":0" && echo "PASS: models endpoint" || echo "FAIL: models endpoint"\n' || true
    sleep 2
    printf 'curl -s http://127.0.0.1:8989/api/metrics | grep -q "\\"system\\"" && echo "PASS: metrics endpoint" || echo "FAIL: metrics endpoint"\n' || true
    sleep 2
    
    printf 'pkill edge-ai\n' || true
    sleep 2
    
    printf 'ai task --list | grep -q summarize && echo "PASS: task --list" || echo "FAIL: task --list"\n' || true
    sleep 2
    
    printf 'rm -f /tmp/test-model.gguf\n' || true
    sleep 1
    
    printf 'echo "ALL_TESTS_COMPLETED"\n' || true
    sleep 1
    printf 'exit\n' || true
    sleep 2
    
) 2>/dev/null | timeout --foreground 1800 qemu-system-x86_64 \
    -enable-kvm \
    -machine q35 -cpu core2duo -smp 4 -m 2048 \
    -drive file=/tmp/aios-vm-test.img,format=raw,if=none,id=drv0 -device nvme,drive=drv0,serial=NVME_SERIAL \
    -device e1000,netdev=net0 -netdev user,id=net0 \
    -display none -vga none -serial stdio -monitor none -no-reboot > /tmp/aios-vm-full.log 2>&1

status=${PIPESTATUS[1]}

echo
echo "=== Results ==="
if grep -q "ALL_TESTS_COMPLETED" /tmp/aios-vm-full.log; then
    echo "✅ ALL TESTS COMPLETED"
    grep -E "(PASS|FAIL)" /tmp/aios-vm-full.log | head -30
    exit 0
else
    echo "❌ Tests incomplete or failed"
    echo "Check /tmp/aios-vm-full.log for details"
    tail -50 /tmp/aios-vm-full.log
    exit 1
fi
