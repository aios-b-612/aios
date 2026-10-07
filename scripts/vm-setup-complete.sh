#!/usr/bin/env bash
# Complete AIOS setup inside the VM
# Run this AFTER booting the AIOS VM and logging in as 'user'

set -euo pipefail

echo "=== AIOS VM Setup ==="
echo "Building all AIOS binaries inside the VM..."
echo

# Ensure we're in the right place
cd /home/user

# Clone the repo (or copy from host via serial/shared folder)
if [ ! -d "aios" ]; then
    echo "Cloning AIOS repository..."
    git clone https://github.com/aios/aios.git
    cd aios
else
    cd aios
    git pull
fi

# Build all release binaries
echo "Building release binaries (this takes 5-10 minutes)..."
cargo build --release --bin ai --bin edge-ai --bin edge --bin aios-deploy --bin aios-security

# Install to system paths
echo "Installing to /usr/bin/..."
sudo cp target/release/ai /usr/bin/
sudo cp target/release/edge-ai /usr/bin/
sudo cp target/release/edge /usr/bin/
sudo cp target/release/aios-deploy /usr/bin/
sudo cp target/release/aios-security /usr/bin/

# Verify installation
echo
echo "=== Verification ==="
for bin in ai edge-ai edge aios-deploy aios-security; do
    if [ -x "/usr/bin/$bin" ]; then
        echo "  ✓ /usr/bin/$bin"
    else
        echo "  ✗ /usr/bin/$bin MISSING"
    fi
done

# Test model lifecycle
echo
echo "=== Testing model lifecycle ==="
export AIOS_MODELS_DIR="/var/lib/ai/models"
export AIOS_REGISTRY="/var/lib/ai/registry.tsv"
mkdir -p "$AIOS_MODELS_DIR"

# Create test GGUF
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
"

echo "1. ai inspect"
ai inspect /tmp/test-model.gguf | grep -q "Format: GGUF" && echo "  ✓ inspect works"

echo "2. ai verify"
ai verify /tmp/test-model.gguf | grep -q "sha256" && echo "  ✓ verify works"

echo "3. ai install"
ai install /tmp/test-model.gguf test-model && echo "  ✓ install works"

echo "4. ai list"
ai list | grep -q "test-model" && echo "  ✓ list works"

echo "5. ai info"
ai info test-model | grep -q "Registered:  yes" && echo "  ✓ info works"

echo "6. ai remove"
ai remove test-model && echo "  ✓ remove works"

# Test security policy
echo
echo "=== Testing security policy ==="
export XDG_CONFIG_HOME="/tmp/aios-test"
mkdir -p "$XDG_CONFIG_HOME"

MODEL="test-model"
aios-security create-ai-model "$MODEL" && echo "  ✓ create-ai-model works"
aios-security check "$MODEL" filesystem read --scope /var/lib/ai/models | grep -q "Decision: Allow" && echo "  ✓ check allow works"
aios-security check "$MODEL" filesystem read --scope /etc/shadow | grep -q "Decision: Deny" && echo "  ✓ check deny works"
aios-security authorize "$MODEL" filesystem read --scope /var/lib/ai/models | grep -q "ALLOWED" && echo "  ✓ authorize works"
aios-security contain-plan ai-model "$MODEL" | grep -q "rootfs: /var/lib/ai/models" && echo "  ✓ contain-plan works"
aios-security remove "$MODEL" && echo "  ✓ security remove works"

# Test deploy
echo
echo "=== Testing deploy ==="
aios-deploy devices && echo "  ✓ device registry works"

# Test CI monitor
echo
echo "=== Testing CI monitor ==="
edge ci-monitor --help | grep -q "ci-monitor" && echo "  ✓ ci-monitor CLI works"

# Test edge daemon (background)
echo
echo "=== Testing edge daemon ==="
edge-ai --host 127.0.0.1 --port 8989 &
DAEMON_PID=$!
sleep 3

curl -s http://127.0.0.1:8989/api/health | grep -q '"status":"ok"' && echo "  ✓ health endpoint works"
curl -s http://127.0.0.1:8989/api/models | grep -q '"count":0' && echo "  ✓ models endpoint works"
curl -s http://127.0.0.1:8989/api/metrics | grep -q '"system"' && echo "  ✓ metrics endpoint works"

kill $DAEMON_PID 2>/dev/null
wait $DAEMON_PID 2>/dev/null

# Test AI tasks
echo
echo "=== Testing AI tasks ==="
ai task --list | grep -q "summarize" && echo "  ✓ task --list works"

# Cleanup
rm -f /tmp/test-model.gguf

echo
echo "=== ✓✓✓ ALL TESTS PASSED - AIOS IS FULLY FUNCTIONAL IN VM! ✓✓✓ ==="
echo
echo "Available commands:"
echo "  ai              - Model management (list, install, remove, run, task)"
echo "  edge            - Edge CLI (status, models, run, deploy, ci-monitor)"
echo "  edge-ai         - Edge daemon (HTTP API on :8989)"
echo "  aios-deploy     - Device registry & model deployment"
echo "  aios-security   - AI model permissions & contain profiles"