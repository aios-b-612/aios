#!/usr/bin/env bash
# Full stack integration test that runs inside the AIOS VM.
# This is executed via the platform test.sh mechanism.

set -euo pipefail

export AIOS_MODELS_DIR="/var/lib/ai/models"
export AIOS_REGISTRY="/var/lib/ai/registry.tsv"
export XDG_CONFIG_HOME="/tmp/aios-test"

mkdir -p "$AIOS_MODELS_DIR"
mkdir -p /tmp/ai-inference
mkdir -p "$XDG_CONFIG_HOME"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\033[31mFALHOU: %s\033[0m\n' "$1" >&2; return 1; }
ok() { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

# Create a minimal GGUF file for testing
create_test_gguf() {
    python3 -c "
import struct
magic = b'GGUF'
version = struct.pack('<I', 1)
tensor_count = struct.pack('<Q', 0)
metadata_kv_count = struct.pack('<Q', 0)
with open('/tmp/test-model.gguf', 'wb') as f:
    f.write(magic)
    f.write(version)
    f.write(tensor_count)
    f.write(metadata_kv_count)
" || return 1
}

step "1. Model lifecycle (ai CLI)"
create_test_gguf || fail "Failed to create test GGUF"

./ai inspect /tmp/test-model.gguf | grep -q "Format: GGUF" || fail "ai inspect failed"
ok "ai inspect works"

./ai verify /tmp/test-model.gguf | grep -q "sha256" || fail "ai verify failed"
ok "ai verify works"

./ai install /tmp/test-model.gguf test-model || fail "ai install failed"
ok "ai install works"

./ai list | grep -q "test-model" || fail "ai list failed"
ok "ai list works"

./ai info test-model | grep -q "Registered:  yes" || fail "ai info failed"
ok "ai info works"

./ai remove test-model || fail "ai remove failed"
ok "ai remove works"

step "2. Security policy (aios-security)"
MODEL="test-model-security"

./aios-security create-ai-model "$MODEL" || fail "create-ai-model failed"
ok "create-ai-model works"

./aios-security check "$MODEL" filesystem read --scope /var/lib/ai/models | grep -q "Decision: Allow" || fail "check allow failed"
ok "check allow works"

./aios-security check "$MODEL" filesystem read --scope /etc/shadow | grep -q "Decision: Deny" || fail "check deny failed"
ok "check deny works"

./aios-security authorize "$MODEL" filesystem read --scope /var/lib/ai/models | grep -q "ALLOWED" || fail "authorize failed"
ok "authorize works"

./aios-security contain-plan ai-model "$MODEL" | grep -q "rootfs: /var/lib/ai/models" || fail "contain-plan failed"
ok "contain-plan works"

./aios-security remove "$MODEL" || fail "security remove failed"
ok "Security policy works"

step "3. Deployment (aios-deploy)"
./aios-deploy --help | grep -q "deploy" || fail "aios-deploy help failed"
ok "aios-deploy CLI works"

./aios-deploy devices || fail "aios-deploy devices failed"
ok "Device registry works"

step "4. Edge CLI"
./edge --help | grep -q "ci-monitor" || fail "edge CLI missing ci-monitor"
ok "edge CLI works"

./edge ci-monitor --help | grep -q "ci-monitor" || fail "edge ci-monitor help failed"
ok "edge ci-monitor works"

step "5. Verify /etc/ai-platform marker"
cat /etc/ai-platform
grep -q "name = " /etc/ai-platform || fail "AI platform marker missing"
ok "AI platform marker present"

# Cleanup
rm -f /tmp/test-model.gguf

printf '\n\033[32m✓✓✓ ALL VM INTEGRATION TESTS PASSED ✓✓✓\033[0m\n'
exit 0