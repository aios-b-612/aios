#!/usr/bin/env bash
# Produce reproducible AIOS release artifacts.
#
# Collects the built images of every profile together with checksums and a
# provenance manifest, so a given release can be traced back to the exact
# upstream revision, kernel package and aios commit that produced it.
#
# Reproducibility here means: the same aios commit + the same upstream.lock
# pin selects the same upstream sources and the same image content. It does
# NOT mean bit-identical images across hosts -- the upstream build embeds
# timestamps and build paths, so only the checksums and manifest are
# reproducible. See docs/REPRODUCIBILITY.md.
#
# Usage:
#   release.sh [--build] [--test] [--out DIR]
#
#   --build     build any profile whose image is missing (slow: downloads GBs)
#   --test      run the QEMU boot smoke-test for every profile before collecting
#   --out DIR   output directory (default: <platform>/dist)
#
# Environment:
#   REDOX_SOURCE  upstream redox tree (default <platform>/../redox-os)
#   DIST          output directory (same as --out)
#   PROFILES      space-separated list (default: "x86_64/ai-developer aarch64/ai-edge")

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REDOX_SOURCE="${REDOX_SOURCE:-${PLATFORM_DIR}/../redox-os}"
AIOS_DIR="$(cd "${PLATFORM_DIR}/.." && pwd)"

DIST="${DIST:-${PLATFORM_DIR}/dist}"
PROFILES="${PROFILES:-x86_64/ai-developer aarch64/ai-edge}"
DO_BUILD=0
DO_TEST=0

usage() {
    cat <<'EOF'
Produce reproducible AIOS release artifacts.

Usage: release.sh [--build] [--test] [--out DIR]

  --build   build any profile whose image is missing
  --test    run the QEMU boot smoke-test before collecting
  --out DIR output directory (default: <platform>/dist)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --build) DO_BUILD=1 ;;
        --test) DO_TEST=1 ;;
        --out)
            [ $# -ge 2 ] || { echo "ERROR: --out needs a directory" >&2; exit 1; }
            DIST="$2"
            shift
            ;;
        --out=*) DIST="${1#--out=}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option $1" >&2; usage; exit 1 ;;
    esac
    shift
done

log() { echo "  $*"; }

# The release is only meaningful against the pinned upstream revision.
echo "==> AIOS release"
REDOX_SOURCE="${REDOX_SOURCE}" "${SCRIPT_DIR}/bootstrap.sh" --verify

# Provenance inputs.
UPSTREAM_COMMIT="$(git -C "${REDOX_SOURCE}" rev-parse HEAD)"
UPSTREAM_DATE="$(git -C "${AIOS_DIR}" log -1 --format=%cI)"
AIOS_COMMIT="$(git -C "${AIOS_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
AIOS_REF="$(git -C "${AIOS_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "${AIOS_DIR}" status --porcelain 2>/dev/null)" ]; then
    AIOS_DIRTY="yes"
else
    AIOS_DIRTY="no"
fi

rm -rf "${DIST}"
mkdir -p "${DIST}"

MANIFEST="${DIST}/MANIFEST.txt"
{
    echo "# AIOS release manifest"
    echo "aios_commit = ${AIOS_COMMIT}"
    echo "aios_ref = ${AIOS_REF}"
    echo "aios_dirty_worktree = ${AIOS_DIRTY}"
    echo "aios_commit_date = ${UPSTREAM_DATE}"
    echo "upstream_repo = https://github.com/redox-os/redox.git"
    echo "upstream_commit = ${UPSTREAM_COMMIT}"
} > "${MANIFEST}"

# Record which kernel package each profile was actually built against. The
# kernel is a prebuilt package from the Redox repository (see
# recipes/core/kernel/recipe.toml), so this is the only way to tell whether an
# image carries a locally patched kernel.
kernel_provenance() {
    local arch="$1"
    local info="${REDOX_SOURCE}/recipes/core/kernel/target/${arch}-unknown-redox/source_info.toml"
    if [ -f "${info}" ]; then
        sed -n 's/^[[:space:]]*\(source_identifier\|commit_identifier\|time_identifier\)[[:space:]]*=[[:space:]]*"\(.*\)"$/\1 = \2/p' "${info}"
    else
        echo "kernel_source_identifier = unknown"
        echo "kernel_time_identifier = unknown"
    fi
}

release_failed=0

for profile in ${PROFILES}; do
    arch="${profile%%/*}"
    config="${profile##*/}"
    build_dir="${REDOX_SOURCE}/build/${arch}/${config}"

    echo
    echo "==> profile ${profile}"

    # The live ISO is the distributable form; fall back to the raw disk image
    # when the profile was built with a harddrive-only target.
    img="${build_dir}/redox-live.iso"
    [ -f "${img}" ] || img="${build_dir}/harddrive.img"

    if [ ! -f "${img}" ]; then
        if [ "${DO_BUILD}" -eq 1 ]; then
            log "image missing; building (this downloads several GB)"
            "${SCRIPT_DIR}/build.sh" -a "${arch}" -c "${config}"
            img="${build_dir}/redox-live.iso"
            [ -f "${img}" ] || img="${build_dir}/harddrive.img"
        fi
    fi

    if [ ! -f "${img}" ]; then
        log "SKIP: no image in ${build_dir} (re-run with --build)"
        echo "${profile} = not-built" >> "${MANIFEST}"
        release_failed=1
        continue
    fi

    if [ "${DO_TEST}" -eq 1 ]; then
        log "boot smoke-test"
        if ! "${SCRIPT_DIR}/test.sh" -a "${arch}" -c "${config}"; then
            log "boot test FAILED for ${profile}"
            release_failed=1
        fi
    fi

    name="$(basename "${img}")"
    out="${DIST}/${config}-${arch}-${name}"
    log "collecting ${name} ($(du -h "${img}" | cut -f1))"
    cp "${img}" "${out}"

    {
        echo ""
        echo "[${profile}]"
        echo "artifact = $(basename "${out}")"
        echo "bytes = $(stat -c %s "${out}")"
        kernel_provenance "${arch}"
    } >> "${MANIFEST}"
done

echo
echo "==> checksums"
# sha256sum over the artifacts only, so the checksum file is stable regardless
# of the manifest content.
( cd "${DIST}" && sha256sum ./*.iso ./*.img 2>/dev/null > SHA256SUMS || true )
if [ -s "${DIST}/SHA256SUMS" ]; then
    sed 's/^/  /' "${DIST}/SHA256SUMS"
else
    log "no artifacts to checksum"
fi

cp "${PLATFORM_DIR}/upstream.lock" "${DIST}/upstream.lock"

echo
echo "==> release manifest"
sed 's/^/  /' "${MANIFEST}"

echo
if [ "${release_failed}" -eq 0 ]; then
    echo "RESULT: PASS (artifacts in ${DIST})"
    exit 0
fi
echo "RESULT: INCOMPLETE (some profiles missing or failing; see above)" >&2
exit 1
