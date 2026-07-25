#!/usr/bin/env bash
# OronyxClang — Compatibility Validator
# Checks that OronyxClang is correctly installed and compatible with a kernel tree.
# Usage: scripts/check-compat.sh [kernel-source-dir]
set -euo pipefail

ORONYX_ROOT="${ORONYX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="$ORONYX_ROOT/clang-version.txt"
KERNEL_DIR="${1:-}"

PASS=0
WARN=0
FAIL=0

# ─── Colors ───────────────────────────────────────────────────────────────
GRN="\033[0;32m"; YLW="\033[0;33m"; RED="\033[0;31m"; BLD="\033[1m"; RST="\033[0m"
ok()   { echo -e " ${GRN}✓${RST} $1"; ((PASS++)) || true; }
warn() { echo -e " ${YLW}⚠${RST} $1"; ((WARN++)) || true; }
err()  { echo -e " ${RED}✗${RST} $1"; ((FAIL++)) || true; }
info() { echo -e "   $1"; }

echo -e "${BLD}OronyxClang Compatibility Check${RST}"
echo ""

# ─── 1. Toolchain binaries ──────────────────────────────────────────────
echo -e "${BLD}1. Toolchain binaries${RST}"
TOOLCHAIN_BINS=(clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump)
TOOLCHAIN_PATHS=()
all_same_prefix=true
prefix=""

for bin in "${TOOLCHAIN_BINS[@]}"; do
  path=$(command -v "$bin" || true)
  if [[ -z "$path" ]]; then
    err "$bin — not found in PATH"
    all_same_prefix=false
    continue
  fi
  TOOLCHAIN_PATHS+=("$path")
  bin_prefix=$(dirname "$(dirname "$path")")
  if [[ -z "$prefix" ]]; then
    prefix="$bin_prefix"
  elif [[ "$bin_prefix" != "$prefix" ]]; then
    warn "$bin — from different prefix ($bin_prefix vs $prefix)"
    all_same_prefix=false
  fi
  ok "$bin — $path"
done

if $all_same_prefix && [[ -n "$prefix" ]]; then
  ok "All tools from same installation: $prefix"
fi

# ─── 2. Manifest ─────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}2. Build manifest${RST}"
if [[ -f "$MANIFEST" ]]; then
  ok "clang-version.txt found"
  echo ""
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" == "#"* ]] && continue
    printf "  %-20s = %s\n" "$key" "$val"
  done < "$MANIFEST"
  echo ""
else
  warn "clang-version.txt not found (set ORONYX_ROOT or run from repo root)"
fi

# ─── 3. Clang version ───────────────────────────────────────────────────
echo -e "${BLD}3. Clang version${RST}"
CLANG_VER=$(clang --version | head -1 2>/dev/null || echo "")
if [[ -n "$CLANG_VER" ]]; then
  ok "Clang: $CLANG_VER"
  CLANG_MAJOR=$(echo "$CLANG_VER" | grep -oP '\d+' | head -1)
  CLANG_MAJOR="${CLANG_MAJOR:-0}"

  if [[ "$CLANG_MAJOR" -ge 14 ]]; then
    ok "Clang >= 14 — compatible with kernel >= 6.0"
  elif [[ "$CLANG_MAJOR" -ge 12 ]]; then
    ok "Clang >= 12 — compatible with kernel >= 5.12 LTO"
  elif [[ "$CLANG_MAJOR" -ge 11 ]]; then
    ok "Clang >= 11 — compatible with older kernels"
  else
    err "Clang < 11 — too old for modern kernels"
  fi
else
  err "Clang not found in PATH"
fi

# ─── 4. ld.lld version match ────────────────────────────────────────────
echo ""
echo -e "${BLD}4. Linker version${RST}"
LD_VER=$(ld.lld --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
if [[ "$CLANG_MAJOR" -gt 0 && "$LD_VER" -gt 0 ]]; then
  if [[ "$CLANG_MAJOR" == "$LD_VER" ]]; then
    ok "ld.lld major version ($LD_VER) matches Clang ($CLANG_MAJOR)"
  else
    warn "ld.lld version ($LD_VER) differs from Clang major ($CLANG_MAJOR)"
  fi
else
  warn "Could not compare ld.lld and Clang versions"
fi

# ─── 5. Kernel compatibility ────────────────────────────────────────────
echo ""
echo -e "${BLD}5. Kernel compatibility${RST}"
KV=0
KP=0
if [[ -n "$KERNEL_DIR" && -f "$KERNEL_DIR/Makefile" ]]; then
  KV=$(grep -oP '^VERSION\s*=\s*\K\d+' "$KERNEL_DIR/Makefile" 2>/dev/null || echo "0")
  KP=$(grep -oP '^PATCHLEVEL\s*=\s*\K\d+' "$KERNEL_DIR/Makefile" 2>/dev/null || echo "0")
  ok "Kernel: $KV.$KP"

  if [[ "$KV" -ge 6 ]] && [[ "$CLANG_MAJOR" -ge 14 ]]; then
    ok "Kernel $KV.$KP + Clang $CLANG_MAJOR = compatible"
  elif [[ "$KV" -ge 5 && "$KP" -ge 12 ]] && [[ "$CLANG_MAJOR" -ge 12 ]]; then
    ok "Kernel $KV.$KP + Clang $CLANG_MAJOR = compatible (LTO supported)"
  elif [[ "$KV" -ge 5 ]] && [[ "$CLANG_MAJOR" -ge 12 ]]; then
    ok "Kernel $KV.$KP + Clang $CLANG_MAJOR = compatible (LTO optional)"
  elif [[ "$CLANG_MAJOR" -ge 11 ]]; then
    ok "Kernel $KV.$KP + Clang $CLANG_MAJOR = compatible"
  else
    err "Kernel $KV.$KP requires Clang >= 11 (have $CLANG_MAJOR)"
  fi
elif [[ -n "$KERNEL_DIR" ]]; then
  warn "No Makefile found at $KERNEL_DIR — skipping kernel check"
else
  info "No kernel path provided — skipping kernel check"
  echo "  Pass a kernel source directory as first argument to validate compatibility."
fi

# ─── 6. Kernel version guide ────────────────────────────────────────────
echo ""
echo -e "${BLD}6. Build recommendations${RST}"
if [[ "$KV" -gt 0 ]]; then
  # LTO recommendation
  if [[ "$KV" -ge 6 ]]; then
    ok "LTO: ThinLTO recommended (KCFLAGS=\"-flto=thin\")"
  elif [[ "$KV" -ge 5 && "$KP" -ge 12 ]]; then
    ok "LTO: ThinLTO supported (KCFLAGS=\"-flto=thin\")"
  elif [[ "$KV" -ge 5 ]]; then
    warn "LTO: Partial support, use --lto=off for safety"
  else
    warn "LTO: Not supported on kernel < 5.0, use --lto=off"
  fi

  # Warning suppress flags
  if [[ "$KV" -eq 4 ]]; then
    warn "Warning flags: Kernel 4.x needs 19+ -Wno-* flags for modern Clang"
    info "  Use: kernel-build.sh (auto-applies warning suppress)"
    info "  Or manually add: -Wno-unused-function -Wno-unused-variable ..."
  elif [[ "$KV" -eq 5 && "$KP" -lt 12 ]]; then
    info "Warning flags: Kernel 5.0-5.11 may need 5 -Wno-* flags"
  else
    ok "Warning flags: Minimal suppress needed"
  fi

  # Build command example
  echo ""
  info "Recommended build command:"
  if [[ "$KV" -lt 5 ]]; then
    info "  kernel-build.sh $KERNEL_DIR --defconfig=<name> --lto=off"
  elif [[ "$KV" -ge 5 && "$KP" -ge 12 ]]; then
    info "  kernel-build.sh $KERNEL_DIR --defconfig=<name> --lto=thin"
  else
    info "  kernel-build.sh $KERNEL_DIR --defconfig=<name> --lto=auto"
  fi
else
  info "Provide a kernel directory to see build recommendations"
fi

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
if [[ "$FAIL" -gt 0 ]]; then
  echo -e " ${RED}✗ FAIL${RST} — $FAIL error(s), $WARN warning(s), $PASS passed"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e " ${YLW}⚠ WARN${RST} — $WARN warning(s), $PASS passed"
  exit 2
else
  echo -e " ${GRN}✓ PASS${RST} — all $PASS checks passed"
  exit 0
fi
