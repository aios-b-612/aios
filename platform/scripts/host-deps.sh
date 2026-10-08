#!/usr/bin/env bash
#
# Install the host tools a NATIVE Redox build needs.
#
# The podman build path gets these from the redox-base container. Building
# natively (-n / no podman on the host) requires them on the host instead.
# mk/depends.mk checks the first four and aborts naming them, but ninja is not
# on that list and fails far less legibly, so it is installed here too.
#
# Package names vary by distro, so each tool is tried from the system package
# manager first and only then built with cargo, which is slower but always
# available where cargo is.
#
# Usage: host-deps.sh [-h]
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: host-deps.sh

Installs the host dependencies required by a native Redox build:
  rustup   - required, must already be installed (https://rustup.rs/)
  cbindgen - C header generator for the bindings
  nasm     - assembler
  just     - command runner
  ninja    - CMake build backend, needed by the cookbook source recipes

Re-exports nothing; call it before build.sh -n.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    echo "unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
esac

log() { echo "==> $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# rustup is a hard requirement and bootstrapping someone else's toolchain is
# not this script's job, so only check it.
if ! have rustup; then
  echo "ERROR: rustup not found. Install it from https://rustup.rs/" >&2
  exit 1
fi

install_pkgs() {
  local sudo=""
  if [ "$(id -u)" -ne 0 ]; then
    have sudo || {
      echo "ERROR: need sudo or root to install packages" >&2
      exit 1
    }
    sudo="sudo"
  fi
  $sudo apt-get update
  # One package per invocation on purpose. apt-get aborts the whole
  # transaction when it cannot locate a single name, so a distro that lacks
  # one of these would silently get none of them.
  local pkg
  for pkg in "$@"; do
    if have "$pkg"; then
      continue
    fi
    if $sudo apt-get install -y --no-install-recommends "$pkg"; then
      continue
    fi
    echo "info: ${pkg} is not packaged here; a fallback may cover it" >&2
  done
}

install_pkgs nasm just

# cargo install drops binaries somewhere on PATH already, so once it has run
# the tool is findable; this exists purely so the caller gets a clear message
# instead of a bare "command not found" from make.
install_from_cargo() {
  local tool="$1"
  if have "$tool"; then
    return 0
  fi
  have cargo || {
    echo "ERROR: ${tool} is missing and cargo is not available to build it" >&2
    echo "       Install ${tool} with your package manager and rerun." >&2
    exit 1
  }
  log "installing ${tool} from crates.io (this compiles from source)"
  cargo install --locked "$tool"
}

# The apt package is ninja-build, the binary it installs is ninja, so this
# cannot go through the plain `have "$pkg"` check above.
if ! have ninja; then
  log "installing ninja (apt package: ninja-build)"
  install_pkgs ninja-build
fi

# nasm and just are packaged on the runners and on every distro we target;
# cbindgen is the one that usually has to be compiled. It is NOT taken from
# apt: Ubuntu's cbindgen 0.26 predates the syntax in current relibc headers
# ("expected path" on src/header/err/mod.rs); cargo installs a recent one.
install_from_cargo cbindgen
install_from_cargo just

for tool in rustup cbindgen nasm just ninja; do
  if have "$tool"; then
    echo "    ok: ${tool} ($(command -v "$tool"))"
  elif [ "$tool" = "nasm" ]; then
    # nasm is a C assembler with no crate to fall back on, so a failure here
    # is not recoverable automatically.
    echo "ERROR: nasm is a native-build requirement and is not packaged on this" >&2
    echo "       host. Install it with your package manager (Debian/Ubuntu:" >&2
    echo "       'apt-get install nasm') and rerun." >&2
    exit 1
  elif [ "$tool" = "ninja" ]; then
    # No crate, but pipx ships a prebuilt binary and needs no root, which is
    # the way out when sudo requires a password.
    echo "ERROR: ninja is a native-build requirement and is not available here" >&2
    echo "       Install it with your package manager (Debian/Ubuntu:" >&2
    echo "       'apt-get install ninja-build'), or without root via" >&2
    echo "       'pipx install ninja', then rerun." >&2
    exit 1
  else
    echo "ERROR: ${tool} is still missing after installing dependencies" >&2
    exit 1
  fi
done

echo "==> host dependencies ready"
