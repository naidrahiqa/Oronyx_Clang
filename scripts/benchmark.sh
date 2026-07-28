#!/usr/bin/env bash
# OronyxClang — Toolchain Benchmark
# Compares multiple Oronyx Clang builds: binary size, compile speed, kernel build perf.
# Usage: bash scripts/benchmark.sh [options]
set -euo pipefail

log()    { echo -e "\033[1;36m[Benchmark]\033[0m $*"; }
warn()   { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()    { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
info()   { echo -e "\033[1;32m[INFO]\033[0m $*"; }
header() { echo -e "\033[1;34m$1\033[0m"; }

MODE="compare"          # compare, build-all
VERSIONS=""
TOOLCHAIN_DIRS=""       # Colon-separated paths to existing toolchains
KERNEL_DIR=""           # Kernel dir for build benchmark
JOBS="${JOBS:-$(nproc)}"
OUTPUT_DIR="./benchmark-results"
LLVM_BRANCH=""          # For build-all mode
VERBOSE=false

# ─── Usage ──────────────────────────────────────────────────────────────────
usage() {
  cat << 'EOF'
OronyxClang — Toolchain Benchmark
Compares binary size, compile speed, and kernel build performance.

Usage: benchmark.sh [options]

Modes:
  --compare=<dirs>      Compare existing toolchains (colon-separated paths)
  --build=<versions>    Build & benchmark multiple versions (comma-sep)
  --kernel=<dir>        Kernel source dir for build benchmark
  --jobs=<n>            Parallel jobs (default: nproc)
  --output=<dir>        Output directory for results (default: ./benchmark-results)
  --verbose             Show detailed output
  --help                Show this help

Examples:
  # Compare existing toolchains
  benchmark.sh --compare=~/toolchains/oronyx-v22:~/.local/tc/clang-r522817

  # Build + benchmark multiple versions
  benchmark.sh --build=17.0.6,18.1.8,19.1.0,22.1.8

  # With kernel build benchmark
  benchmark.sh --compare=~/tc/oronyx:~/tc/stock --kernel=~/kernel/sdm845
EOF
  exit 0
}

# ─── Parse args ─────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compare=*)    MODE="compare"; TOOLCHAIN_DIRS="${1#*=}" ;;
      --build=*)      MODE="build"; VERSIONS="${1#*=}" ;;
      --kernel=*)     KERNEL_DIR="${1#*=}" ;;
      --jobs=*)       JOBS="${1#*=}" ;;
      --output=*)     OUTPUT_DIR="${1#*=}" ;;
      --verbose)      VERBOSE=true ;;
      --help|-h)      usage ;;
      *)              die "Unknown option: $1" ;;
    esac
    shift
  done

  mkdir -p "$OUTPUT_DIR"
}

# ═══ Metrics Collection ═════════════════════════════════════════════════════

collect_binary_sizes() {
  local tc_dir="$1"
  local results=()

  local bins=(
    "bin/clang"
    "bin/clang-*"
    "bin/ld.lld"
    "bin/lld"
    "bin/llvm-ar"
    "bin/llvm-objcopy"
    "bin/llvm-strip"
  )

  for pattern in "${bins[@]}"; do
    for f in "$tc_dir"/$pattern; do
      [[ -f "$f" && ! -L "$f" ]] || continue
      local name; name=$(basename "$f")
      local size; size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
      results+=("$name:$size")
    done
  done

  # Total toolchain size
  local total; total=$(du -sb "$tc_dir" 2>/dev/null | cut -f1)
  results+=("(total):$total")

  echo "${results[@]}"
}

collect_clang_version() {
  local tc_dir="$1"
  local clang="$tc_dir/bin/clang"
  if [[ -x "$clang" ]]; then
    "$clang" --version | head -1
  else
    echo "unknown"
  fi
}

# Simple kernel compile test
bench_kernel() {
  local tc_dir="$1" label="$2"
  local log="$OUTPUT_DIR/kernel-build-${label}.log"
  local result_file="$OUTPUT_DIR/kernel-result-${label}.txt"

  if [[ -z "$KERNEL_DIR" ]]; then
    echo "N/A" > "$result_file"
    return
  fi

  info "  Building kernel with $label ..."

  local start end duration
  start=$(date +%s)

  export PATH="$tc_dir/bin:$PATH"
  export ARCH="arm64"
  export CROSS_COMPILE="aarch64-linux-gnu-"

  if ! command -v clang &>/dev/null; then
    warn "    clang not in PATH after adding $tc_dir/bin"
    echo "FAIL (no clang)" > "$result_file"
    return
  fi

  # Quick compile test: build a single kernel file
  local test_file
  test_file=$(find "$KERNEL_DIR/init" -name "*.c" -type f 2>/dev/null | head -1)
  if [[ -z "$test_file" ]]; then
    test_file=$(find "$KERNEL_DIR/kernel" -name "*.c" -type f 2>/dev/null | head -1)
  fi

  if [[ -n "$test_file" ]]; then
    clang -c -O2 "$test_file" -o /dev/null 2>&1 | tail -5 > "$log" || true
    end=$(date +%s)
    duration=$((end - start))
    echo "${duration}s" > "$result_file"
    info "    Compiled in ${duration}s"
  else
    echo "N/A (no source)" > "$result_file"
  fi
}

# ═══ Summary Table ═════════════════════════════════════════════════════════

print_table() {
  local results_dir="$1"
  echo ""
  header "═══════════════════════════════════════════════════════════════"
  header "  Oronyx Clang — Toolchain Benchmark"
  header "═══════════════════════════════════════════════════════════════"
  echo ""

  # Collect all labels
  local labels=()
  for f in "$results_dir"/version-*.txt; do
    [[ -f "$f" ]] || continue
    local label; label=$(basename "$f" .txt); label="${label#version-}"
    labels+=("$label")
  done

  if [[ ${#labels[@]} -eq 0 ]]; then
    warn "No benchmark results found in $results_dir"
    return
  fi

  # Print version info
  for label in "${labels[@]}"; do
    local ver_file="$results_dir/version-${label}.txt"
    [[ -f "$ver_file" ]] && printf "  %-20s %s" "$label" "$(cat "$ver_file")" && echo ""
  done
  echo ""

  # ── Binary sizes table ──
  header "  Binary Sizes (bytes)"
  printf "  %-25s" "Binary"
  for label in "${labels[@]}"; do printf " %12s" "$label"; done
  echo ""

  # Get all unique binary names
  local all_bins=()
  for label in "${labels[@]}"; do
    local sizes_file="$results_dir/sizes-${label}.txt"
    [[ -f "$sizes_file" ]] || continue
    while IFS=: read -r name size; do
      local found=false
      for b in "${all_bins[@]}"; do [[ "$b" == "$name" ]] && { found=true; break; } done
      $found || all_bins+=("$name")
    done < "$sizes_file"
  done

  for bin in "${all_bins[@]}"; do
    printf "  %-25s" "$bin"
    for label in "${labels[@]}"; do
      local sizes_file="$results_dir/sizes-${label}.txt"
      local val=$(grep "^${bin}:" "$sizes_file" 2>/dev/null | cut -d: -f2 || echo "-")
      if [[ "$val" != "-" ]]; then
        printf " %12s" "$(numfmt --to=iec "$val" 2>/dev/null || echo "$val")"
      else
        printf " %12s" "-"
      fi
    done
    echo ""
  done
  echo ""

  # ── Kernel build ──
  if [[ -n "$KERNEL_DIR" ]]; then
    header "  Kernel Compile Time"
    printf "  %-25s" "Toolchain"
    for label in "${labels[@]}"; do printf " %12s" "$label"; done
    echo ""
    printf "  %-25s" "Compile time"
    for label in "${labels[@]}"; do
      local kr_file="$results_dir/kernel-result-${label}.txt"
      [[ -f "$kr_file" ]] && printf " %12s" "$(cat "$kr_file")" || printf " %12s" "-"
    done
    echo ""
    echo ""
  fi

  header "═══════════════════════════════════════════════════════════════"
  echo ""
}

# ═══ Compare existing toolchains ═══════════════════════════════════════════
compare_mode() {
  log "Comparing toolchains ..."

  IFS=':' read -ra dirs <<< "$TOOLCHAIN_DIRS"
  for tc_dir in "${dirs[@]}"; do
    tc_dir="${tc_dir/#\~/$HOME}"
    [[ -d "$tc_dir" ]] || { warn "  Directory not found: $tc_dir"; continue; }
    [[ -d "$tc_dir/bin" ]] || { warn "  No bin/ in $tc_dir"; continue; }

    local label; label=$(basename "$tc_dir")
    info "  Scanning: $label ($tc_dir)"

    local ver; ver=$(collect_clang_version "$tc_dir")
    echo "$ver" > "$OUTPUT_DIR/version-${label}.txt"

    local sizes; sizes=$(collect_binary_sizes "$tc_dir")
    > "$OUTPUT_DIR/sizes-${label}.txt"
    for entry in $sizes; do
      echo "$entry" >> "$OUTPUT_DIR/sizes-${label}.txt"
    done

    bench_kernel "$tc_dir" "$label"
  done

  print_table "$OUTPUT_DIR"
}

# ═══ Build multiple versions ═══════════════════════════════════════════════
build_mode() {
  local script_dir; script_dir="$(cd "$(dirname "$0")" && pwd)"
  local repo_dir; repo_dir="$(dirname "$script_dir")"

  IFS=',' read -ra versions <<< "$VERSIONS"
  for ver in "${versions[@]}"; do
    ver=$(echo "$ver" | tr -d '[:space:]')
    info "  Building LLVM $ver ..."

    local log="$OUTPUT_DIR/build-${ver}.log"
    local start end duration

    start=$(date +%s)
    LLVM_BRANCH="llvmorg-${ver}" \
    ENABLE_PGO=false \
    ENABLE_BOLT=false \
    LTO_MODE=Thin \
    ZSTD_LEVEL=10 \
    bash "$script_dir/build.sh" 2>&1 | tail -20 > "$log" || {
      warn "  Build failed for $ver (see $log)"
      echo "BUILD FAILED" > "$OUTPUT_DIR/version-${ver}.txt"
      continue
    }
    end=$(date +%s)
    duration=$((end - start))
    info "  Built $ver in ${duration}s"

    # Collect metrics from the built toolchain
    local install_dir="${HOME}/toolchains/oronyx"
    if [[ -d "$install_dir/bin" ]]; then
      local ver_str; ver_str=$(collect_clang_version "$install_dir")
      echo "${ver_str} (build: ${duration}s)" > "$OUTPUT_DIR/version-${ver}.txt"
      local sizes; sizes=$(collect_binary_sizes "$install_dir")
      > "$OUTPUT_DIR/sizes-${ver}.txt"
      for entry in $sizes; do echo "$entry" >> "$OUTPUT_DIR/sizes-${ver}.txt"; done
      bench_kernel "$install_dir" "$ver"
    fi
  done

  print_table "$OUTPUT_DIR"
}

# ═══ Main ════════════════════════════════════════════════════════════════════
main() {
  parse_args "$@"

  case "$MODE" in
    compare)
      [[ -n "$TOOLCHAIN_DIRS" ]] || die "Specify --compare=<dirs>"
      compare_mode
      ;;
    build)
      [[ -n "$VERSIONS" ]] || die "Specify --build=<versions>"
      build_mode
      ;;
  esac
}

main "$@"