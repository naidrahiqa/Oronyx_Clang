# OronyxClang Makefile
# Common tasks for development and CI

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Variables - read from .llvm-version for consistency
VERSION    := $(shell cat VERSION 2>/dev/null || echo "unknown")
LLVM_BRANCH := $(shell cat .llvm-version 2>/dev/null || echo "llvmorg-22.1.8")
BUILD_DIR  := build
INSTALL_DIR := $(HOME)/toolchains/oronyx

# ─── Help ────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@echo "OronyxClang $(VERSION) (LLVM $(LLVM_BRANCH))"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# ─── Build ───────────────────────────────────────────────────────────────────
.PHONY: build
build: ## Build OronyxClang (PGO=true, BOLT=true)
	bash scripts/build.sh

.PHONY: build-simple
build-simple: ## Build without PGO (faster, for testing)
	ENABLE_PGO=false ENABLE_BOLT=false bash scripts/build.sh

.PHONY: build-pgo
build-pgo: ## Build with PGO only (no BOLT)
	ENABLE_BOLT=false bash scripts/build.sh

.PHONY: build-version
build-version: ## Build specific LLVM version (LLVM_VERSION=17.0.6)
	@if [ -z "$(LLVM_VERSION)" ]; then \
		echo "Usage: make build-version LLVM_VERSION=17.0.6"; \
		echo "Examples:"; \
		echo "  make build-version LLVM_VERSION=17.0.6"; \
		echo "  make build-version LLVM_VERSION=18.1.8"; \
		echo "  make build-version LLVM_VERSION=19.1.0"; \
		echo "  make build-version LLVM_VERSION=main LLVM_SOURCE=android"; \
		exit 1; \
	fi
	LLVM_BRANCH=llvmorg-$(LLVM_VERSION) bash scripts/build.sh

.PHONY: build-main
build-main: ## Build from LLVM main branch (rolling release)
	LLVM_BRANCH=main bash scripts/build.sh

.PHONY: build-android
build-android: ## Build from Android's LLVM fork
	LLVM_SOURCE=android bash scripts/build.sh

# ─── Quality ─────────────────────────────────────────────────────────────────
.PHONY: lint
lint: ## Run ShellCheck on all scripts
	@echo "Running ShellCheck ..."
	@find scripts/ -name "*.sh" -exec shellcheck --severity=warning {} + || true
	@echo "Done."

.PHONY: lint-fix
lint-fix: ## Run ShellCheck with auto-fix suggestions
	@find scripts/ -name "*.sh" -exec shellcheck --fix --severity=info {} + || true

.PHONY: fmt
fmt: ## Format shell scripts with shfmt
	@find scripts/ -name "*.sh" -exec shfmt -w -ci -i 2 {} + || true

.PHONY: check
check: lint ## Run all checks (alias for lint)

# ─── Test ────────────────────────────────────────────────────────────────────

# ─── Docker ──────────────────────────────────────────────────────────────────
.PHONY: docker-build
docker-build: ## Build in Docker container
	docker build -t oronyx-clang .

.PHONY: docker-run
docker-run: ## Run build inside Docker
	docker run --rm -v $$(pwd):/workspace -w /workspace oronyx-clang make build

# ─── Patches ─────────────────────────────────────────────────────────────────
.PHONY: sync-patches
sync-patches: ## Sync patches from LLVM stable
	bash scripts/sync-patches.sh

.PHONY: apply-patches
apply-patches: ## Apply all patches to llvm-project
	bash scripts/patch.sh $(BUILD_DIR)/llvm-project

# ─── Clean ───────────────────────────────────────────────────────────────────
.PHONY: clean
clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)
	rm -rf output
	@echo "Cleaned."

.PHONY: distclean
distclean: clean ## Remove everything including toolchain
	rm -rf $(INSTALL_DIR)
	rm -rf llvm-project

# ─── Release ─────────────────────────────────────────────────────────────────
.PHONY: package
package: ## Package toolchain for release
	bash scripts/package.sh

.PHONY: version
version: ## Show current version
	@echo "OronyxClang $(VERSION) (LLVM $(LLVM_BRANCH))"
