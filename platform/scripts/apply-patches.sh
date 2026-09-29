#!/usr/bin/env bash
# Apply the AIOS platform patches on top of the pinned upstream Redox tree.
#
# The upstream tree in redox-os/ is kept at the exact revision recorded in
# upstream.lock. Some Redox packages need a local fix that upstream does not
# carry; those fixes live in platform/patches/<arch>/ and are overlaid onto the
# cookbook recipe here rather than committed upstream.
#
# Why the recipe is edited instead of a separate cookbook directory: `repo cook`
# advertises a --cookbook=<dir> flag, but it is dead code. The recipe index is
# built by `ignore::Walk::new("recipes")` in the cookbook
# (redox-os/src/staged_pkg.rs), a path relative to the current working
# directory, and config.cookbook_dir is parsed but never read. Passing a
# different directory is silently ignored, so a recipe cannot be shadowed that
# way. Editing the recipe in place is the only mechanism the cookbook honours.
#
# The overlay is deterministic and idempotent: running it twice produces the
# same recipe, and --verify reports whether the tree currently matches what
# this script would produce. bootstrap.sh --update discards it, so re-run after
# any re-checkout.
#
# Usage:
#   apply-patches.sh              apply the overlay for the detected arch
#   apply-patches.sh --verify     fail (exit 2) if the overlay is not applied
#   apply-patches.sh --arch ARCH  override the arch (default: from REDOX_ARCH
#                                 or uname -m mapped to a Redox target)
#
# Environment:
#   REDOX_SOURCE  where the upstream tree lives (default <platform>/../redox-os)
#   REDOX_ARCH    aarch64 or x86_64 (default: derived from uname -m)
#
# Exit codes: 0 ok, 1 error, 2 overlay mismatch with --verify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCK_FILE="${PLATFORM_DIR}/upstream.lock"

REDOX_SOURCE="${REDOX_SOURCE:-${PLATFORM_DIR}/../redox-os}"
MODE="apply"

usage() {
    cat <<'EOF'
Overlay AIOS platform patches onto the pinned upstream Redox tree.

Usage: apply-patches.sh [--verify] [--arch ARCH]

  (no flag)   apply the overlay for the target arch
  --verify    fail (exit 2) if the overlay is not currently applied
  --arch      target arch (aarch64|x86_64); defaults to REDOX_ARCH or uname -m
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --verify) MODE="verify" ;;
        --arch) shift; ARCH_OVERRIDE="${1:-}" ;;
        --arch=*) ARCH_OVERRIDE="${1#--arch=}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option $1" >&2; usage; exit 1 ;;
    esac
    shift
done

log() { echo "    $*"; }
err() { echo "ERROR: $*" >&2; }

[ -f "${LOCK_FILE}" ] || { err "missing ${LOCK_FILE}"; exit 1; }
[ -d "${REDOX_SOURCE}" ] || { err "no upstream tree at ${REDOX_SOURCE}"; exit 1; }

# --- arch ------------------------------------------------------------------

detect_arch() {
    case "${1:-$(uname -m)}" in
        aarch64|arm64) echo "aarch64" ;;
        x86_64|amd64)  echo "x86_64" ;;
        *) echo "" ;;
    esac
}

ARCH="$(detect_arch "${ARCH_OVERRIDE:-${REDOX_ARCH:-}}")"
[ -n "${ARCH}" ] || { err "cannot determine target arch from '${ARCH_OVERRIDE:-${REDOX_ARCH:-}}'"; exit 1; }

PATCH_DIR="${PLATFORM_DIR}/patches/${ARCH}"

# Not every arch carries patches. An absent directory means "nothing declared
# for this target", which is a no-op rather than an error, so that bootstrap.sh
# --verify stays meaningful on arches with no overlay.
if [ ! -d "${PATCH_DIR}" ]; then
    log "no ${ARCH} patches declared; nothing to do"
    exit 0
fi

# --- pins ------------------------------------------------------------------

lock_section_value() {
    # Read "key = value" from a named [section] of upstream.lock.
    sed -n "/^\\[$1\\]/,/^\\[/ s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"#]*\)\"\{0,1\}[[:space:]]*$/\\1/p" \
        "${LOCK_FILE}" | head -1
}

# --- target recipe ---------------------------------------------------------

# Each patch targets one cookbook recipe, and that recipe must also be forced to
# the "source" rule. Adding a patch to a different recipe means adding a case
# here.
RECIPE_REL="recipes/core/base/recipe.toml"
RECIPE="${REDOX_SOURCE}/${RECIPE_REL}"
RECIPE_NAME="base"
[ -f "${RECIPE}" ] || { err "missing recipe ${RECIPE_REL} in ${REDOX_SOURCE}"; exit 1; }

PATCH_NAMES=()
while IFS= read -r p; do
    [ -n "${p}" ] || continue
    PATCH_NAMES+=("$(basename "${p}")")
done < <(find "${PATCH_DIR}" -maxdepth 1 -name '*.patch' -type f | sort)

if [ ${#PATCH_NAMES[@]} -eq 0 ]; then
    if [ "${MODE}" = "verify" ]; then
        log "no ${ARCH} patches declared; nothing to verify"
        exit 0
    fi
    log "no ${ARCH} patches declared; nothing to do"
    exit 0
fi

LOCK_OVERRIDE="${REDOX_SOURCE}/cookbook.lock"

# The build defaults to REPO_BINARY=1, which makes the cookbook download a
# prebuilt source.pkgar for a patched recipe instead of fetching its source. A
# patch would then be silently skipped, so the recipe is pinned to the "source"
# rule in cookbook.lock, which overrides both the recipe default and
# --repo-binary. cookbook.lock is only ever written by `repo change-rule*`, so
# the entry persists across builds; it is still managed here so a clean tree
# gets it without a separate repo invocation.
#
# Equivalent to: repo change-rule-local base --set-rule=source
write_lock_entry() {
    if lock_is_correct; then
        log "cookbook.lock already pins ${RECIPE_NAME} to source"
        return 0
    fi

    if [ -f "${LOCK_OVERRIDE}" ] && grep -q "^\[recipes\.${RECIPE_NAME}\]$" "${LOCK_OVERRIDE}"; then
        # Replace just this recipe's table, leave other entries alone.
        awk -v name="${RECIPE_NAME}" '
            $0 == "[recipes." name "]" {
                skip = 1
                print "[recipes." name "]"
                print "fsrule = \"source\""
                next
            }
            /^\[/ {
                # Restore the blank line the skipped block used to end with, so
                # the file keeps the shape `repo change-rule` writes.
                if (skip) print ""
                skip = 0
                print
                next
            }
            !skip { print }
        ' "${LOCK_OVERRIDE}" > "${LOCK_OVERRIDE}.tmp"
        mv "${LOCK_OVERRIDE}.tmp" "${LOCK_OVERRIDE}"
    elif [ -f "${LOCK_OVERRIDE}" ]; then
        printf '[recipes.%s]\nfsrule = "source"\n' "${RECIPE_NAME}" >> "${LOCK_OVERRIDE}"
    else
        {
            echo "# This file is generated automatically."
            echo "# All configuration here overrides anything from recipes or config directory."
            echo ""
            printf '[recipes.%s]\nfsrule = "source"\n' "${RECIPE_NAME}"
        } > "${LOCK_OVERRIDE}"
    fi
    log "pinned ${RECIPE_NAME} to source in cookbook.lock"
}

lock_is_correct() {
    [ -f "${LOCK_OVERRIDE}" ] || return 1
    grep -A1 "^\[recipes\.${RECIPE_NAME}\]$" "${LOCK_OVERRIDE}" | grep -q '^fsrule = "source"$'
}

# --- expected recipe -------------------------------------------------------

# Rewrite [source] so it carries the pinned rev and the patch list. Existing
# rev/patches lines in [source] are dropped first so the result does not depend
# on whether the overlay was already applied.
PATCHES_TOML=""
for name in "${PATCH_NAMES[@]}"; do
    if [ -z "${PATCHES_TOML}" ]; then
        PATCHES_TOML="\"${name}\""
    else
        PATCHES_TOML="${PATCHES_TOML}, \"${name}\""
    fi
done

rev_line=""
if [ "${ARCH}" = "aarch64" ]; then
    base_rev="$(lock_section_value base rev)"
    [ -n "${base_rev}" ] || { err "upstream.lock has no [base] rev; cannot pin base.git"; exit 1; }
    rev_line="rev = \"${base_rev}\""
fi

expected_recipe() {
    awk -v rev_line="${rev_line}" -v patches_line="patches = [${PATCHES_TOML}]" '
        BEGIN { in_source = 0; done_source = 0 }
        /^\[/ {
            if (in_source) done_source = 1
            in_source = ($0 ~ /^\[source\]/)
            print
            next
        }
        in_source {
            # Drop the keys we manage, then re-emit them after "git =".
            if ($0 ~ /^[[:space:]]*(rev|patches)[[:space:]]*=/) next
            print
            if ($0 ~ /^[[:space:]]*git[[:space:]]*=/) {
                if (rev_line != "") print rev_line
                print patches_line
            }
            next
        }
        { print }
        END { if (in_source && !done_source) {} }
    ' "${RECIPE}"
}

EXPECTED="$(expected_recipe)"

# --- verify ---------------------------------------------------------------

if [ "${MODE}" = "verify" ]; then
    rc=0
    if [ "${EXPECTED}" != "$(cat "${RECIPE}")" ]; then
        err "recipe ${RECIPE_REL} does not carry the expected overlay"
        rc=2
    fi
    for name in "${PATCH_NAMES[@]}"; do
        src="${PATCH_DIR}/${name}"
        dst="${REDOX_SOURCE}/recipes/core/base/${name}"
        if [ ! -f "${dst}" ]; then
            err "patch file missing from recipe dir: ${name}"
            rc=2
        elif ! cmp -s "${src}" "${dst}"; then
            err "patch file differs from platform/patches/${ARCH}/${name}: ${name}"
            rc=2
        fi
    done
    if ! lock_is_correct; then
        err "cookbook.lock does not pin ${RECIPE_NAME} to the source rule"
        rc=2
    fi
    if [ "${rc}" -eq 0 ]; then
        log "overlay verified (${#PATCH_NAMES[@]} ${ARCH} patch(es))"
    fi
    exit "${rc}"
fi

# --- apply -----------------------------------------------------------------

# The patch files must sit next to the recipe: the cookbook resolves
# `patches = [...]` relative to the recipe directory.
for name in "${PATCH_NAMES[@]}"; do
    src="${PATCH_DIR}/${name}"
    dst="${REDOX_SOURCE}/recipes/core/base/${name}"
    if [ -f "${dst}" ] && cmp -s "${src}" "${dst}"; then
        log "patch up to date: ${name}"
    else
        cp "${src}" "${dst}"
        log "installed patch: ${name}"
    fi
done

if [ "${EXPECTED}" = "$(cat "${RECIPE}")" ]; then
    log "recipe already carries the overlay"
else
    printf '%s\n' "${EXPECTED}" > "${RECIPE}"
    if [ -n "${rev_line}" ]; then
        log "pinned base.git to ${base_rev:0:12} in ${RECIPE_REL}"
    fi
    log "added ${#PATCH_NAMES[@]} patch(es) to ${RECIPE_REL}"
fi

write_lock_entry

# The recipe must still be readable by the cookbook, and a patch that does not
# apply would otherwise surface much later as an opaque build failure.
if command -v python3 >/dev/null 2>&1; then
    python3 - "$RECIPE" <<'PY' || { err "overlay produced an invalid recipe"; exit 1; }
import sys
try:
    import tomllib
except ModuleNotFoundError:
    sys.exit(0)
with open(sys.argv[1], "rb") as fh:
    tomllib.load(fh)
PY
fi

log "overlay applied for ${ARCH}"
