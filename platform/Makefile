# AIOS — meta-build entry points.
#
# Thin wrappers around scripts/ that call the upstream Redox build system.
# See README.md for details.

ARCH ?= x86_64
CONFIG_NAME ?= ai-developer
REDOX_SOURCE ?= ../redox-os
DIST ?= $(CURDIR)/dist

.PHONY: bootstrap build run test debug release clean help

help:
	@echo "AIOS make targets:"
	@echo "  make bootstrap   fetch the pinned upstream tree (upstream.lock)"
	@echo "  make build       [ARCH=x86_64] [CONFIG_NAME=ai-developer]"
	@echo "  make run         [ARCH=...] [CONFIG_NAME=...]"
	@echo "  make test        [ARCH=...] [CONFIG_NAME=...]"
	@echo "  make debug       [ARCH=...] [CONFIG_NAME=...]"
	@echo "  make release     [DIST=...] reproducible artifacts + checksums"
	@echo "  make clean       (upstream build tree)"
	@echo
	@echo "Profiles:"
	@echo "  x86_64/ai-developer   (Developer OS)"
	@echo "  aarch64/ai-edge       (Edge AI OS)"

# Materialize the pinned upstream tree. Safe to re-run; verifies an existing
# checkout instead of re-cloning it.
bootstrap:
	REDOX_SOURCE=$(REDOX_SOURCE) ./scripts/bootstrap.sh

build: bootstrap
	./scripts/build.sh -a $(ARCH) -c $(CONFIG_NAME)

run:
	./scripts/run-qemu.sh -a $(ARCH) -c $(CONFIG_NAME)

test:
	./scripts/test.sh -a $(ARCH) -c $(CONFIG_NAME)

debug:
	./scripts/debug-qemu.sh -a $(ARCH) -c $(CONFIG_NAME)

release: bootstrap
	DIST=$(DIST) ./scripts/release.sh

clean:
	-$(MAKE) -C $(REDOX_SOURCE) clean PODMAN_BUILD=0 NOT_ON_PODMAN=1
