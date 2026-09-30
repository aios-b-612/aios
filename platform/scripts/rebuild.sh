#!/usr/bin/env bash
# Force a full re-cook of the base package, then build an image.
#
# WHY THIS EXISTS
#
# Editing sources under `redox-os/recipes/core/base/source/` and re-running
# build.sh does NOT reliably rebuild the image. Three separate caches each
# cause a silent stale build, and all three have to be cleared:
#
#   1. repo/<arch>/base.pkgar -- the prebuilt package. The installer extracts
#      it instead of cooking, even with REPO_BINARY=0, so the patch never
#      reaches the image.
#   2. build/<arch>/<config>/repo.tag -- gates `make cook`. Present, make
#      skips cooking entirely and just prints "Extracting base".
#   3. Per-recipe source_info.toml stamps written before the edit. These force
#      downstream packages to rebuild, and some of them call autopoint, which
#      needs gettext that is usually not installed on the host.
#
# The failure mode is nasty because it looks like success: a normal-looking
# build log, a bootable image, and a driver that is quietly the old one. A 6/6
# stability result was once mistaken for "the fix works" when it was in fact
# measured on a stale image.
#
# Usage:
#   rebuild.sh [-a ARCH] [-c CONFIG] [MAKE_TARGET ...]
#
# Defaults match build.sh: x86_64 / ai-developer.
#
# Environment:
#   REDOX_SOURCE  upstream redox tree (default <platform>/../redox-os)
#   KEEP_PKGAR    1 to back up base.pkgar instead of deleting it (default 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE_DEFAULT="${PLATFORM_DIR}/../redox-os"
REDOX_SOURCE="${REDOX_SOURCE:-$(cd "${REDOX_SOURCE_DEFAULT}" 2>/dev/null && pwd || echo "${REDOX_SOURCE_DEFAULT}")}"

ARCH="${ARCH:-x86_64}"
CONFIG_NAME="${CONFIG_NAME:-ai-developer}"
KEEP_PKGAR="${KEEP_PKGAR:-1}"
FILESYSTEM_CONFIG=""

while getopts ":a:c:f:h" opt; do
    case "$opt" in
        a) ARCH="$OPTARG" ;;
        c) CONFIG_NAME="$OPTARG" ;;
        f) FILESYSTEM_CONFIG="$OPTARG" ;;
        h) echo "Usage: rebuild.sh [-a ARCH] [-c CONFIG] [MAKE_TARGET ...]"; exit 0 ;;
        \?) echo "Unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

[ -d "${REDOX_SOURCE}" ] || { echo "ERROR: redox tree not found at ${REDOX_SOURCE}" >&2; exit 1; }

BUILD_ARGS=(-a "${ARCH}" -c "${CONFIG_NAME}" -n)
[ -n "${FILESYSTEM_CONFIG}" ] && BUILD_ARGS+=(-f "${FILESYSTEM_CONFIG}")
BUILD_ARGS+=("$@")

echo "==> Invalidating base caches for ${ARCH}/${CONFIG_NAME}"

# 1. the prebuilt package the installer would otherwise extract
PKGAR="${REDOX_SOURCE}/repo/${ARCH}-unknown-redox/base.pkgar"
if [ -f "${PKGAR}" ]; then
    if [ "${KEEP_PKGAR}" = "1" ]; then
        BAK="${PKGAR}.$(date +%Y%m%d-%H%M%S).bak"
        mv "${PKGAR}" "${BAK}"
        echo "    base.pkgar -> ${BAK##*/}"
    else
        rm -f "${PKGAR}"
        echo "    removed base.pkgar"
    fi
else
    echo "    no base.pkgar present (already clean)"
fi

# 2. the cook gate
REPO_TAG="${REDOX_SOURCE}/build/${ARCH}/${CONFIG_NAME}/repo.tag"
if [ -f "${REPO_TAG}" ]; then
    rm -f "${REPO_TAG}"
    echo "    removed repo.tag (forces make cook)"
fi

# 3. the stamp that makes downstream packages rebuild, plus any source.tmp
#    left behind by an interrupted build.
stale_stamps=0
while IFS= read -r stamp; do
    rm -f "${stamp}"
    stale_stamps=$((stale_stamps + 1))
done < <(find "${REDOX_SOURCE}/recipes" -path "*/target/${ARCH}-unknown-redox/source_info.toml" 2>/dev/null)
[ "${stale_stamps}" -gt 0 ] && echo "    removed ${stale_stamps} source_info.toml stamp(s)"

find "${REDOX_SOURCE}/recipes" -maxdepth 4 -name "source.tmp" -type d 2>/dev/null | while read -r tmp; do
    rm -rf "${tmp}"
    echo "    removed stale ${tmp#"${REDOX_SOURCE}/"}"
done

# autopoint, without root. The cross-compiled copy in the tree is a shell
# script and does run on the host, but it looks for its data under
# /usr/share/gettext, which is not installed. Exporting gettext_datadir to the
# tree's own copy is enough for autoreconf to get past it.
# The shim lives under the already-ignored /tmp so the repo stays clean.
HOST_TOOLS="${HOST_TOOLS:-/tmp/aios-host-tools}"
if ! command -v autopoint >/dev/null 2>&1; then
    for candidate in x86_64 i586; do
        GT_BIN="${REDOX_SOURCE}/recipes/tools/gettext/target/${candidate}-unknown-redox/stage/usr/bin/autopoint"
        GT_DATA="${REDOX_SOURCE}/recipes/tools/gettext/target/${candidate}-unknown-redox/stage/usr/share/gettext"
        if [ -x "${GT_BIN}" ] && [ -d "${GT_DATA}" ]; then
            mkdir -p "${HOST_TOOLS}"
            cat > "${HOST_TOOLS}/autopoint" <<EOF
#!/bin/sh
gettext_datadir="${GT_DATA}"
export gettext_datadir
exec "${GT_BIN}" "\$@"
EOF
            chmod +x "${HOST_TOOLS}/autopoint"
            echo "    shimmed autopoint -> ${GT_BIN##*/}"
            break
        fi
    done
fi

export PATH="${HOST_TOOLS}:${PATH}"
# REPO_BINARY=0 so the cook actually builds instead of fetching prebuilts.
export REPO_BINARY=0

echo "==> Building (REPO_BINARY=0, this recompiles base)"
"${SCRIPT_DIR}/build.sh" "${BUILD_ARGS[@]}"

# Report whether the driver binary is actually newer than the build, so a
# stale result cannot be mistaken for a fresh one again.
DRIVER="${REDOX_SOURCE}/recipes/core/base/target/${ARCH}-unknown-redox/build/initfs/lib/drivers/nvmed"
if [ -f "${DRIVER}" ]; then
    echo
    echo "    nvmed built at: $(date -r "${DRIVER}" '+%Y-%m-%d %H:%M:%S')"
    echo "    image:          ${REDOX_SOURCE}/build/${ARCH}/${CONFIG_NAME}/harddrive.img"
else
    echo "WARNING: nvmed binary not found at ${DRIVER}" >&2
fi
