#!/usr/bin/env bash
# OronyxClang — Toolchain Slim
# Strips unnecessary components from the built toolchain to reduce size.
# Run BEFORE packaging.
# Usage: bash scripts/toolchain-slim.sh <toolchain-dir>
set -euo pipefail

TC_DIR="${1:-}"
DRY_RUN=false
AGGRESSIVE=false
VERBOSE=false

log()    { echo -e "\033[1;36m[Slim]\033[0m $*"; }
warn()   { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
info()   { echo -e "\033[1;32m[INFO]\033[0m $*"; }
die()    { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── Binaries to KEEP ───────────────────────────────────────────────────────
# Everything else in bin/ is removed
KEEP_BINS=(
  "clang"
  "clang++"
  "clang-*"
  "clang-cpp"
  "ld.lld"
  "ld.lld-*"
  "lld"
  "lld-*"
  "lld-link"
  "lld-link-*"
  "wasm-ld"
  "wasm-ld-*"
  "llvm-ar"
  "llvm-nm"
  "llvm-objcopy"
  "llvm-objdump"
  "llvm-strip"
  "llvm-readelf"
  "llvm-readobj"
  "llvm-profdata"
  "llvm-symbolizer"
  "llvm-addr2line"
  "llvm-cov"
  "llvm-size"
  "llvm-strings"
  "llvm-dwarfdump"
  "llvm-dis"
  "llvm-otool"
  "llvm-bolt"
  "perf2bolt"
  "merge-fdata"
  "llvm-lto"
  "llvm-lto2"
  "FileCheck"
)

# ─── Usage ──────────────────────────────────────────────────────────────────
usage() {
  cat << 'EOF'
OronyxClang — Toolchain Slim
Strips unnecessary components and reduces toolchain size.

Usage: toolchain-slim.sh <toolchain-dir> [options]

Options:
  --aggressive    Also remove .a files, headers, docs (max savings)
  --dry-run       Show what would be removed without deleting
  --verbose       Show detailed output
  --help          Show this help

Examples:
  toolchain-slim.sh ~/toolchains/oronyx
  toolchain-slim.sh ~/toolchains/oronyx --aggressive
EOF
  exit 0
}

# ─── Parse args ─────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --aggressive) AGGRESSIVE=true ;;
      --dry-run)    DRY_RUN=true ;;
      --verbose)    VERBOSE=true ;;
      --help|-h)    usage ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        [[ -z "$TC_DIR" ]] || die "Unexpected argument: $1"
        TC_DIR="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$TC_DIR" ]]; then
    # Try default install dir
    TC_DIR="${INSTALL_DIR:-$HOME/toolchains/oronyx}"
  fi

  [[ -d "$TC_DIR" ]] || die "Toolchain dir not found: $TC_DIR"
  [[ -d "$TC_DIR/bin" ]] || die "No bin/ directory in: $TC_DIR"
}

# ─── Get size ──────────────────────────────────────────────────────────────
get_size() {
  du -sh "$1" 2>/dev/null | cut -f1
}

# ─── Strip binaries ─────────────────────────────────────────────────────────
strip_bins() {
  log "Stripping debug symbols from binaries ..."

  local count=0 saved=0
  while IFS= read -r -d '' f; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    local before; before=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [[ "$DRY_RUN" == "true" ]]; then
      info "  [DRY RUN] strip $f"
      ((count++))
      continue
    fi
    # Use llvm-strip if available, else system strip
    if "$TC_DIR/bin/llvm-strip" --strip-all -g "$f" 2>/dev/null; then
      local after; after=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
      saved=$((saved + before - after))
      ((count++))
      $VERBOSE && info "  Stripped $(basename "$f"): $(numfmt --to=iec "$before" 2>/dev/null || echo "$before") → $(numfmt --to=iec "$after" 2>/dev/null || echo "$after")"
    else
      # Fallback to system strip
      if command -v strip &>/dev/null; then
        strip --strip-all -g "$f" 2>/dev/null && { ((count++)); }
      fi
    fi
  done < <(find "$TC_DIR/bin" -type f -executable -print0 2>/dev/null)

  local saved_hr
  saved_hr=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  info "  Stripped $count binaries, saved $saved_hr"
}

# ─── Remove unused bins ─────────────────────────────────────────────────────
remove_unused_bins() {
  log "Removing unused binaries ..."

  # Build find patterns for keep
  local keep_patterns=()
  for name in "${KEEP_BINS[@]}"; do
    keep_patterns+=(-name "$name" -o)
  done
  # Remove trailing -o
  unset 'keep_patterns[${#keep_patterns[@]}-1]'

  local removed=0 saved=0
  while IFS= read -r -d '' f; do
    local size; size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [[ "$DRY_RUN" == "true" ]]; then
      info "  [DRY RUN] rm $(basename "$f") ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    else
      rm -f "$f"
    fi
    ((removed++))
    saved=$((saved + size))
  done < <(find "$TC_DIR/bin" -type f -executable \
    ! \( "${keep_patterns[@]}" \) -print0 2>/dev/null)

  # Also remove symlinks to removed targets
  while IFS= read -r -d '' l; do
    [[ -L "$l" && ! -e "$l" ]] || continue
    if [[ "$DRY_RUN" == "true" ]]; then
      info "  [DRY RUN] rm (broken symlink) $(basename "$l")"
    else
      rm -f "$l"
    fi
  done < <(find "$TC_DIR/bin" -type l -print0 2>/dev/null)

  local saved_hr
  saved_hr=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  info "  Removed $removed binaries, saved $saved_hr"
}

# ─── Remove static libraries ───────────────────────────────────────────────
remove_static_libs() {
  log "Removing static libraries (*.a) ..."

  local count=0 saved=0
  while IFS= read -r -d '' f; do
    local size; size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [[ "$DRY_RUN" == "true" ]]; then
      info "  [DRY RUN] rm $(basename "$f") ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    else
      rm -f "$f"
    fi
    ((count++))
    saved=$((saved + size))
  done < <(find "$TC_DIR/lib" -name "*.a" -type f -print0 2>/dev/null)

  local saved_hr
  saved_hr=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  info "  Removed $count static libs, saved $saved_hr"
}

# ─── Remove docs, share, cmake ─────────────────────────────────────────────
remove_docs() {
  log "Removing documentation, cmake files, and share/ ..."

  local dirs=(
    "$TC_DIR/docs"
    "$TC_DIR/doc"
    "$TC_DIR/share"
    "$TC_DIR/lib/cmake"
  )

  local saved=0
  for d in "${dirs[@]}"; do
    if [[ -d "$d" ]]; then
      local size; size=$(du -sb "$d" 2>/dev/null | cut -f1)
      if [[ "$DRY_RUN" == "true" ]]; then
        info "  [DRY RUN] rm -rf $(basename "$d") ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
      else
        rm -rf "$d"
      fi
      saved=$((saved + size))
    fi
  done

  local saved_hr
  saved_hr=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  info "  Saved $saved_hr from docs/cmake/share"
}

# ─── Remove headers (aggressive) ───────────────────────────────────────────
remove_headers() {
  log "Removing header files (aggressive) ..."

  local saved=0
  if [[ -d "$TC_DIR/include" ]]; then
    local size; size=$(du -sb "$TC_DIR/include" 2>/dev/null | cut -f1)
    if [[ "$DRY_RUN" == "true" ]]; then
      info "  [DRY RUN] rm -rf include ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
    else
      rm -rf "$TC_DIR/include"
    fi
    saved=$((saved + size))
  fi

  if [[ -d "$TC_DIR/lib/clang" ]]; then
    # Remove headers but keep built-in modules / resource dir
    while IFS= read -r -d '' f; do
      local sz; sz=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
      [[ "$DRY_RUN" == "true" ]] || rm -f "$f"
      saved=$((saved + sz))
    done < <(find "$TC_DIR/lib/clang" -name "*.h" -type f -print0 2>/dev/null)
  fi

  local saved_hr
  saved_hr=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
  info "  Saved $saved_hr from headers"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  local before; before=$(get_size "$TC_DIR")
  log "Toolchain: $TC_DIR"
  log "Size before: $before"
  echo ""

  strip_bins
  echo ""

  remove_unused_bins
  echo ""

  if [[ "$AGGRESSIVE" == "true" ]]; then
    remove_static_libs
    echo ""
    remove_docs
    echo ""
    remove_headers
    echo ""
  fi

  local after; after=$(get_size "$TC_DIR")
  log "Size after:  $after"

  if [[ "$DRY_RUN" != "true" ]]; then
    # Make sure essential tools are still executable
    for tool in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-strip; do
      if [[ ! -x "$TC_DIR/bin/$tool" ]]; then
        warn "WARNING: $tool was removed! This may break functionality."
      fi
    done
  fi
}

main "$@"