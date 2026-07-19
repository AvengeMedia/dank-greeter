# Root Makefile for DMS Greeter
# Orchestrates the Go core build and local installation of the
# binary (with the quickshell UI embedded) and its system assets.

BINARY_NAME=dms-greeter
CORE_DIR=core
BUILD_DIR=$(CORE_DIR)/bin
PREFIX ?= /usr/local
DESTDIR ?=
INSTALL_DIR=$(PREFIX)/bin
DATA_DIR=$(PREFIX)/share

SHELL_DIR=quickshell
ASSETS_DIR=assets

.PHONY: all build dev run clean test fmt vet update-common i18n-extract i18n-local i18n-test i18n-push i18n-sync i18n-check install install-bin uninstall uninstall-bin help

all: build

build:
	@$(MAKE) -C $(CORE_DIR) build

dev:
	@$(MAKE) -C $(CORE_DIR) dev

run: dev
	@$(BUILD_DIR)/$(BINARY_NAME) run -c $(CURDIR)/$(SHELL_DIR)

clean:
	@$(MAKE) -C $(CORE_DIR) clean

test:
	@$(MAKE) -C $(CORE_DIR) test

fmt:
	@$(MAKE) -C $(CORE_DIR) fmt

vet:
	@$(MAKE) -C $(CORE_DIR) vet

# Pull the latest dank-qml-common and pin it everywhere it is consumed
# (submodule pointer + nix flake input). Commit both in one change.
update-common:
	git submodule update --remote --merge dank-qml-common
	nix --extra-experimental-features 'nix-command flakes' flake update dank-qml-common

i18n-extract:
	@python3 $(SHELL_DIR)/translations/extract_translations.py

i18n-local:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py local

i18n-test:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py test

i18n-push:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py push

i18n-sync:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py sync

i18n-check:
	@python3 $(SHELL_DIR)/scripts/i18nsync.py check

install-bin:
	@test -f $(BUILD_DIR)/$(BINARY_NAME) || { echo "$(BUILD_DIR)/$(BINARY_NAME) not found; run 'make' first"; exit 1; }
	@echo "Installing $(BINARY_NAME) to $(DESTDIR)$(INSTALL_DIR)..."
	@install -D -m 755 $(BUILD_DIR)/$(BINARY_NAME) $(DESTDIR)$(INSTALL_DIR)/$(BINARY_NAME)

install: install-bin
	@echo ""
	@echo "Installation complete."
	@echo "Configure greetd with 'dms-greeter install', then sync your theme with 'dms-greeter sync'."

uninstall-bin:
	@rm -f $(DESTDIR)$(INSTALL_DIR)/$(BINARY_NAME)

uninstall: uninstall-bin
	@echo "Uninstallation complete."

help:
	@echo "Build:"
	@echo "  build              - Build the dms-greeter binary (release flags, UI embedded)"
	@echo "  dev                - Fast development build"
	@echo "  run                - Build and preview the greeter against the in-repo quickshell config"
	@echo "  clean / test / fmt / vet"
	@echo "  update-common      - Bump the dank-qml-common submodule + flake input"
	@echo "  i18n-extract       - Regenerate translations/en.json from I18n.tr() calls"
	@echo "  i18n-local         - Re-extract and show added/removed terms (no POEditor)"
	@echo "  i18n-test          - Extract and validate, no POEditor calls"
	@echo "  i18n-push          - Force-upload all source terms (use for first upload; needs POEditor env)"
	@echo "  i18n-sync          - Upload changed source terms + download translations (needs POEditor env)"
	@echo "  i18n-check         - Fail if local i18n is out of sync with POEditor"
	@echo ""
	@echo "Install (PREFIX=$(PREFIX)):"
	@echo "  install            - Binary (UI embedded)"
	@echo "  uninstall          - Remove the binary"
