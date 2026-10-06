#!/usr/bin/env bash
# AIOS Complete VM Test Runner
# Run this INSIDE the VM after booting and logging in as 'user'
# Usage: curl -s https://raw.githubusercontent.com/aios/aios/main/scripts/aios-vm-run-all.sh | bash

set -euo pipefail

echo "=== AIOS Complete VM Validation ==="
echo "Building all binaries..."
echo

export AIOS_MODELS_DIR="/var/lib/ai/models"
export AIOS_REGISTRY="/var/lib/ai/registry.tsv"
export XDG_CONFIG_HOME="/tmp/aios-test"

mkdir -p "$AIOS_MODELS_DIR"
mkdir -p "$XDG_CONFIG_HOME"

cd /home/user

# Clone or update repo
if [ ! -d "aios" ]; then
    git clone https://github.com/aios/aios.git
fi
cd aios
git pull 2>/dev/null || true

echo "Building release binaries (5-10 minutes)..."
cargo build --release --bin ai --bin edge-ai --bin edge --bin aios-deploy --bin aios-security

# Install
sudo cp target/release/ai /usr/bin/
sudo cp target/release/edge-ai /usr/bin/
sudo cp target/release/edge /usr/bin/
sudo cp target/release/aios-deploy /usr/bin/
sudo cp target/release/aios-security /usr/bin/

echo
echo "=== Validation Tests ==="

# Test model lifecycle
python3 -c "
import struct
magic = b'GGUF'
version = struct.pack('<I', 1)
tensor_count = struct.pack('<Q', 0)
metadata_kv_count = struct.pack('<Q', 0)
with open('/tmp/test-model.gguf', 'wb') as f:
    f.write(magic + version + tensor_count + metadata_kv_count)
"

run_test() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "  ✅ $name: PASS"
        return 0
    else
        echo "  ❌ $name: FAIL"
        return 1
    fi
}

FAIL=0

run_test "ai inspect" "ai inspect /tmp/test-model.gguf | grep -q 'Format: GGUF'"
run_test "ai verify" "ai verify /tmp/test-model.gguf | grep -q sha256"
run_test "ai install" "ai install /tmp/test-model.gguf test-model"
run_test "ai list" "ai list | grep -q test-model"
run_test "ai info" "ai info test-model | grep -q 'Registered:  yes'"
run_test "ai remove" "ai remove test-model"

# Security tests
run_test "create-ai-model" "aios-security create-ai-model test"
run_test "check allow" "aios-security check test filesystem read --scope /var/lib/ai/models | grep -q 'Decision: Allow'"
run_test "check deny" "aios-security check test filesystem read --scope /etc/shadow | grep -q 'Decision: Deny'"
run_test "authorize" "aios-security authorize test filesystem read --scope /var/lib/ai/models | grep -q ALLOWED"
run_test "contain-plan" "aios-security contain-plan ai-model test | grep -q 'rootfs: /var/lib/ai/models'"
run_test "security remove" "aios-security remove test"

# Deploy
run_test "device registry" "aios-deploy devices"

# CI Monitor
run_test "ci-monitor CLI" "edge ci-monitor --help | grep -q ci-monitor"

# Edge daemon
edge-ai --host 127.0.0.1 --port 8989 &
DAEMON_PID=$!
sleep 3

run_test "health endpoint" "curl -s http://127.0.0.1:8989/api/health | grep -q '\"status\":\"ok\"'"
run_test "models endpoint" "curl -s http://127.0.0.1:8989/api/models | grep -q '\"count\":0'"
run_test "metrics endpoint" "curl -s http://127.0.0.1:8989/api/metrics | grep -q '\"system\"'"

kill $DAEMON_PID 2>/dev/null
wait $DAEMON_PID 2>/dev/null || true

# AI Tasks
run_test "task --list" "ai task --list | grep -q summarize"

# Cleanup
rm -f /tmp/test-model.gguf

echo
if [ $FAIL -eq 0 ]; then
    echo "✅✅✅ ALL TESTS PASSED - AIOS FULLY FUNCTIONAL IN VM! ✅✅✅"
    exit 0
else
    echo "❌ $FAIL TEST(S) FAILED"
    exit 1
fi
