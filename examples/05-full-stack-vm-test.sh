#!/usr/bin/env bash
# Full stack integration test for AIOS inside the VM.
# This script should be run INSIDE the Redox guest VM to test the complete stack.
#
# Usage from host:
#   # Copy to VM via serial or network, then run inside VM
#   # Or run via QEMU with a shared directory
#
# Tests:
#   1. Model lifecycle (ai CLI)
#   2. Edge daemon HTTP API
#   3. Security policy (aios-security)
#   4. CI monitor (edge ci-monitor)
#   5. Model deployment (edge deploy / aios-deploy)

set -euo pipefail

REPO_ROOT="/home/user/aios"
AIOS_MODELS_DIR="/var/lib/ai/models"
AIOS_REGISTRY="/var/lib/ai/registry.tsv"

export AIOS_MODELS_DIR
export AIOS_REGISTRY

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFALHOU: %s\033[0m\n' "$1" >&2; exit 1; }
ok() { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

# Check we're in the right environment
[[ -f "/etc/ai-platform" ]] || fail "Not running in AIOS VM (missing /etc/ai-platform)"
cat /etc/ai-platform
ok "Running in AIOS VM"

# Ensure model directory exists
mkdir -p "$AIOS_MODELS_DIR"
mkdir -p /tmp/ai-inference

step "1. Model lifecycle (ai CLI)"
cd "$REPO_ROOT"
# Create a minimal GGUF file for testing
python3 -c "
import struct
# Minimal GGUF v1 header
magic = b'GGUF'
version = struct.pack('<I', 1)
tensor_count = struct.pack('<Q', 0)
metadata_kv_count = struct.pack('<Q', 0)
with open('/tmp/test-model.gguf', 'wb') as f:
    f.write(magic)
    f.write(version)
    f.write(tensor_count)
    f.write(metadata_kv_count)
" || fail "Failed to create test GGUF"

# Test ai inspect
"$REPO_ROOT/target/release/ai" inspect /tmp/test-model.gguf | grep -q "Format: GGUF" || fail "ai inspect failed"
ok "ai inspect works"

# Test ai verify
"$REPO_ROOT/target/release/ai" verify /tmp/test-model.gguf | grep -q "sha256" || fail "ai verify failed"
ok "ai verify works"

# Test ai install
"$REPO_ROOT/target/release/ai" install /tmp/test-model.gguf test-model || fail "ai install failed"
ok "ai install works"

# Test ai list
"$REPO_ROOT/target/release/ai" list | grep -q "test-model" || fail "ai list failed"
ok "ai list works"

# Test ai info
"$REPO_ROOT/target/release/ai" info test-model | grep -q "Registered:  yes" || fail "ai info failed"
ok "ai info works"

# Test ai remove
"$REPO_ROOT/target/release/ai" remove test-model || fail "ai remove failed"
ok "ai remove works"

step "2. Edge daemon HTTP API"
# Start daemon in background
"$REPO_ROOT/target/release/edge-ai" --host 127.0.0.1 --port 8989 &
DAEMON_PID=$!
sleep 2

# Test health endpoint
curl -s http://127.0.0.1:8989/api/health | grep -q '"status":"ok"' || fail "Health endpoint failed"
ok "Health endpoint works"

# Test models endpoint
curl -s http://127.0.0.1:8989/api/models | grep -q '"count":0' || fail "Models endpoint failed"
ok "Models endpoint works"

# Install a model for inference tests
"$REPO_ROOT/target/release/ai" install /tmp/test-model.gguf test-model || fail "ai install for daemon test"

# Test metrics endpoint
curl -s http://127.0.0.1:8989/api/metrics | grep -q '"system"' || fail "Metrics endpoint failed"
ok "Metrics endpoint works"

# Test logs endpoint
curl -s http://127.0.0.1:8989/api/logs | grep -q '"logs"' || fail "Logs endpoint failed"
ok "Logs endpoint works"

# Stop daemon
kill $DAEMON_PID 2>/dev/null || true
wait $DAEMON_PID 2>/dev/null || true
ok "Daemon lifecycle works"

step "3. Security policy (aios-security)"
export XDG_CONFIG_HOME="/tmp/aios-security-test"
mkdir -p "$XDG_CONFIG_HOME"

MODEL="test-model-security"

"$REPO_ROOT/target/release/aios-security" create-ai-model "$MODEL" || fail "create-ai-model failed"
ok "create-ai-model works"

# Test check - allowed
"$REPO_ROOT/target/release/aios-security" check "$MODEL" filesystem read --scope /var/lib/ai/models | grep -q "Decision: Allow" || fail "check allow failed"
ok "check allow works"

# Test check - denied
"$REPO_ROOT/target/release/aios-security" check "$MODEL" filesystem read --scope /etc/shadow | grep -q "Decision: Deny" || fail "check deny failed"
ok "check deny works"

# Test authorize
"$REPO_ROOT/target/release/aios-security" authorize "$MODEL" filesystem read --scope /var/lib/ai/models | grep -q "ALLOWED" || fail "authorize failed"
ok "authorize works"

# Test contain-plan
"$REPO_ROOT/target/release/aios-security" contain-plan ai-model "$MODEL" | grep -q "rootfs: /var/lib/ai/models" || fail "contain-plan failed"
ok "contain-plan works"

# Cleanup
"$REPO_ROOT/target/release/aios-security" remove "$MODEL" || fail "security remove failed"
ok "Security policy works"

step "4. CI Monitor (edge ci-monitor)"
# Test with a mock endpoint - just test the CLI parsing
"$REPO_ROOT/target/release/edge" ci-monitor --help | grep -q "ci-monitor" || fail "ci-monitor help failed"
ok "CI monitor CLI works"

# Test with a simple local server (if available)
# Note: Full test requires a real CI endpoint

step "5. Deployment (edge deploy / aios-deploy)"
# Test aios-deploy CLI
"$REPO_ROOT/target/release/aios-deploy" --help | grep -q "deploy" || fail "aios-deploy help failed"
ok "aios-deploy CLI works"

# Test edge deploy CLI
"$REPO_ROOT/target/release/edge" deploy --help | grep -q "deploy" || fail "edge deploy help failed"
ok "edge deploy CLI works"

# Test device registry
"$REPO_ROOT/target/release/aios-deploy" devices || fail "aios-deploy devices failed"
ok "Device registry works"

step "6. Verify /etc/ai-platform marker"
cat /etc/ai-platform
grep -q "name = " /etc/ai-platform || fail "AI platform marker missing"
ok "AI platform marker present"

# Cleanup
rm -f /tmp/test-model.gguf

printf '\n\033[32m✓✓✓ ALL TESTS PASSED ✓✓✓\033[0m\n'
printf 'AIOS full stack is functional in the VM!\n'