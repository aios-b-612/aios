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
        # The profiles in config/ include upstream's config/server.toml by a
        # path relative to the config's own directory. In podman mode the
        # build runs inside a container that mounts only the upstream tree, so
        # that include escapes the mount and the build fails. The native path
        # reads the config straight off the host and is the only mode these
        # images have actually been built in.
        # See docs/gotchas/podman-build-unvalidated.md.
        echo "WARNING: podman detected, so this will use the podman build path," >&2
        echo "         which is UNVALIDATED for the AIOS profiles. If the build" >&2
        echo "         fails on a missing config/server.toml, rerun with -n." >&2
    else
        echo "info: podman not found; falling back to native build (PODMAN_BUILD=0)" >&2
        PODMAN_BUILD=0
    fi
fi

export ARCH
export CONFIG_NAME
export PODMAN_BUILD
export PREFIX_BINARY
export REPO_BINARY

# `repo cook` draws a TUI unless CI is set, and the TUI has no headless
# fallback: with no TTY, into_raw_mode() fails the ioctl, and even given a
# pty it underflows on an empty log buffer. Upstream documents CI=1 as the way
# to disable it (see `repo cook --help`), so set it whenever there is no
# terminal to draw on. Building interactively is still possible with
# AIOS_TUI=1.
if [ -t 1 ] && [ "${AIOS_TUI:-0}" = "1" ]; then
    echo "    tui:     enabled (AIOS_TUI=1)"
else
    export CI=1
    echo "    tui:     disabled (CI=1)"
fi

# In podman mode the Redox build runs the sysroot step inside a container that
# mounts only the upstream tree, as /mnt/redox. A host path under platform/ is
# therefore invisible in there, and the build dies with a bare "No such file or
# directory" on our config. Stage the config inside the mounted tree and pass
# the in-container path instead.
#
# The container workdir is Redox's, not ours, so it is overridable.
PODMAN_WORKDIR="${PODMAN_WORKDIR:-/mnt/redox}"
if [ "${PODMAN_BUILD}" = "1" ]; then
    STAGE_DIR="${REDOX_SOURCE}/aios-config"
    mkdir -p "${STAGE_DIR}"
    STAGED_CONFIG="${STAGE_DIR}/$(basename "${FILESYSTEM_CONFIG}")"
    cp "${FILESYSTEM_CONFIG}" "${STAGED_CONFIG}"
    CONTAINER_CONFIG="${PODMAN_WORKDIR}/aios-config/$(basename "${STAGED_CONFIG}")"
    echo "    staged:   ${CONTAINER_CONFIG}"
else
    CONTAINER_CONFIG="${FILESYSTEM_CONFIG}"
fi
export FILESYSTEM_CONFIG="${CONTAINER_CONFIG}"

# Overlay the platform patches onto the cookbook recipe before the build. The
# aarch64 image needs the nvmed poll-mode/fence fix; without it the block
# driver never reaps completions and the image hangs before login:.
#
# This runs here rather than inside the container because in podman mode only
# REDOX_SOURCE is mounted: the script and platform/patches/ are host-side, so
# the overlay has to be materialised into the mounted tree, which is exactly
# what apply-patches.sh writes.
echo "==> platform patches"
REDOX_ARCH="${ARCH}" "${SCRIPT_DIR}/apply-patches.sh"

echo "==> AIOS build"
echo "    type:     ${CONFIG_NAME} (${ARCH})"
echo "    config:   ${FILESYSTEM_CONFIG}"
echo "    source:   ${REDOX_SOURCE}"
echo "    podman:   ${PODMAN_BUILD}  prefix-bin: ${PREFIX_BINARY}  repo-bin: ${REPO_BINARY}"
echo "    targets:  ${*:-all}"

cd "${REDOX_SOURCE}"
exec ./build.sh -a "${ARCH}" -c "${CONFIG_NAME}" -f "${FILESYSTEM_CONFIG}" "$@"