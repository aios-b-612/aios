#!/usr/bin/env bash
# Fetch the pinned upstream Redox tree needed to build AIOS images.
#
# The upstream tree is NOT vendored in this repository (separate git history,
# ~1 GB of history). A clean clone therefore has no redox-os/ and cannot build
# an image. This script materializes the exact revision recorded in
# upstream.lock, so `make build` is reproducible on any host and in CI.
#
# Usage:
#   bootstrap.sh            clone if missing, verify revision if present
#   bootstrap.sh --verify   only check that the existing tree matches the pin
#   bootstrap.sh --update   move to the revision in upstream.lock
#                           (re-checkout only; does not merge or pull newer
#                           commits — bump upstream.lock deliberately instead)
#
# Environment:
#   REDOX_SOURCE  where the upstream tree lives (default <platform>/../redox-os)
#
# Exit codes: 0 ok, 1 error, 2 pin mismatch with --verify/--update

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCK_FILE="${PLATFORM_DIR}/upstream.lock"

REDOX_SOURCE="${REDOX_SOURCE:-${PLATFORM_DIR}/../redox-os}"
MODE="ensure"

usage() {
    cat <<'EOF'
Fetch the pinned upstream Redox tree.

Usage: bootstrap.sh [--verify | --update]

  (no flag)   clone the pinned revision if the tree is missing, verify otherwise
  --verify    fail (exit 2) if the tree does not match upstream.lock
  --update    re-checkout the pinned revision in an existing tree
EOF
}

case "${1:-}" in
    "") ;;
    --verify) MODE="verify" ;;
    --update) MODE="update" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option $1" >&2; usage; exit 1 ;;
esac

if [ ! -f "${LOCK_FILE}" ]; then
    echo "ERROR: missing ${LOCK_FILE}" >&2
    exit 1
fi

# Parse the two values we need from the lock file without extra tooling.
lock_value() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"#]*\)\"\{0,1\}[[:space:]]*$/\1/p" \
        "${LOCK_FILE}" | head -1
}

UPSTREAM_REPO="$(lock_value repo)"
UPSTREAM_COMMIT="$(lock_value commit)"

if [ -z "${UPSTREAM_REPO}" ] || [ -z "${UPSTREAM_COMMIT}" ]; then
    echo "ERROR: could not parse repo/commit from ${LOCK_FILE}" >&2
    exit 1
fi

log() { echo "    $*"; }

verify() {
    local actual
    actual="$(git -C "${REDOX_SOURCE}" rev-parse HEAD 2>/dev/null || true)"
    if [ "${actual}" = "${UPSTREAM_COMMIT}" ]; then
        log "upstream revision matches pin (${UPSTREAM_COMMIT:0:12})"
        return 0
    fi
    echo "ERROR: upstream revision mismatch" >&2
    echo "    expected: ${UPSTREAM_COMMIT}" >&2
    echo "    actual:   ${actual:-<not a git checkout>}" >&2
    echo "    run 'bootstrap.sh --update' to re-checkout the pin, or bump" >&2
    echo "    upstream.lock deliberately if the new revision is intended." >&2
    return 2
}

echo "==> AIOS upstream bootstrap"
echo "    repo:   ${UPSTREAM_REPO}"
echo "    commit: ${UPSTREAM_COMMIT}"
echo "    target: ${REDOX_SOURCE}"

case "${MODE}" in
    verify)
        if [ ! -d "${REDOX_SOURCE}/.git" ]; then
            echo "ERROR: no upstream tree at ${REDOX_SOURCE}" >&2
            exit 1
        fi
        verify || exit $?
        ;;
    update)
        if [ ! -d "${REDOX_SOURCE}/.git" ]; then
            echo "ERROR: no upstream tree at ${REDOX_SOURCE} to update" >&2
            exit 1
        fi
        log "fetching ${UPSTREAM_REPO}"
        git -C "${REDOX_SOURCE}" fetch --quiet origin "${UPSTREAM_COMMIT}"
        log "checking out ${UPSTREAM_COMMIT}"
        git -C "${REDOX_SOURCE}" checkout --quiet "${UPSTREAM_COMMIT}"
        verify || exit $?
        ;;
    ensure)
        if [ -d "${REDOX_SOURCE}/.git" ]; then
            verify || exit $?
        else
            if [ -e "${REDOX_SOURCE}" ] && [ -n "$(ls -A "${REDOX_SOURCE}" 2>/dev/null || true)" ]; then
                echo "ERROR: ${REDOX_SOURCE} exists and is not empty," >&2
                echo "       and is not a git checkout. Move it aside or set" >&2
                echo "       REDOX_SOURCE to another path." >&2
                exit 1
            fi
            log "cloning upstream (shallow, pinned revision)"
            # Shallow fetch of the exact revision: keeps the clone small while
            # still pinning it. Not all servers allow fetching an arbitrary
            # SHA unadvertised, so fall back to a full clone if that fails.
            if ! git clone --quiet --depth 1 --branch master "${UPSTREAM_REPO}" \
                "${REDOX_SOURCE}" 2>/dev/null; then
                log "shallow clone failed; falling back to full clone"
                rm -rf "${REDOX_SOURCE}"
                git clone --quiet "${UPSTREAM_REPO}" "${REDOX_SOURCE}"
            fi
            log "fetching pinned revision ${UPSTREAM_COMMIT:0:12}"
            git -C "${REDOX_SOURCE}" fetch --quiet origin "${UPSTREAM_COMMIT}" \
                || git -C "${REDOX_SOURCE}" fetch --quiet origin
            git -C "${REDOX_SOURCE}" checkout --quiet "${UPSTREAM_COMMIT}"
            verify || exit $?
        fi
        ;;
esac

echo "==> upstream ready"
