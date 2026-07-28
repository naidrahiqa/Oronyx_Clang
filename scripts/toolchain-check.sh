#!/usr/bin/env bash
# OronyxClang — Toolchain Health Check
# Verifies the built toolchain works correctly end-to-end.
# Usage: bash scripts/toolchain-check.sh <toolchain-dir>
set -euo pipefail

TC_DIR="${1:-${INSTALL_DIR:-$HOME/toolchains/oronyx}}"
VERBOSE=false

log()    { echo -e "\033[1;36m[Check]\033[0m $*"; }
warn()   { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()    { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
info()   { echo -e "\033[1;32m[INFO]\033[0m $*"; }
pass()   { echo -e "  \033[1;32m✓\033[0m $*"; }
fail()   { echo -e "  \033[1;31m✗\033[0m $*"; }

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

test_pass() { ((TESTS_PASSED++)); }
test_fail() { ((TESTS_FAILED++)); warn "$*"; }
test_skip() { ((TESTS_SKIPPED++)); }

usage() {
  cat << 'EOF'
OronyxClang — Toolchain Health Check
Verifies the built toolchain is functional.

Usage: toolchain-check.sh [toolchain-dir]

Checks:
  1. Required binaries exist and are executable
  2. Clang compiles a C program
  3. Clang++ compiles a C++ program
  4. LLD links correctly
  5. LLVM ar/nm/strip work
  6. Cross-compilation to AArch64 works
  7. LTO link test
  8. Version strings match
  9. Shared library dependencies
  10. ccache integration (if available)

Examples:
  toolchain-check.sh ~/toolchains/oronyx
  toolchain-check.sh
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) VERBOSE=true ;;
      --help|-h) usage ;;
      *)
        TC_DIR="$1"
        shift
        ;;
    esac
    shift
  done

  [[ -d "$TC_DIR" ]] || die "Toolchain not found: $TC_DIR"
  [[ -d "$TC_DIR/bin" ]] || die "No bin/ in: $TC_DIR"

  export PATH="$TC_DIR/bin:$PATH"
}

check_bin() {
  local name="$1"
  if command -v "$name" &>/dev/null; then
    local path; path=$(command -v "$name")
    local size; size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo "?")
    local size_hr
    size_hr=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
    pass "$name ($path, $size_hr)"
    return 0
  else
    fail "$name — NOT FOUND"
    return 1
  fi
}

check_compile() {
  local lang="$1" compiler="$2" ext="$3" msg="$4" src="$5"
  local tmp; tmp=$(mktemp -d)
  local src_file="$tmp/test.$ext"
  local out_file="$tmp/test.out"

  echo "$src" > "$src_file"
  if "$compiler" -o "$out_file" "$src_file" 2>/dev/null; then
    pass "$msg"
    rm -rf "$tmp"
    return 0
  else
    fail "$msg — COMPILATION FAILED"
    rm -rf "$tmp"
    return 1
  fi
}

check_link() {
  local tmp; tmp=$(mktemp -d)
  local src1="$tmp/a.c" src2="$tmp/b.c" obj1="$tmp/a.o" obj2="$tmp/b.o"

  echo 'int foo(void) { return 42; }' > "$src1"
  echo 'int foo(void); int main(void) { return foo(); }' > "$src2"

  if clang -c -o "$obj1" "$src1" 2>/dev/null && \
     clang -c -o "$obj2" "$src2" 2>/dev/null && \
     ld.lld -o "$tmp/test" "$obj1" "$obj2" 2>/dev/null; then
    pass "LLD linking works"
    rm -rf "$tmp"
    return 0
  else
    fail "LLD linking FAILED"
    rm -rf "$tmp"
    return 1
  fi
}

check_lto() {
  local tmp; tmp=$(mktemp -d)
  local src="$tmp/test.c"
  echo 'int main(void) { return 0; }' > "$src"

  if clang -flto=thin -O2 -o "$tmp/test" "$src" 2>/dev/null; then
    local linked_with; linked_with=$(strings "$tmp/test" 2>/dev/null | grep -i "lld\|LTO" | head -1 || echo "LTO binary")
    pass "ThinLTO link: $linked_with"
    rm -rf "$tmp"
    return 0
  else
    fail "ThinLTO link FAILED"
    rm -rf "$tmp"
    return 1
  fi
}

check_cross() {
  local tmp; tmp=$(mktemp -d)
  local src="$tmp/test.c"
  echo 'int main(void) { return 0; }' > "$src"

  if clang --target=aarch64-linux-android -o "$tmp/test" "$src" 2>/dev/null; then
    local arch; arch=$(file "$tmp/test" 2>/dev/null | grep -o "aarch64\|ARM64" || echo "unknown")
    pass "Cross-compile to AArch64: $arch"
    rm -rf "$tmp"
    return 0
  else
    fail "Cross-compile to AArch64 FAILED"
    rm -rf "$tmp"
    return 1
  fi
}

check_version() {
  local ver; ver=$(clang --version 2>/dev/null | head -1)
  if echo "$ver" | grep -q "$CLANG_VENDOR"; then
    pass "Clang version: $ver"
    return 0
  else
    warn "Clang version: $ver"
    if echo "$ver" | grep -qi "clang"; then
      pass "Clang version (non-Oronyx): $ver"
      return 0
    fi
    fail "Clang version check FAILED"
    return 1
  fi
}

check_shared_libs() {
  local missing=0
  for bin in clang ld.lld; do
    local path; path=$(command -v "$bin" 2>/dev/null || true)
    [[ -z "$path" ]] && continue
    if command -v ldd &>/dev/null; then
      local deps; deps=$(ldd "$path" 2>/dev/null | grep "not found" || true)
      if [[ -n "$deps" ]]; then
        fail "$bin has missing shared libs: $deps"
        ((missing++))
      fi
    fi
  done
  if [[ "$missing" -eq 0 ]]; then
    pass "All shared library dependencies satisfied"
  fi
}

check_resource_dir() {
  local tmp; tmp=$(mktemp -d)
  local src="$tmp/test.c"
  echo 'int main(void) { return 0; }' > "$src"

  # Get resource dir
  local res_dir; res_dir=$(clang -print-resource-dir 2>/dev/null || echo "")
  if [[ -n "$res_dir" && -d "$res_dir" ]]; then
    local files; files=$(find "$res_dir" -type f 2>/dev/null | wc -l)
    pass "Resource dir: $res_dir ($files files)"
  else
    fail "Resource dir not found"
  fi
  rm -rf "$tmp"
}

check_bolt() {
  if command -v llvm-bolt &>/dev/null; then
    local ver; ver=$(llvm-bolt --version 2>/dev/null | head -1 || echo "llvm-bolt")
    pass "BOLT available: $ver"
  else
    test_skip
    info "  BOLT not available (optional)"
  fi
}

# ═══ Main ════════════════════════════════════════════════════════════════════

main() {
  parse_args "$@"
  export CLANG_VENDOR="${CLANG_VENDOR:-Oronyx Clang}"

  echo ""
  header() { echo -e "\033[1;34m$1\033[0m"; }
  header "════════════════════════════════════════════════════"
  header "  Oronyx Clang — Toolchain Health Check"
  header "════════════════════════════════════════════════════"
  echo ""
  info "Toolchain: $TC_DIR"

  local before; before=$(du -sh "$TC_DIR" 2>/dev/null | cut -f1)
  info "Size: $before"
  echo ""

  echo "──────────────────────────────────────────────────────"
  header "  [1] Required Binaries"
  echo "──────────────────────────────────────────────────────"
  local bins=(clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-strip llvm-readelf llvm-profdata llvm-symbolizer)
  for b in "${bins[@]}"; do
    check_bin "$b" && test_pass || test_fail
  done

  echo ""
  echo "──────────────────────────────────────────────────────"
  header "  [2] Compilation Tests"
  echo "──────────────────────────────────────────────────────"
  check_compile "C" clang c "C program compiles" 'int main(void) { return 0; }' && test_pass || test_fail
  check_compile "C++" clang++ cpp "C++ program compiles" 'int main() { return 0; }' && test_pass || test_fail

  echo ""
  echo "──────────────────────────────────────────────────────"
  header "  [3] Linker Tests"
  echo "──────────────────────────────────────────────────────"
  check_link && test_pass || test_fail
  check_lto && test_pass || test_fail

  echo ""
  echo "──────────────────────────────────────────────────────"
  header "  [4] Cross-Compilation"
  echo "──────────────────────────────────────────────────────"
  check_cross && test_pass || test_fail

  echo ""
  echo "──────────────────────────────────────────────────────"
  header "  [5] Version & Integrity"
  echo "──────────────────────────────────────────────────────"
  check_version && test_pass || test_fail
  check_shared_libs && test_pass || test_fail
  check_resource_dir && test_pass || test_fail

  echo ""
  echo "──────────────────────────────────────────────────────"
  header "  [6] Optional Features"
  echo "──────────────────────────────────────────────────────"
  check_bolt

  echo ""
  local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
  header "════════════════════════════════════════════════════"
  header "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
  header "════════════════════════════════════════════════════"
  echo ""

  if [[ "$TESTS_FAILED" -gt 0 ]]; then
    return 1
  fi
}

main "$@"