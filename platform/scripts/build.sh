#!/usr/bin/env bash
# Build an AIOS image using the upstream Redox build system.
#
# Usage:
#   build.sh [-a ARCH] [-c CONFIG] [-f FILESYSTEM_CONFIG] [-n] [MAKE_TARGET ...]
#
#   -a ARCH       x86_64 (default), aarch64, i586, riscv64gc
#   -c CONFIG     ai-developer (default) | ai-edge
#   -f CONFIGFILE custom config path (defaults to config/<ARCH>/<CONFIG>.toml in this repo)
#   -n            native build mode (PODMAN_BUILD=0); otherwise auto: podman if available, else native
#   MAKE_TARGET   optional make targets (all | qemu | live | image | ...). Default: all
#
# Environment:
#   REDOX_SOURCE   path to the upstream redox tree (default: <platform>/../redox-os)
#   PODMAN_BUILD   1/0 force container/native build
#   PREFIX_BINARY  1/0 use prebuilt toolchain prefix (default 1)
#   REPO_BINARY    1/0 use binary packages (default 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE_DEFAULT="${PLATFORM_DIR}/../redox-os"
REDOX_SOURCE="${REDOX_SOURCE:-$(cd "${REDOX_SOURCE_DEFAULT}" 2>/dev/null && pwd || echo "${REDOX_SOURCE_DEFAULT}")}"

ARCH="${ARCH:-x86_64}"
CONFIG_NAME="${CONFIG_NAME:-ai-developer}"
FILESYSTEM_CONFIG=""
PREFIX_BINARY="${PREFIX_BINARY:-1}"
REPO_BINARY="${REPO_BINARY:-1}"

usage() {
    cat <<'EOF'
Build an AIOS image using the upstream Redox build system.

Usage:
  build.sh [-a ARCH] [-c CONFIG] [-f FILESYSTEM_CONFIG] [-n] [MAKE_TARGET ...]

  -a ARCH       x86_64 (default), aarch64, i586, riscv64gc
  -c CONFIG     ai-developer (default) | ai-edge
  -f CONFIGFILE custom config path (defaults to config/<ARCH>/<CONFIG>.toml)
  -n            native build mode (PODMAN_BUILD=0)
  MAKE_TARGET   optional make targets (all | qemu | live | image | ...). Default: all

Environment:
  REDOX_SOURCE   path to the upstream redox tree (default: ../redox-os)
  PODMAN_BUILD   1/0 force container/native build
  PREFIX_BINARY  1/0 use prebuilt toolchain prefix (default 1)
  REPO_BINARY    1/0 use binary packages (default 1)
EOF
}

while getopts ":a:c:f:nh" opt; do
    case "$opt" in
        a) ARCH="$OPTARG" ;;
        c) CONFIG_NAME="$OPTARG" ;;
        f) FILESYSTEM_CONFIG="$OPTARG" ;;
        n) PODMAN_BUILD=0 ;;
        h) usage; exit 0 ;;
        \?) echo "Unknown option -$OPTARG"; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$FILESYSTEM_CONFIG" ]; then
    FILESYSTEM_CONFIG="${PLATFORM_DIR}/config/${ARCH}/${CONFIG_NAME}.toml"
fi

if [ ! -f "$FILESYSTEM_CONFIG" ]; then
    echo "ERROR: filesystem config not found: ${FILESYSTEM_CONFIG}" >&2
    exit 1
fi

if [ ! -d "${REDOX_SOURCE}" ]; then
    echo "ERROR: upstream Redox tree not found at ${REDOX_SOURCE}" >&2
    echo "Set REDOX_SOURCE to the redox-os/redox checkout." >&2
    exit 1
fi

# If PODMAN_BUILD not forced (-n / env), auto-detect
if [ -z "${PODMAN_BUILD:-}" ]; then
    if command -v podman >/dev/null 2>&1; then
        PODMAN_BUILD=1
    else
        echo "info: podman not found; falling back to native build (PODMAN_BUILD=0)" >&2
        PODMAN_BUILD=0
    fi
fi

export ARCH
export CONFIG_NAME
export FILESYSTEM_CONFIG
export PODMAN_BUILD
export PREFIX_BINARY
export REPO_BINARY

echo "==> AIOS build"
echo "    type:     ${CONFIG_NAME} (${ARCH})"
echo "    config:   ${FILESYSTEM_CONFIG}"
echo "    source:   ${REDOX_SOURCE}"
echo "    podman:   ${PODMAN_BUILD}  prefix-bin: ${PREFIX_BINARY}  repo-bin: ${REPO_BINARY}"
echo "    targets:  ${*:-all}"

cd "${REDOX_SOURCE}"
exec ./build.sh -a "${ARCH}" -c "${CONFIG_NAME}" -f "${FILESYSTEM_CONFIG}" "$@"