#!/usr/bin/env bash
# Copy AIOS binaries to the VM image for integration testing.
# Run this AFTER building the image with `make -C platform build`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_DIR="${REPO_ROOT}/platform"
VM_IMG="${PLATFORM_DIR}/../redox-os/build/x86_64/ai-developer/harddrive.img"
MOUNT_POINT="/mnt/aios-vm"

BINARIES=(
    "target/release/ai"
    "target/release/edge-ai"
    "target/release/edge"
    "target/release/aios-deploy"
    "target/release/aios-security"
)

INTEGRATION_TEST="${REPO_ROOT}/examples/05-full-stack-vm-test.sh"
VM_TEST_SCRIPT="${PLATFORM_DIR}/scripts/vm-integration-test.sh"

echo "==> Copying AIOS binaries to VM image"
echo "    Image: ${VM_IMG}"
echo "    Mount: ${MOUNT_POINT}"

# Check image exists
[[ -f "${VM_IMG}" ]] || { echo "ERROR: VM image not found at ${VM_IMG}"; exit 1; }

# Create mount point
sudo mkdir -p "${MOUNT_POINT}"

# Check if already mounted
if mountpoint -q "${MOUNT_POINT}"; then
    echo "    Unmounting previous mount..."
    sudo umount "${MOUNT_POINT}"
fi

# Mount the image (RedoxFS)
echo "    Mounting image..."
sudo mount -t redoxfs "${VM_IMG}" "${MOUNT_POINT}" || {
    echo "ERROR: Failed to mount RedoxFS image. Trying loop device..."
    # Try with loop device
    LOOP_DEV=$(sudo losetup -f --show "${VM_IMG}")
    echo "    Loop device: ${LOOP_DEV}"
    sudo mount -t redoxfs "${LOOP_DEV}" "${MOUNT_POINT}" || {
        echo "ERROR: Cannot mount image"
        sudo losetup -d "${LOOP_DEV}" 2>/dev/null || true
        exit 1
    }
}

# Copy binaries
echo "    Copying binaries to /usr/bin/ in VM..."
for bin in "${BINARIES[@]}"; do
    src="${REPO_ROOT}/${bin}"
    if [[ -f "${src}" ]]; then
        sudo cp "${src}" "${MOUNT_POINT}/usr/bin/"
        echo "      $(basename "${bin}")"
    else
        echo "WARNING: ${src} not found, skipping"
    fi
done

# Copy integration test script
echo "    Copying integration test script..."
sudo cp "${VM_TEST_SCRIPT}" "${MOUNT_POINT}/home/user/vm-integration-test.sh"
sudo chmod +x "${MOUNT_POINT}/home/user/vm-integration-test.sh"

# Also copy the test script to a location accessible from the VM
sudo cp "${INTEGRATION_TEST}" "${MOUNT_POINT}/home/user/full-stack-vm-test.sh"
sudo chmod +x "${MOUNT_POINT}/home/user/full-stack-vm-test.sh"

# Create a simple runner script
sudo tee "${MOUNT_POINT}/home/user/run-tests.sh" > /dev/null <<'EOF'
#!/bin/sh
export AIOS_MODELS_DIR="/var/lib/ai/models"
export AIOS_REGISTRY="/var/lib/ai/registry.tsv"
export XDG_CONFIG_HOME="/tmp/aios-test"

mkdir -p "$AIOS_MODELS_DIR"
mkdir -p /tmp/ai-inference
mkdir -p "$XDG_CONFIG_HOME"

cd /home/user
./vm-integration-test.sh
EOF
sudo chmod +x "${MOUNT_POINT}/home/user/run-tests.sh"

# Unmount
echo "    Unmounting..."
sudo umount "${MOUNT_POINT}"

# Cleanup loop device if used
if [[ -n "${LOOP_DEV:-}" ]]; then
    sudo losetup -d "${LOOP_DEV}"
fi

echo "==> Done! Binaries copied to VM image."
echo "    Run the VM and execute: /home/user/run-tests.sh"