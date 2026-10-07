#!/usr/bin/env bash
# Sync the AIOS workspace into redox-os/aios-src, the source tree the `aios`
# cookbook recipe builds from.
#
# Why a filtered copy at all: the recipe needs `[source].path` to be the whole
# workspace (the crates depend on each other through workspace path deps), but
# pointing it at the repo root would recurse -- redox-os/ lives INSIDE the repo
# and the cookbook would copy the checkout into itself, redox-os and target/
# included.
#
# What is excluded, on purpose:
#   .cargo/   the workspace config pins an x86_64-only linker; the cookbook
#             redoxer sets the correct target/linker per arch instead
#   target/   host build artifacts are never recipe input
#
# The destination is untracked and disposable: this script owns it, like the
# recipe overlay in apply-patches.sh owns its files.
#
# Usage: sync-aios-src.sh            sync (idempotent)
#        REDOX_SOURCE=/path ./sync-aios-src.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLATFORM_DIR}/.." && pwd)"
REDOX_SOURCE="${REDOX_SOURCE:-${PLATFORM_DIR}/../redox-os}"
DST="${REDOX_SOURCE}/aios-src"

[ -d "${REDOX_SOURCE}" ] || { echo "ERROR: no upstream tree at ${REDOX_SOURCE}" >&2; exit 1; }

mkdir -p "${DST}"
rsync -a --delete \
    --exclude='.cargo/' \
    --exclude='target/' \
    -C \
    "${REPO_ROOT}/Cargo.toml" \
    "${REPO_ROOT}/Cargo.lock" \
    "${REPO_ROOT}/ai-core" \
    "${REPO_ROOT}/ai-inference" \
    "${REPO_ROOT}/edge-sdk" \
    "${REPO_ROOT}/edge-ai" \
    "${REPO_ROOT}/cli" \
    "${REPO_ROOT}/deploy" \
    "${REPO_ROOT}/security" \
    "${DST}/"

echo "    synced workspace -> ${DST}"
