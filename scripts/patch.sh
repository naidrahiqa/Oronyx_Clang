#!/usr/bin/env bash
# OronyxClang — Patch Application Script
# Applies all patches from patches/ directory to the LLVM source tree.
set -euo pipefail

LLVM_DIR="${1:-$(pwd)/llvm-project}"
PATCHES_DIR="$(cd "$(dirname "$(dirname "$0")")" && pwd)/patches"

log() { echo -e "\033[1;33m[Patches]\033[0m $*"; }

if [[ ! -d "$PATCHES_DIR" ]]; then
  log "No patches/ directory found, skipping."
  exit 0
fi

patch_files=("$PATCHES_DIR"/*.patch)
if [[ ! -e "${patch_files[0]}" ]]; then
  log "No .patch files found in patches/, skipping."
  exit 0
fi

log "Applying patches to $LLVM_DIR ..."

# ─── Fallback fixups for known patches ───────────────────────────────────────
# When git apply fails due to context drift (e.g. shallow clones, upstream
# churn), apply targeted sed fixups so the build never breaks on a patch
# that we know is correct but doesn't apply cleanly.
apply_nsan_gcc14_fallback() {
  local nsan_dir="$LLVM_DIR/compiler-rt/lib/nsan"
  local applied=0

  # ── Target 1: nsan.h ─ define before sanitizer_internal_defs include ────
  local nsan_h="$nsan_dir/nsan.h"
  if [[ -f "$nsan_h" ]] && ! grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
    if sed -i '/#include "sanitizer_common\/sanitizer_internal_defs.h"/i#define SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
      if grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
        log "    ✓ nsan.h GCC-14 fix applied via fallback sed"
        applied=1
      fi
    fi
  elif [[ -f "$nsan_h" ]] && grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
    applied=1
  fi

  # ── Target 2: nsan_allocator.cpp ─ define before first include ───────────
  local nsan_alloc="$nsan_dir/nsan_allocator.cpp"
  if [[ -f "$nsan_alloc" ]] && ! grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_alloc"; then
    if sed -i '0,/^#include/{/^#include/i#define SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD
}' "$nsan_alloc"; then
      if grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_alloc"; then
        log "    ✓ nsan_allocator.cpp GCC-14 fix applied via fallback sed"
        applied=1
      fi
    fi
  elif [[ -f "$nsan_alloc" ]] && grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_alloc"; then
    applied=1
  fi

  # ── Target 3: CMakeLists.txt ─ add -D flag to NSAN_CFLAGS ────────────────
  local nsan_cmake="$nsan_dir/CMakeLists.txt"
  if [[ -f "$nsan_cmake" ]] && ! grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_cmake"; then
    if sed -i '/append_rtti_flag(OFF NSAN_CFLAGS)/a set(NSAN_CFLAGS ${NSAN_CFLAGS} -DSANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD)' "$nsan_cmake"; then
      if grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_cmake"; then
        log "    ✓ nsan CMakeLists.txt GCC-14 fix applied via fallback sed"
        applied=1
      fi
    fi
  elif [[ -f "$nsan_cmake" ]] && grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_cmake"; then
    applied=1
  fi

  [[ $applied -eq 1 ]] && return 0
  return 1
}

# ─── Fallback: lld isPreemptible narrowing (LLVM main changed bool→uint8_t) ──
apply_lld_ispreemptible_fallback() {
  local reloc_cpp="$LLVM_DIR/lld/ELF/Relocations.cpp"
  if [[ ! -f "$reloc_cpp" ]]; then
    log "    ⏭ lld/ELF/Relocations.cpp not found"
    return 1
  fi
  if grep -q '(bool)sym.isPreemptible' "$reloc_cpp"; then
    log "    ✓ isPreemptible narrowing fix already applied"
    return 0
  fi
  if sed -i 's/\(sym\.isPreemptible\)/(bool)\1/g' "$reloc_cpp"; then
    log "    ✓ isPreemptible narrowing fix applied via fallback sed"
    return 0
  fi
  return 1
}

# ─── Main patch loop ────────────────────────────────────────────────────────
for patch in "$PATCHES_DIR"/*.patch; do
  patch_name="$(basename "$patch")"
  log "  → $patch_name"

  # Attempt 1: clean apply
  if git -C "$LLVM_DIR" apply --check "$patch" 2>/dev/null; then
    git -C "$LLVM_DIR" apply "$patch"
    continue
  fi

  # Attempt 2: fuzzy / 3-way merge
  log "    ⚠ clean apply failed, trying --3way ..."
  if git -C "$LLVM_DIR" apply --3way "$patch" 2>/dev/null; then
    log "    ✓ applied with --3way"
    continue
  fi

  # Attempt 3: known fallback fixups
  log "    ⚠ --3way failed, trying built-in fallback ..."
  if [[ "$patch_name" == *"nsan"*"gcc"* || "$patch_name" == *"nsan"*"compat"* ]]; then
    # NSan was added in LLVM 19; skip for older versions
    if [[ ! -d "$LLVM_DIR/compiler-rt/lib/nsan" ]]; then
      log "    ⏭ NSan not present in this LLVM version, skipping patch $patch_name"
      continue
    fi
    if apply_nsan_gcc14_fallback; then
      continue
    fi
  fi

  # lld isPreemptible narrowing fix (LLVM main branch: bool → uint8_t)
  if [[ "$patch_name" == *"lld"*"ispreemptible"* || "$patch_name" == *"lld"*"narrowing"* ]]; then
    if apply_lld_ispreemptible_fallback; then
      continue
    fi
  fi

  echo "ERROR: Failed to apply patch: $patch" >&2
  exit 1
done

log "All patches applied successfully."