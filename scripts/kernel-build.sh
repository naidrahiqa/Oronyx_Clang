#!/usr/bin/env bash
# OronyxClang — Unified Kernel Build Script
# Auto-detects kernel version and applies correct flags for 4.19+ kernels.
# Replaces kernel-4x-build.sh and kernel-lto.sh with a single entry point.
# Usage: bash scripts/kernel-build.sh <kernel-dir> [options]
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
ORONYX_ROOT="${ORONYX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# Defaults
KERNEL_DIR=""
ARCH="${ARCH:-arm64}"
DEFCONFIG="${DEFCONFIG:-}"
JOBS="${JOBS:-$(nproc)}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}"
OUT_DIR="${OUT_DIR:-}"
LTO_MODE="${LTO_MODE:-auto}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
KCFLAGS_EXTRA="${KCFLAGS:-}"

# ─── Warning suppress flags per kernel era ────────────────────────────────────
# 4.x kernels trigger many warnings with modern Clang (22+)
WARN_4X=(
  -Wno-unused-function
  -Wno-unused-variable
  -Wno-unused-but-set-variable
  -Wno-address-of-packed-member
  -Wno-shift-negative-value
  -Wno-pointer-sign
  -Wno-maybe-uninitialized
  -Wno-array-bounds
  -Wno-shift-overflow
  -Wno-implicit-fallthrough
  -Wno-incompatible-pointer-types
  -Wno-deprecated-declarations
  -Wno-constant-conversion
  -Wno-missing-field-initializers
  -Wno-tautological-compare
  -Wno-parentheses-equality
  -Wno-empty-body
  -Wno-uninitialized
  -Wno-dangling-else
)

# 5.x kernels need fewer suppress flags
WARN_5X=(
  -Wno-unused-but-set-variable
  -Wno-address-of-packed-member
  -Wno-maybe-uninitialized
  -Wno-incompatible-pointer-types
)

# 6.x kernels — minimal suppress
WARN_6X=(
  -Wno-address-of-packed-member
)

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()   { echo -e "\033[1;36m[Kernel]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
info()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }

START_TIME=$(date +%s)

usage() {
  cat << 'EOF'
OronyxClang — Unified Kernel Build Script

Usage: kernel-build.sh <kernel-dir> [options]

Options:
  --arch=<arch>          Target architecture (default: arm64)
  --defconfig=<name>     Use specific defconfig (default: auto-detect)
  --cross=<prefix>       Cross-compile prefix (default: aarch64-linux-gnu-)
  --triple=<triple>      Target triple (default: aarch64-linux-gnu-)
  --jobs=<n>             Parallel jobs (default: nproc)
  --out=<dir>            Output directory (default: <kernel-dir>/out)
  --lto=<mode>           LTO mode: thin, full, off, auto (default: auto)
                         auto = thin for kernel >= 5.12, off for < 5.0
  --dry-run              Show commands without executing
  --verbose              Show full make output
  --no-warn-suppress     Don't add -Wno-* flags for legacy kernels
  --help                 Show this help

Environment variables:
  ARCH, CROSS_COMPILE, CLANG_TRIPLE, JOBS, OUT_DIR, KCFLAGS

Examples:
  # Kernel 4.19 — auto-detect, no LTO, warning suppress
  kernel-build.sh ~/kernel/msm-4.19

  # Kernel 5.15 — auto ThinLTO
  kernel-build.sh ~/kernel/msm-5.15 --defconfig=vendor/sdm845_defconfig

  # Kernel 6.1 — GKI with ThinLTO
  kernel-build.sh ~/kernel/android-mainline --lto=thin --arch=arm64

  # Force LTO off on kernel 5.x
  kernel-build.sh ~/kernel/msm-5.10 --lto=off

  # Dry run to see what commands would run
  kernel-build.sh ~/kernel/msm-4.19 --dry-run

EOF
  exit 0
}

# ─── Parse Arguments ──────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch=*)           ARCH="${1#*=}" ;;
      --defconfig=*)      DEFCONFIG="${1#*=}" ;;
      --cross=*)          CROSS_COMPILE="${1#*=}" ;;
      --triple=*)         CLANG_TRIPLE="${1#*=}" ;;
      --jobs=*)           JOBS="${1#*=}" ;;
      --out=*)            OUT_DIR="${1#*=}" ;;
      --lto=*)            LTO_MODE="${1#*=}" ;;
      --dry-run)          DRY_RUN=true ;;
      --verbose)          VERBOSE=true ;;
      --no-warn-suppress) NO_WARN_SUPPRESS=true ;;
      --help|-h)          usage ;;
      -*)                 die "Unknown option: $1" ;;
      *)
        if [[ -z "$KERNEL_DIR" ]]; then
          KERNEL_DIR="$1"
        else
          die "Unexpected argument: $1"
        fi
        ;;
    esac
    shift
  done

  [[ -n "$KERNEL_DIR" ]] || { usage; }
  [[ -d "$KERNEL_DIR" ]] || die "Kernel directory not found: $KERNEL_DIR"
  [[ -f "$KERNEL_DIR/Makefile" ]] || die "No Makefile found in: $KERNEL_DIR"

  OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out}"
}

# ─── Detect kernel version ──────────────────────────────────────────────────
detect_kernel() {
  local kv kp
  kv=$(grep -E '^VERSION\s*=' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
  kp=$(grep -E '^PATCHLEVEL\s*=' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
  KERNEL_V="${kv:-0}"
  KERNEL_P="${kp:-0}"
  KERNEL_FULL="$KERNEL_V.$KERNEL_P"

  log "Detected kernel: $KERNEL_FULL"

  if [[ "$KERNEL_V" -lt 4 || ("$KERNEL_V" -eq 4 && "$KERNEL_P" -lt 14) ]]; then
    warn "Kernel < 4.14 is NOT supported by OronyxClang. Proceed at your own risk."
  fi
}

# ─── Detect Clang version ──────────────────────────────────────────────────
detect_clang() {
  if ! command -v clang &>/dev/null; then
    die "clang not found in PATH. Add OronyxClang bin to PATH first."
  fi

  CLANG_VER=$(clang --version | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
  CLANG_MAJOR=$(clang --version | head -1 | grep -oP '\d+' | head -1 || echo "0")

  info "Clang version: $CLANG_VER (major: $CLANG_MAJOR)"

  # Check required tools
  local missing=()
  for tool in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing tools: ${missing[*]}"
  fi
}

# ─── Resolve LTO mode ──────────────────────────────────────────────────────
resolve_lto() {
  case "$LTO_MODE" in
    thin|Thin)
      LTO_MODE="thin"
      ;;
    full|Full)
      LTO_MODE="full"
      ;;
    off|Off)
      LTO_MODE="off"
      ;;
    auto|Auto)
      # Auto-detect based on kernel version
      if [[ "$KERNEL_V" -ge 6 ]]; then
        LTO_MODE="thin"
      elif [[ "$KERNEL_V" -ge 5 && "$KERNEL_P" -ge 12 ]]; then
        LTO_MODE="thin"
      elif [[ "$KERNEL_V" -ge 5 ]]; then
        LTO_MODE="off"
        warn "Kernel 5.0-5.11 has partial LTO support. Using --lto=off for safety."
      else
        LTO_MODE="off"
        info "Kernel < 5.0 has no LTO support. Disabling LTO."
      fi
      ;;
    *)
      die "Invalid LTO mode: $LTO_MODE (use: thin, full, off, auto)"
      ;;
  esac

  # Validate LTO vs kernel version
  if [[ "$LTO_MODE" != "off" && "$KERNEL_V" -lt 5 ]]; then
    warn "Kernel < 5.0 does not support LTO. Forcing --lto=off."
    LTO_MODE="off"
  fi

  if [[ "$LTO_MODE" != "off" && "$CLANG_MAJOR" -lt 12 ]]; then
    warn "Clang < 12 has limited LTO support. Forcing --lto=off."
    LTO_MODE="off"
  fi

  log "LTO mode: $LTO_MODE"
}

# ─── Build warning suppress flags ──────────────────────────────────────────
build_warn_flags() {
  if [[ "${NO_WARN_SUPPRESS:-false}" == "true" ]]; then
    WARN_FLAGS=()
    return
  fi

  if [[ "$KERNEL_V" -eq 4 ]]; then
    WARN_FLAGS=("${WARN_4X[@]}")
    log "Kernel 4.x detected: applying ${#WARN_FLAGS[@]} warning suppress flags"
  elif [[ "$KERNEL_V" -eq 5 && "$KERNEL_P" -lt 12 ]]; then
    WARN_FLAGS=("${WARN_5X[@]}")
    log "Kernel 5.0-5.11: applying ${#WARN_FLAGS[@]} warning suppress flags"
  else
    WARN_FLAGS=("${WARN_6X[@]}")
    log "Kernel $KERNEL_FULL: applying ${#WARN_FLAGS[@]} warning suppress flags"
  fi
}

# ─── Detect defconfig ──────────────────────────────────────────────────────
detect_defconfig() {
  if [[ -n "$DEFCONFIG" ]]; then
    log "Using specified defconfig: $DEFCONFIG"
    return
  fi

  log "Auto-detecting defconfig ..."

  local candidates=(
    "defconfig"
    "vendor/${ARCH}-perf_defconfig"
    "vendor/${ARCH}-perf-gki_defconfig"
    "gki_${ARCH}_defconfig"
    "${ARCH}_defconfig"
    "msm_defconfig"
    "pixel_defconfig"
  )

  for dc in "${candidates[@]}"; do
    if [[ -f "$KERNEL_DIR/arch/$ARCH/configs/$dc" ]]; then
      DEFCONFIG="$dc"
      info "Found defconfig: $dc"
      return
    fi
  done

  # Try to find any defconfig
  local found
  found=$(find "$KERNEL_DIR/arch/$ARCH/configs" -maxdepth 1 -name "*defconfig*" -type f 2>/dev/null | head -1 || true)
  if [[ -n "$found" ]]; then
    DEFCONFIG=$(basename "$found")
    info "Using first defconfig found: $DEFCONFIG"
  else
    die "No defconfig found for ARCH=$ARCH in $KERNEL_DIR/arch/$ARCH/configs/"
  fi
}

# ─── Clean previous build ──────────────────────────────────────────────────
clean_build() {
  if [[ -d "$OUT_DIR" ]]; then
    log "Cleaning previous build at $OUT_DIR ..."
    rm -rf "$OUT_DIR"
  fi
  mkdir -p "$OUT_DIR"
}

# ─── Configure kernel ──────────────────────────────────────────────────────
configure_kernel() {
  log "Configuring kernel with $DEFCONFIG ..."

  local cmd=(
    make -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CC=clang
    CLANG_TRIPLE="$CLANG_TRIPLE"
    CROSS_COMPILE="$CROSS_COMPILE"
    HOSTCC=clang
    HOSTCXX=clang++
    "$DEFCONFIG"
  )

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ${cmd[*]}"
    return
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    "${cmd[@]}"
  else
    "${cmd[@]}" 2>&1 | grep -E "^\*|error|warning" || true
  fi

  info "Kernel configured successfully."
}

# ─── Build kernel ──────────────────────────────────────────────────────────
build_kernel() {
  log "Building kernel (jobs=$JOBS, lto=$LTO_MODE) ..."

  # Build KCFLAGS string
  local kcflags=()

  # Add warning suppress flags
  kcflags+=("${WARN_FLAGS[@]+"${WARN_FLAGS[@]}"}")

  # Add LTO flags if enabled
  if [[ "$LTO_MODE" == "thin" ]]; then
    kcflags+=(-flto=thin)
  elif [[ "$LTO_MODE" == "full" ]]; then
    kcflags+=(-flto)
  fi

  # Add user-specified KCFLAGS
  if [[ -n "$KCFLAGS_EXTRA" ]]; then
    IFS=' ' read -ra extra_flags <<< "$KCFLAGS_EXTRA"
    kcflags+=("${extra_flags[@]}")
  fi

  local kcflags_str="${kcflags[*]:-}"

  local cmd=(
    make -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CC=clang
    CLANG_TRIPLE="$CLANG_TRIPLE"
    CROSS_COMPILE="$CROSS_COMPILE"
    HOSTCC=clang
    HOSTCXX=clang++
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    STRIP=llvm-strip
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    -j"$JOBS"
  )

  # Add KCFLAGS only if non-empty
  if [[ -n "$kcflags_str" ]]; then
    cmd+=(KCFLAGS="$kcflags_str")
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ${cmd[*]}"
    return
  fi

  log "KCFLAGS: $kcflags_str"

  if [[ "$VERBOSE" == "true" ]]; then
    "${cmd[@]}"
  else
    local build_log="$OUT_DIR/build.log"
    "${cmd[@]}" 2>&1 | tee "$build_log" | {
      grep -E "^\*|error:|warning:|LD |OBJCOPY |CC |AR " || true
    }
    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -ne 0 ]]; then
      warn "Build failed! Check log: $build_log"
      warn "Last 20 lines of build log:"
      tail -20 "$build_log" 2>/dev/null || true
      return $exit_code
    fi
  fi

  info "Build completed successfully!"
}

# ─── Generate image ────────────────────────────────────────────────────────
generate_image() {
  log "Generating kernel image ..."

  local cmd=(
    make -C "$KERNEL_DIR"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CC=clang
    CLANG_TRIPLE="$CLANG_TRIPLE"
    CROSS_COMPILE="$CROSS_COMPILE"
    HOSTCC=clang
    HOSTCXX=clang++
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    STRIP=llvm-strip
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    -j"$JOBS"
    Image
  )

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ${cmd[*]}"
    return
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    "${cmd[@]}"
  else
    "${cmd[@]}" 2>&1 | grep -E "OBJCOPY|Image|error" || true
  fi

  # Check for generated image
  local image_path=""
  for path in \
    "$OUT_DIR/arch/$ARCH/boot/Image" \
    "$OUT_DIR/arch/$ARCH/boot/Image.gz" \
    "$OUT_DIR/arch/$ARCH/boot/Image.gz-dtb" \
    "$OUT_DIR/arch/$ARCH/boot/Image.bz2"; do
    if [[ -f "$path" ]]; then
      image_path="$path"
      break
    fi
  done

  if [[ -n "$image_path" ]]; then
    local size
    size=$(du -sh "$image_path" | cut -f1)
    info "Kernel image: $image_path ($size)"
  else
    warn "No kernel image found in $OUT_DIR/arch/$ARCH/boot/"
  fi
}

# ─── Build summary ──────────────────────────────────────────────────────────
print_summary() {
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  local h=$((duration / 3600))
  local m=$(((duration % 3600) / 60))
  local s=$((duration % 60))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Build Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Kernel:   $KERNEL_FULL"
  info "Arch:     $ARCH"
  info "Clang:    $CLANG_VER"
  info "LTO:      $LTO_MODE"
  info "Output:   $OUT_DIR"
  info "Duration: ${h}h ${m}m ${s}s"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  df -h / 2>/dev/null | tail -1 || true
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  log "OronyxClang — Unified Kernel Build Script"
  echo ""

  parse_args "$@"
  detect_kernel
  detect_clang
  resolve_lto
  build_warn_flags
  detect_defconfig

  log "Configuration:"
  info "  Kernel dir:  $KERNEL_DIR"
  info "  Output dir:  $OUT_DIR"
  info "  Arch:        $ARCH"
  info "  Defconfig:   $DEFCONFIG"
  info "  Jobs:        $JOBS"
  info "  Cross:       $CROSS_COMPILE"
  info "  Triple:      $CLANG_TRIPLE"
  info "  LTO:         $LTO_MODE"
  info "  Warn flags:  ${#WARN_FLAGS[@]}"
  echo ""

  clean_build
  configure_kernel
  build_kernel
  generate_image
  print_summary
}

main "$@"
