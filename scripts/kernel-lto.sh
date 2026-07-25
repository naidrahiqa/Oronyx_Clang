#!/usr/bin/env bash
# OronyxClang — Kernel ThinLTO Helper
# Source or run before your kernel make invocation to set up ThinLTO.
# Usage: source scripts/kernel-lto.sh [kernel-source-dir]
set -euo pipefail

ORONYX_ROOT="${ORONYX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="$ORONYX_ROOT/clang-version.txt"
KERNEL_DIR="${1:-}"

log() { echo -e "\033[1;34m[Kernel-LTO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }

# ─── Check toolchain binaries ──────────────────────────────────────────────
check_bins() {
  for bin in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump; do
    if ! command -v "$bin" &>/dev/null; then
      echo "[ERROR] $bin not found in PATH. Export OronyxClang bin directory first." >&2
      return 1
    fi
  done
}

# ─── Parse clang-version.txt ──────────────────────────────────────────────
parse_manifest() {
  if [[ -f "$MANIFEST" ]]; then
    CLANG_VERSION=$(grep -oP 'CLANG_VERSION=\K.*' "$MANIFEST")
    LTO_MODE=$(grep -oP 'LTO=\K.*' "$MANIFEST")
    PGO_ENABLED=$(grep -oP 'PGO=\K.*' "$MANIFEST")
  fi
  CLANG_VERSION="${CLANG_VERSION:-$(clang --version | head -1 | grep -oP '\d+\.\d+\.\d+')}"
  LTO_MODE="${LTO_MODE:-unknown}"
  PGO_ENABLED="${PGO_ENABLED:-unknown}"
}

# ─── Extract Clang major version ──────────────────────────────────────────
get_clang_major() {
  local ver
  ver=$(clang --version | head -1 | grep -oP '\d+' | head -1)
  echo "${ver:-0}"
}

# ─── Detect kernel version ────────────────────────────────────────────────
detect_kernel_version() {
  if [[ -z "$KERNEL_DIR" || ! -f "$KERNEL_DIR/Makefile" ]]; then
    return
  fi
  KERNEL_V=$(grep -oP '^VERSION\s*=\s*\K\d+' "$KERNEL_DIR/Makefile" 2>/dev/null || echo "0")
  KERNEL_P=$(grep -oP '^PATCHLEVEL\s*=\s*\K\d+' "$KERNEL_DIR/Makefile" 2>/dev/null || echo "0")
  KERNEL_FULL="$KERNEL_V.$KERNEL_P"
}

# ─── Main ────────────────────────────────────────────────────────────────
main() {
  log "OronyxClang Kernel LTO Setup"

  check_bins || return 1
  parse_manifest

  CLANG_MAJOR=$(get_clang_major)
  log "Clang version: $CLANG_VERSION (major: $CLANG_MAJOR)"
  log "Manifest PGO: $PGO_ENABLED | LTO: $LTO_MODE"

  # Validate Clang version for ThinLTO
  if [[ "$CLANG_MAJOR" -lt 12 ]]; then
    echo "[ERROR] Clang >= 12 required for ThinLTO (detected: $CLANG_MAJOR)" >&2
    return 1
  fi

  detect_kernel_version
  if [[ -n "${KERNEL_FULL:-}" ]]; then
    log "Kernel: $KERNEL_FULL"
    IFS=. read -r kv kp <<< "$KERNEL_FULL"
    unset IFS
    if [[ "$kv" -lt 5 || ("$kv" -eq 5 && "$kp" -lt 12) ]]; then
      warn "Kernel < 5.12 has incomplete LTO support. Proceed with caution."
    fi
  fi

  # Export LTO build environment
  export CC=clang
  export LD=ld.lld
  export AR=llvm-ar
  export NM=llvm-nm
  export STRIP=llvm-strip
  export OBJCOPY=llvm-objcopy
  export OBJDUMP=llvm-objdump
  export KCFLAGS="-flto=thin ${KCFLAGS:-}"
  export KLDFLAGS="-flto=thin ${KLDFLAGS:-}"

  echo ""
  log "Exported environment:"
  echo "  CC=clang, LD=ld.lld, AR=llvm-ar"
  echo "  KCFLAGS=\"$KCFLAGS\""
  echo "  KLDFLAGS=\"$KLDFLAGS\""
  echo ""
  log "Ready. Run your kernel make command now."
}

main
