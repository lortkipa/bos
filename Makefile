# bOS — see README.md. `make help` lists targets.
SHELL := /bin/bash
SUDO  := $(if $(filter 0,$(shell id -u)),,sudo)
DOCKER ?= docker
BUILDER_IMAGE ?= bos-builder

BOS_ID ?= $(shell . ./bos.conf && echo $$BOS_ID)
DEV_ISO := out/$(BOS_ID)-dev-amd64.iso

# Settings from bos.conf given on the command line or in the environment
# (e.g. `make release BOS_VERSION=1.0.0`) are passed through sudo/docker.
CONF_VARS := BOS_NAME BOS_ID BOS_VERSION BOS_CODENAME SUITE ARCH MIRROR \
             LIVE_USER LIVE_HOSTNAME LOCALE TIMEZONE WORK_DIR OUT_DIR CACHE_DIR
BUILD_ENV := $(foreach v,$(CONF_VARS),$(if $(filter environment command line,$(origin $(v))),$(v)=$($(v))))
BUILD     := $(SUDO) env $(BUILD_ENV) build/build.sh
DOCKER_RUN = $(DOCKER) run --rm --privileged -v "$(CURDIR):/src" $(addprefix -e ,$(BUILD_ENV)) $(BUILDER_IMAGE)

.PHONY: help deps iso dev run run-uefi run-install run-installed release \
        docker-builder docker-iso docker-release theme clean distclean

help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'

deps: ## Install build + VM tools (Ubuntu/Debian hosts)
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y debootstrap squashfs-tools xorriso mtools dosfstools \
	  grub-common grub-pc-bin grub-efi-amd64-bin qemu-system-x86 qemu-utils ovmf

# ---- development -----------------------------------------------------------
iso: ## Build the dev ISO (fast compression, cached downloads)
	$(BUILD) --profile dev

dev: iso run ## Build the dev ISO and boot it in a VM

run: ## Boot the newest ISO in QEMU (BIOS)
	scripts/run-vm.sh $(wildcard $(DEV_ISO))

run-uefi: ## Boot the newest ISO in QEMU (UEFI)
	scripts/run-vm.sh --uefi $(wildcard $(DEV_ISO))

run-install: ## Boot the ISO with a blank virtual disk to test the installer (UEFI)
	scripts/run-vm.sh --uefi --disk $(wildcard $(DEV_ISO))

run-installed: ## Boot the virtual disk installed by run-install
	scripts/run-vm.sh --uefi --boot-disk

theme: ## Regenerate the window decoration theme PNGs
	python3 tools/gen-wm-theme.py

# ---- production ------------------------------------------------------------
release: ## Clean production build: xz-compressed ISO + sha256 + package manifest
	$(BUILD) --profile release

# ---- containerised builds (any Linux host with Docker) ---------------------
docker-builder:
	$(DOCKER) build -t $(BUILDER_IMAGE) build

docker-iso: docker-builder ## Dev ISO, built inside Docker
	$(DOCKER_RUN) --profile dev

docker-release: docker-builder ## Release ISO, built inside Docker
	$(DOCKER_RUN) --profile release

# ---- housekeeping ----------------------------------------------------------
clean: ## Remove the build tree (keeps download cache, ISOs and VM disk)
	$(SUDO) rm -rf work

distclean: clean ## Remove everything generated, including caches, ISOs and VM disk
	$(SUDO) rm -rf cache out vm
