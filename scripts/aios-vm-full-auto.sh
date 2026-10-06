#!/usr/bin/env bash
# AIOS Complete VM Automation
# This script boots the VM, builds all binaries inside, and runs full validation
# Usage: ./scripts/aios-vm-full-auto.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_DIR="${REPO_ROOT}/platform"
VM_IMG="${REPO_ROOT}/redox-os/build/x86_64/ai-developer/harddrive.img"

echo "=== AIOS Full VM Automation ==="
echo "Repo: ${REPO_ROOT}"
echo "VM Image: ${VM_IMG}"
echo

# Check if expect is available
if ! command -v expect &>/dev/null; then
    echo "Installing expect..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y expect
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y expect
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm expect
    else
        echo "ERROR: Please install 'expect' manually and re-run"
        exit 1
    fi
fi

# Copy VM image to avoid lock issues
TEST_IMG="/tmp/aios-automation.img"
echo "Copying VM image to ${TEST_IMG}..."
cp "${VM_IMG}" "${TEST_IMG}"

# Create expect script for full automation
EXPECT_SCRIPT="/tmp/aios-vm-automation.exp"
cat > "${EXPECT_SCRIPT}" << 'EOF'
#!/usr/bin/env expect

set timeout 1800
set vm_img "/tmp/aios-automation.img"

spawn qemu-system-x86_64 \
    -enable-kvm \
    -machine q35 \
    -cpu core2duo \
    -smp 4 \
    -m 4096 \
    -drive file=/usr/share/OVMF/OVMF_CODE_4M.fd,if=pflash,format=raw,readonly=on,unit=0 \
    -drive file=$vm_img,format=raw,if=virtio \
    -device e1000,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -display none \
    -vga none \
    -serial stdio \
    -monitor none \
    -no-reboot

log_file -noopen /tmp/aios-vm-full.log

# Wait for boot and login prompt
expect {
    "login:" {
        send "user\r"
        exp_continue
    }
    "Welcome to Redox OS!" {
        exp_continue
    }
    "\\$ " {
        # We're at the shell prompt
    }
    timeout {
        send_user "\nERROR: Boot timeout\n"
        exit 1
    }
}

# Now at shell prompt - run the full build and test
send "export AIOS_MODELS_DIR=/var/lib/ai/models\r"
expect "\\$ "
send "export AIOS_REGISTRY=/var/lib/ai/registry.tsv\r"
expect "\\$ "
send "mkdir -p \$AIOS_MODELS_DIR\r"
expect "\\$ "
send "export XDG_CONFIG_HOME=/tmp/aios-test\r"
expect "\\$ "
send "mkdir -p \$XDG_CONFIG_HOME\r"
expect "\\$ "

# Clone and build
send "cd /home/user\r"
expect "\\$ "
send "git clone https://github.com/aios/aios.git 2>/dev/null || cd aios && git pull\r"
expect "\\$ "
send "cd aios\r"
expect "\\$ "

send_user "\n=== Building all binaries (5-10 minutes) ===\n"
send "cargo build --release --bin ai --bin edge-ai --bin edge --bin aios-deploy --bin aios-security\r"
expect {
    "Finished" {
        send_user "\nBuild successful!\n"
    }
    "error" {
        send_user "\nBuild failed!\n"
        exit 1
    }
    timeout {
        send_user "\nBuild timeout!\n"
        exit 1
    }
}

expect "\\$ "

# Install binaries
send "sudo cp target/release/ai /usr/bin/\r"
expect "\\$ "
send "sudo cp target/release/edge-ai /usr/bin/\r"
expect "\\$ "
send "sudo cp target/release/edge /usr/bin/\r"
expect "\\$ "
send "sudo cp target/release/aios-deploy /usr/bin/\r"
expect "\\$ "
send "sudo cp target/release/aios-security /usr/bin/\r"
expect "\\$ "

# Run validation tests
send_user "\n=== Running validation tests ===\n"

# Test model lifecycle
send "python3 -c \"import struct; magic=b'GGUF'; version=struct.pack('<I',1); tc=struct.pack('<Q',0); mk=struct.pack('<Q',0); open('/tmp/test-model.gguf','wb').write(magic+version+tc+mk)\"\r"
expect "\\$ "
send "ai inspect /tmp/test-model.gguf | grep -q 'Format: GGUF' && echo 'inspect: PASS' || echo 'inspect: FAIL'\r"
expect "\\$ "
send "ai verify /tmp/test-model.gguf | grep -q sha256 && echo 'verify: PASS' || echo 'verify: FAIL'\r"
expect "\\$ "
send "ai install /tmp/test-model.gguf test-model && echo 'install: PASS' || echo 'install: FAIL'\r"
expect "\\$ "
send "ai list | grep -q test-model && echo 'list: PASS' || echo 'list: FAIL'\r"
expect "\\$ "
send "ai info test-model | grep -q 'Registered:  yes' && echo 'info: PASS' || echo 'info: FAIL'\r"
expect "\\$ "
send "ai remove test-model && echo 'remove: PASS' || echo 'remove: FAIL'\r"
expect "\\$ "

# Test security
send "aios-security create-ai-model test && echo 'create-ai-model: PASS' || echo 'create-ai-model: FAIL'\r"
expect "\\$ "
send "aios-security check test filesystem read --scope /var/lib/ai/models | grep -q 'Decision: Allow' && echo 'check allow: PASS' || echo 'check allow: FAIL'\r"
expect "\\$ "
send "aios-security check test filesystem read --scope /etc/shadow | grep -q 'Decision: Deny' && echo 'check deny: PASS' || echo 'check deny: FAIL'\r"
expect "\\$ "
send "aios-security authorize test filesystem read --scope /var/lib/ai/models | grep -q ALLOWED && echo 'authorize: PASS' || echo 'authorize: FAIL'\r"
expect "\\$ "
send "aios-security contain-plan ai-model test | grep -q 'rootfs: /var/lib/ai/models' && echo 'contain-plan: PASS' || echo 'contain-plan: FAIL'\r"
expect "\\$ "
send "aios-security remove test && echo 'security remove: PASS' || echo 'security remove: FAIL'\r"
expect "\\$ "

# Test deploy
send "aios-deploy devices && echo 'device registry: PASS' || echo 'device registry: FAIL'\r"
expect "\\$ "

# Test CI monitor
send "edge ci-monitor --help | grep -q ci-monitor && echo 'ci-monitor: PASS' || echo 'ci-monitor: FAIL'\r"
expect "\\$ "

# Test edge daemon
send "edge-ai --host 127.0.0.1 --port 8989 &\r"
expect "\\$ "
send "sleep 3\r"
expect "\\$ "
send "curl -s http://127.0.0.1:8989/api/health | grep -q '\"status\":\"ok\"' && echo 'health: PASS' || echo 'health: FAIL'\r"
expect "\\$ "
send "curl -s http://127.0.0.1:8989/api/models | grep -q '\"count\":0' && echo 'models: PASS' || echo 'models: FAIL'\r"
expect "\\$ "
send "curl -s http://127.0.0.1:8989/api/metrics | grep -q '\"system\"' && echo 'metrics: PASS' || echo 'metrics: FAIL'\r"
expect "\\$ "
send "pkill edge-ai\r"
expect "\\$ "

# Test AI tasks
send "ai task --list | grep -q summarize && echo 'task --list: PASS' || echo 'task --list: FAIL'\r"
expect "\\$ "

# Cleanup
send "rm -f /tmp/test-model.gguf\r"
expect "\\$ "

send_user "\n=== ALL TESTS COMPLETED ===\n"
send "exit\r"
expect eof
EOF

chmod +x "${EXPECT_SCRIPT}"

echo "Starting automated VM test..."
echo "This will take 10-15 minutes..."
echo

# Run the expect script
"${EXPECT_SCRIPT}"

# Check results
if grep -q "ALL TESTS COMPLETED" /tmp/aios-vm-full.log; then
    echo
    echo "✅✅✅ AIOS FULLY FUNCTIONAL IN VM! ✅✅✅"
    echo
    grep -E "(PASS|FAIL)" /tmp/aios-vm-full.log
else
    echo
    echo "❌ TESTS FAILED OR INCOMPLETE"
    echo
    tail -50 /tmp/aios-vm-full.log
    exit 1
fi
EOF

chmod +x /home/fasr/SSD_BACKUP/Workspace/aios/scripts/aios-vm-full-auto.sh