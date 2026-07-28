#!/usr/bin/env bash
# OronyxClang — Kernel Config Optimizer
# Analyzes kernel .config and generates optimization recommendations
# for performance, security, size, and compiler compatibility.
# Usage: bash scripts/kernel-config-optimizer.sh <kernel-dir> [options]
set -euo pipefail

ORONYX_ROOT="${ORONYX_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEVICE_DIR="${ORONYX_ROOT}/config/devices"

KERNEL_DIR=""
DEVICE=""
ARCH="arm64"
DEFCONFIG=""
OUT_FILE=""
VERBOSE=false
DRY_RUN=false

log()   { echo -e "\033[1;36m[ConfigOpt]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
info()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }
header() { echo -e "\033[1;34m$1\033[0m"; }

# ─── Options that SHOULD be disabled (debug, test, unused) ──────────────────
declare -A DISABLE_OPTS
DISABLE_OPTS=(
  # Debug / Tracing
  [DEBUG_FS]="Saves ~500KB, reduces runtime overhead"
  [DEBUG_LL]="No need for low-level debug on production"
  [DYNAMIC_DEBUG]="Runtime memory waste if not actively debugging"
  [DEBUG_PREEMPT]="Adds latency checks, disable on production"
  [DEBUG_LIST]="Kernel list debugging, disable for speed"
  [DEBUG_SG]="Scatter-gather debugging, disable on production"
  [DEBUG_NOTIFIERS]="Notifier call chain debugging"
  [DEBUG_CREDENTIALS]="Credential checks, disable for speed"
  [DEBUG_SCHED]="Scheduler debug, disable on production"
  [DEBUG_STACK_USAGE]="Useful once, disable for regular builds"
  [DEBUG_SPINLOCK]="Spinlock debug overhead"
  [DEBUG_ATOMIC_SLEEP]="Production kernels don't need this"
  [DEBUG_MUTEXES]="Mutex debug overhead"
  [DEBUG_RT_MUTEXES]="RT mutex debug"
  [DEBUG_LOCKING_API_SELFTESTS]="One-time test, disable for builds"
  [DEBUG_INFO]="Strips debug symbols, huge size saving"
  [DEBUG_VM]="VM debugging overhead"
  [DEBUG_BUGVERBOSE]="Reduces kernel image size"
  [DEBUG_MEMORY_INIT]="Boot-time memory init logging"

  # Ftrace / Tracing (heavy overhead)
  [FTRACE]="Significant tracing overhead"
  [FUNCTION_TRACER]="Heavy function tracing overhead"
  [STACK_TRACER]="Stack tracing overhead"

  # Test / Selftest
  [TEST_KASAN]="KASAN test module, not for production"
  [TEST_KSTRTOX]="One-time test"
  [TEST_PRINTF]="One-time test"
  [TEST_BITMAP]="One-time test"
  [TEST_UUID]="One-time test"

  # Verbose / Redundant
  [PRINTK_VERBOSE]="Reduces log spam at boot"
  [EARLY_PRINTK]="Only needed for early boot debug"
  [FW_LOADER_USER_HELPER]="Deprecated, disable unless needed"
  [PROC_KCORE]="Exposes kernel memory layout, security risk"

  # Old / Unused
  [NET_9P]="9P filesystem, rarely used on phones"
  [IPX]="IPX protocol, obsolete"
  [APPLETALK]="AppleTalk, obsolete"
  [WIMAX]="WiMAX, obsolete"
  [IRDA]="IrDA, obsolete"
  [BT_FTRACE]="Bluetooth tracing, disable"
)

# ─── Options that SHOULD be enabled (performance) ──────────────────────────
declare -A ENABLE_OPTS
ENABLE_OPTS=(
  [HZ_1000]="1000Hz timer = smoother UI, lower latency"
  [HZ_300]="300Hz good balance for battery"
  [HZ_250]="250Hz common default"
  [HZ_200]="200Hz for battery-focused builds"
  [MUQSS]="MuQSS CPU scheduler, lower latency"
  [BRLTCP]="Better TCP throughput"
  [TCP_CONG_BBR]="BBR congestion control, best for mobile"
  [TCP_CONG_BBR2]="BBR v2 congestion control"
  [SCHED_ALT]="Alternative schedulers (MuQSS, PDS, BMQ)"
  [CC_OPTIMIZE_FOR_SIZE]="Optimize for size (-Oz) instead of -O2"
  [CC_OPTIMIZE_FOR_PERFORMANCE]="Optimize for performance (-O2)"
  [CC_OPTIMIZE_FOR_PERFORMANCE_O3]="Optimize for performance (-O3)"
  [CRYPTO_AES_NI_INTEL]="AES hardware acceleration"
  [ARM64_CRYPTO]="ARM64 crypto acceleration"
  [CRYPTO_SHA256_ARM64]="SHA256 ARM64 acceleration"
  [CRYPTO_SHA512_ARM64]="SHA512 ARM64 acceleration"
  [CRYPTO_AES_ARM64]="AES ARM64 acceleration"
  [CRYPTO_AES_ARM64_CE]="AES with ARMv8 Crypto Extensions"
  [ARM64_MODULE_PLTS]="Module PLT support (needed for LTO)"
  [ARM64_PATCH_SCU]="SCU patching for SMP"
)

# ─── Options for LTO builds (must be set for Clang LTO to work) ─────────────
declare -A LTO_OPTS
LTO_OPTS=(
  [LTO_CLANG]="Enable Clang ThinLTO (5.12+)"
  [LTO_CLANG_THIN]="ThinLTO (recommended for kernels 5.12+)"
  [CFI_CLANG]="Clang CFI (Control Flow Integrity, 6.x+ GKI)"
  [CFI_PERMISSIVE]="Permissive CFI (log violations, don't panic)"
  [ARM64_BTI]="Branch Target Identification (6.x+)"
  [ARM64_PAUTH]="Pointer Authentication (6.x+)"
  [SHADOW_CALL_STACK]="Shadow Call Stack (6.x+)"
)

# ─── Options that enable KernelSU functionality ─────────────────────────────
declare -A KERNELSU_OPTS
KERNELSU_OPTS=(
  [KPROBES]="Kernel probes — required by KernelSU"
  [HAVE_KPROBES]="Arch support for kprobes"
  [KPROBE_EVENTS]="Kprobe event tracing"
  [MODULES]="Loadable module support"
  [MODULE_UNLOAD]="Module unloading"
)

# ─── Security hardening options ────────────────────────────────────────────
declare -A SECURITY_OPTS
SECURITY_OPTS=(
  [SECURITY_SELINUX]="SELinux mandatory access control"
  [SECURITY_SELINUX_DEVELOP]="SELinux permissive (debug only)"
  [SECURITY_SELINUX_BOOTPARAM]="SELinux boot parameter"
  [SECURITY_DEFEX]="Defex security (Samsung)"
  [SECURITY_PERF_EVENTS_RESTRICT]="Restrict perf events to root"
  [STRICT_KERNEL_RWX]="Kernel RWX restrictions (RO+X)"
  [STRICT_MODULE_RWX]="Module RWX restrictions"
  [IOMMU_DEFAULT_PASSTHROUGH]="IOMMU passthrough (performance)"
  [SECCOMP]="Secure computing mode"
  [SECCOMP_FILTER]="Seccomp filters (required by modern Android)"
  [SECURITY_YAMA]="YAMA security module"
  [HARDENED_USERCOPY]="Hardened usercopy checks"
  [FORTIFY_SOURCE]="String/memory fortification"
  [STACKPROTECTOR]="Stack canary protection"
  [STACKPROTECTOR_STRONG]="Strong stack canary protection"
)

# ─── Usage ──────────────────────────────────────────────────────────────────
usage() {
  cat << 'EOF'
OronyxClang — Kernel Config Optimizer
Analyzes kernel config and generates optimization fragments.

Usage: kernel-config-optimizer.sh <kernel-dir> [options]

Options:
  --arch=<arch>          Target architecture (default: arm64)
  --defconfig=<name>     Use specific defconfig
  --device=<codename>    Load device preset from config/devices/
  --out=<file>           Write optimized config fragment to file
  --verbose              Show detailed analysis
  --dry-run              Don't modify anything, just show report
  --help                 Show this help

Examples:
  # Analyze and show recommendations
  kernel-config-optimizer.sh ~/kernel/sdm845

  # With device preset + auto-generate fragment
  kernel-config-optimizer.sh ~/kernel/sm8150 --device=sm8150 --out=opt.config

  # Generate KernelSU config fragment
  kernel-config-optimizer.sh ~/kernel/sdm845 --out=kernelsu.config

EOF
  exit 0
}

# ─── Parse Args ─────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arch=*)       ARCH="${1#*=}" ;;
      --defconfig=*)  DEFCONFIG="${1#*=}" ;;
      --device=*)     DEVICE="${1#*=}" ;;
      --out=*)        OUT_FILE="${1#*=}" ;;
      --verbose)      VERBOSE=true ;;
      --dry-run)      DRY_RUN=true ;;
      --help|-h)      usage ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        [[ -z "$KERNEL_DIR" ]] || die "Unexpected argument: $1"
        KERNEL_DIR="$1"
        ;;
    esac
    shift
  done

  [[ -n "$KERNEL_DIR" ]] || { usage; }
  [[ -d "$KERNEL_DIR" ]] || die "Kernel dir not found: $KERNEL_DIR"
}

# ─── Detect kernel version ──────────────────────────────────────────────────
detect_kernel_ver() {
  local kv kp
  kv=$(grep -E '^VERSION\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  kp=$(grep -E '^PATCHLEVEL\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  KERNEL_V="${kv:-0}"
  KERNEL_P="${kp:-0}"
  KERNEL_VER="$KERNEL_V.$KERNEL_P"
  log "Detected kernel: $KERNEL_VER"
}

# ─── Load device preset ────────────────────────────────────────────────────
load_device() {
  [[ -z "$DEVICE" ]] && return

  local files=(
    "$DEVICE_DIR/${DEVICE}.conf"
    "$DEVICE_DIR/snapdragon.conf"
    "$DEVICE_DIR/exynos.conf"
    "$DEVICE_DIR/mediatek.conf"
  )

  local found=""
  for f in "${files[@]}"; do
    if [[ -f "$f" ]] && grep -q "^\[$DEVICE\]" "$f" 2>/dev/null; then
      found="$f"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    warn "Device preset '$DEVICE' not found"
    return
  fi

  log "Loading device: $DEVICE (from $(basename "$found"))"
  local section
  section=$(sed -n "/^\[$DEVICE\]/,/^\[/p" "$found" | sed '1d;$d')

  get_val() { echo "$section" | grep -E "^$1=" | head -1 | cut -d= -f2- | tr -d '[:space:]'; }

  local val
  val=$(get_val "DEFCONFIG"); [[ -n "$val" ]] && DEFCONFIG="$val"
  val=$(get_val "ARCH");      [[ -n "$val" ]] && ARCH="$val"
}

# ─── Read config ────────────────────────────────────────────────────────────
read_config() {
  local config_paths=(
    "$KERNEL_DIR/out/.config"
    "$KERNEL_DIR/.config"
  )

  CONFIG_FILE=""
  for p in "${config_paths[@]}"; do
    if [[ -f "$p" ]]; then
      CONFIG_FILE="$p"
      break
    fi
  done

  if [[ -z "$CONFIG_FILE" && -n "$DEFCONFIG" ]]; then
    local dcpath="$KERNEL_DIR/arch/$ARCH/configs/$DEFCONFIG"
    if [[ -f "$dcpath" ]]; then
      CONFIG_FILE="$dcpath"
      warn "Using defconfig (not .config) — results may differ from actual build"
    fi
  fi

  if [[ -z "$CONFIG_FILE" ]]; then
    local found
    found=$(find "$KERNEL_DIR/arch/$ARCH/configs" -name "*defconfig*" -type f 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]]; then
      CONFIG_FILE="$found"
      warn "Using defconfig: $(basename "$found")"
    fi
  fi

  if [[ -z "$CONFIG_FILE" ]]; then
    die "No .config or defconfig found. Build the kernel first or specify --defconfig."
  fi

  log "Reading: $(basename "$CONFIG_FILE")"
}

# ─── Check option status ────────────────────────────────────────────────────
opt_status() {
  grep -q "^$1=y" "$CONFIG_FILE" 2>/dev/null && echo "enabled" && return
  grep -q "^$1=m" "$CONFIG_FILE" 2>/dev/null && echo "module" && return
  grep -q "^# $1 is not set" "$CONFIG_FILE" 2>/dev/null && echo "disabled" && return
  echo "missing"
}

# ─── Analyze ─────────────────────────────────────────────────────────────────
analyze() {
  local disable_count=0 enable_count=0 lto_count=0 sec_count=0 ksu_count=0
  local recommendations=""

  header ""
  header "═══ Oronyx Config Optimizer ═══"
  header "Kernel: $KERNEL_VER  |  Arch: $ARCH  |  Config: $(basename "$CONFIG_FILE")"
  header ""

  # ── Section 1: Debug/Diagnostic to DISABLE ──────────────────────────────
  echo ""
  header "┌─ [1] Debug & Diagnostic — Disable for Production"
  local section_out=""
  for opt in "${!DISABLE_OPTS[@]}"; do
    local status
    status=$(opt_status "$opt")
    case "$status" in
      enabled|module)
        if $VERBOSE; then
          printf "  ✓ %-30s %s\n" "$opt" "${DISABLE_OPTS[$opt]}"
        fi
        recommendations="${recommendations}# ${opt}=n — ${DISABLE_OPTS[$opt]}\n"
        ((disable_count++))
        ;;
      disabled)
        # Already disabled — good
        ;;
      missing)
        if $VERBOSE; then
          printf "  - %-30s (not in config)\n" "$opt"
        fi
        ;;
    esac
  done
  printf "  Found %d options to disable\n" "$disable_count"

  # ── Section 2: Performance to ENABLE ──────────────────────────────────────
  echo ""
  header "┌─ [2] Performance — Enable for Speed"
  for opt in "${!ENABLE_OPTS[@]}"; do
    local status
    status=$(opt_status "$opt")
    if [[ "$status" == "disabled" || "$status" == "missing" ]]; then
      printf "  ○ %-30s %s\n" "$opt" "${ENABLE_OPTS[$opt]}"
      recommendations="${recommendations}${opt}=y — ${ENABLE_OPTS[$opt]}\n"
      ((enable_count++))
    elif [[ "$status" == "enabled" ]] && $VERBOSE; then
      printf "  ✓ %-30s (already enabled)\n" "$opt"
    fi
  done

  # ── Section 3: LTO / CFI (kernel version dependent) ─────────────────────
  echo ""
  header "┌─ [3] LTO & CFI — Link-Time Optimization"
  if [[ "$KERNEL_V" -ge 6 ]]; then
    info "Kernel 6.x: ThinLTO + CFI recommended"
    for opt in "${!LTO_OPTS[@]}"; do
      local status
      status=$(opt_status "$opt")
      if [[ "$status" == "disabled" || "$status" == "missing" ]]; then
        printf "  ○ %-30s %s\n" "$opt" "${LTO_OPTS[$opt]}"
        recommendations="${recommendations}${opt}=y — ${LTO_OPTS[$opt]}\n"
        ((lto_count++))
      elif [[ "$status" == "enabled" ]] && $VERBOSE; then
        printf "  ✓ %-30s (already enabled)\n" "$opt"
      fi
    done
  elif [[ "$KERNEL_V" -ge 5 && "$KERNEL_P" -ge 12 ]]; then
    info "Kernel 5.12+: ThinLTO supported, CFI not available"
    local opts=(LTO_CLANG LTO_CLANG_THIN)
    for opt in "${opts[@]}"; do
      local status
      status=$(opt_status "$opt")
      if [[ "$status" == "disabled" || "$status" == "missing" ]]; then
        printf "  ○ %-30s %s\n" "$opt" "${LTO_OPTS[$opt]}"
        recommendations="${recommendations}${opt}=y — ${LTO_OPTS[$opt]}\n"
        ((lto_count++))
      fi
    done
  else
    info "Kernel $KERNEL_VER: LTO not supported (needs 5.12+)"
  fi

  # ── Section 4: KernelSU ─────────────────────────────────────────────────
  echo ""
  header "┌─ [4] KernelSU — Root Solution"
  if [[ -d "$KERNEL_DIR/kernel/KernelSU" || -f "$KERNEL_DIR/kernel/KernelSU/kernel/Makefile" ]]; then
    info "KernelSU source detected!"
    for opt in "${!KERNELSU_OPTS[@]}"; do
      local status
      status=$(opt_status "$opt")
      if [[ "$status" == "disabled" || "$status" == "missing" ]]; then
        printf "  ○ %-30s %s\n" "$opt" "${KERNELSU_OPTS[$opt]}"
        recommendations="${recommendations}${opt}=y — ${KERNELSU_OPTS[$opt]}\n"
        ((ksu_count++))
      fi
    done
  else
    info "KernelSU not detected in kernel source. Skip."
  fi

  # ── Section 5: Security Hardening ───────────────────────────────────────
  echo ""
  header "┌─ [5] Security Hardening"
  local sec_candidates=(
    SECURITY_SELINUX SECURITY_DEFEX SECCOMP SECCOMP_FILTER
    HARDENED_USERCOPY FORTIFY_SOURCE
    STACKPROTECTOR STACKPROTECTOR_STRONG
    STRICT_KERNEL_RWX STRICT_MODULE_RWX
    SECURITY_PERF_EVENTS_RESTRICT
    SECURITY_YAMA
  )
  for opt in "${sec_candidates[@]}"; do
    local status
    status=$(opt_status "$opt")
    if [[ "$status" == "disabled" ]]; then
      printf "  ○ %-30s %s\n" "$opt" "${SECURITY_OPTS[$opt]:-}"
      recommendations="${recommendations}${opt}=y — ${SECURITY_OPTS[$opt]:-}\n"
      ((sec_count++))
    elif [[ "$status" == "missing" ]]; then
      [[ -n "${SECURITY_OPTS[$opt]:-}" ]] && {
        printf "  ○ %-30s %s\n" "$opt" "${SECURITY_OPTS[$opt]}"
        recommendations="${recommendations}${opt}=y — ${SECURITY_OPTS[$opt]}\n"
        ((sec_count++))
      }
    fi
  done

  # ── Section 6: Summary & Generate ────────────────────────────────────────
  echo ""
  header "═══ Summary ═══"
  printf "  Debug to disable:    %d\n" "$disable_count"
  printf "  Performance to add:  %d\n" "$enable_count"
  printf "  LTO/CFI to add:      %d\n" "$lto_count"
  printf "  KernelSU to add:     %d\n" "$ksu_count"
  printf "  Security to add:     %d\n" "$sec_count"
  echo ""

  # ├── Generate config fragment ────────────────────────────────────────────
  local fragment=""
  fragment="# Oronyx Clang — Optimized Config Fragment
# Generated for kernel: $KERNEL_VER, arch: $ARCH
# $(date -u +%Y-%m-%d\ %H:%M:%S) UTC
"

  if [[ "$disable_count" -gt 0 ]]; then
    fragment+="
# ── Debug/Diagnostic — Disabled ──
"
    for opt in "${!DISABLE_OPTS[@]}"; do
      local st; st=$(opt_status "$opt")
      [[ "$st" == "enabled" || "$st" == "module" ]] && fragment+="# CONFIG_${opt} is not set\n"
    done
  fi

  if [[ "$enable_count" -gt 0 ]]; then
    fragment+="
# ── Performance — Enabled ──
"
    for opt in "${!ENABLE_OPTS[@]}"; do
      local st; st=$(opt_status "$opt")
      [[ "$st" == "disabled" || "$st" == "missing" ]] && fragment+="CONFIG_${opt}=y\n"
    done
  fi

  if [[ "$lto_count" -gt 0 && "$KERNEL_V" -ge 5 ]]; then
    fragment+="
# ── LTO/CFI — Enabled ──
"
    for opt in "${!LTO_OPTS[@]}"; do
      local st; st=$(opt_status "$opt")
      [[ "$st" == "disabled" || "$st" == "missing" ]] && fragment+="CONFIG_${opt}=y\n"
    done
  fi

  if [[ "$ksu_count" -gt 0 ]]; then
    fragment+="
# ── KernelSU — Required Options ──
"
    for opt in "${!KERNELSU_OPTS[@]}"; do
      local st; st=$(opt_status "$opt")
      [[ "$st" == "disabled" || "$st" == "missing" ]] && fragment+="CONFIG_${opt}=y\n"
    done
  fi

  if [[ "$sec_count" -gt 0 ]]; then
    fragment+="
# ── Security Hardening ──
"
    for opt in "${sec_candidates[@]}"; do
      local st; st=$(opt_status "$opt")
      [[ "$st" == "disabled" || "$st" == "missing" ]] && fragment+="CONFIG_${opt}=y\n"
    done
  fi

  # Output the fragment
  if [[ -n "$OUT_FILE" ]]; then
    echo -e "$fragment" > "$OUT_FILE"
    log "Fragment written to: $OUT_FILE"

    local line_count
    line_count=$(echo -e "$fragment" | grep -cE "^CONFIG_|^# CONFIG_" || true)
    info "Contains $line_count config changes"
  fi

  # Print build command recommendations
  header ""
  header "═══ Recommended Build Command ═══"
  local device_flag=""
  [[ -n "$DEVICE" ]] && device_flag="--device=$DEVICE"
  echo ""
  echo "  bash scripts/kernel-build.sh $KERNEL_DIR $device_flag \\"
  echo "    --arch=$ARCH --lto=$([ "$KERNEL_V" -ge 6 ] && echo "thin" || echo "auto") \\"
  echo "    --out=$KERNEL_DIR/out"
  echo ""

  if [[ "$disable_count" -gt 0 || "$enable_count" -gt 0 || "$lto_count" -gt 0 ]]; then
    info "Apply config fragment with:"
    echo ""
    echo "  cd $KERNEL_DIR"
    echo "  ./scripts/kconfig/merge_config.sh out/.config $OUT_FILE"
    echo "  make olddefconfig O=out ARCH=$ARCH"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  detect_kernel_ver
  load_device
  read_config
  analyze
}

main "$@"