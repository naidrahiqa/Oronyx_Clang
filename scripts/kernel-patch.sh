#!/usr/bin/env bash
# OronyxClang — Kernel Patch Manager
# Auto-downloads and applies popular patches for Android kernel development.
# Usage: bash scripts/kernel-patch.sh <kernel-dir> --apply=kernelsu,wireguard
set -euo pipefail

KERNEL_DIR=""
APPLY_LIST=""
VERBOSE=false
DRY_RUN=false

log()   { echo -e "\033[1;36m[KernelPatch]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
info()  { echo -e "\033[1;32m[INFO]\033[0m $*"; }

PATCH_DIR=""

# ─── Available patches (for --help display) ─────────────────────────────────
PATCH_DESCRIPTIONS=(
  "kernelsu    KernelSU root solution              (kernel 5.10+ / 4.14 legacy)"
  "wireguard   WireGuard VPN backport              (kernel < 5.6)"
  "sultan      Sultan kernel patches (scheduler)   (kernel 4.14+)"
  "lxc         LXC container config recommendations (kernel 3.10+)"
)

# ═══ Patch sources ═══════════════════════════════════════════════════════════
# Each source is a function that clones/applies the patch.

# ─── KernelSU ──────────────────────────────────────────────────────────────
patch_kernelsu() {
  log "Applying KernelSU ..."
  local ksu_check_dir="$KERNEL_DIR/kernel/KernelSU"
  if [[ -d "$ksu_check_dir" ]]; then
    info "KernelSU already present at $ksu_check_dir"
    return 0
  fi

  # Check kernel version
  local kv kp
  kv=$(grep -E '^VERSION\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  kp=$(grep -E '^PATCHLEVEL\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  local kver="$kv.$kp"

  # KernelSU needs at least 5.10 for GKI, or 4.14 for legacy
  local ksu_branch="main"
  if [[ "$kv" -le 4 ]]; then
    ksu_branch="legacy"
  fi

  local ksu_dir="$KERNEL_DIR/kernel/KernelSU"
  info "  Cloning KernelSU ($ksu_branch branch) ..."
  git clone --depth=1 --branch="$ksu_branch" \
    "https://github.com/tiann/KernelSU" "$ksu_dir" 2>/dev/null || {
    warn "  KernelSU clone failed (retrying with main)..."
    git clone --depth=1 "https://github.com/tiann/KernelSU" "$ksu_dir" 2>/dev/null || {
      warn "  KernelSU clone failed, skipping"
      return 1
    }
  }

  # Apply KernelSU to kernel
  if [[ -f "$ksu_dir/kernel/KernelSU/install.sh" ]]; then
    log "  Running KernelSU install.sh ..."
    local ksu_exit=0
    bash "$ksu_dir/kernel/KernelSU/install.sh" 2>&1 | \
      grep -v "^$" | sed 's/^/    /' || ksu_exit=$?
    if [[ "$ksu_exit" -ne 0 ]]; then
      warn "  KernelSU install.sh exited with code $ksu_exit — manual integration may be needed"
      return 1
    fi
  else
    warn "  KernelSU install.sh not found at $ksu_dir/kernel/KernelSU/install.sh"
    warn "  Clone may have an unexpected structure — skipping KernelSU integration"
    return 1
  fi

  info "  KernelSU applied successfully!"
  return 0
}

# ─── WireGuard ──────────────────────────────────────────────────────────────
patch_wireguard() {
  log "Applying WireGuard ..."

  # Check if already in-kernel (kernel 5.6+)
  local kv kp
  kv=$(grep -E '^VERSION\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  kp=$(grep -E '^PATCHLEVEL\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')

  if [[ "$kv" -ge 6 ]] || [[ "$kv" -eq 5 && "$kp" -ge 6 ]]; then
    info "WireGuard is built-in since Linux 5.6 — no patch needed"
    return 0
  fi

  # Check if WireGuard is already present in kernel source
  if grep -q "CONFIG_WIREGUARD" "$KERNEL_DIR/drivers/net/Kconfig" 2>/dev/null; then
    info "WireGuard already in kernel source"
    return 0
  fi

  local wg_dir="$KERNEL_DIR/drivers/net/wireguard"
  if [[ -d "$wg_dir" ]]; then
    info "WireGuard already present at $wg_dir"
    return 0
  fi

  local wg_repo="$PATCH_DIR/wireguard-linux-compat"
  if [[ ! -d "$wg_repo" ]]; then
    info "  Cloning wireguard-linux-compat ..."
    git clone --depth=1 \
      "https://github.com/zx2c4/wireguard-linux-compat" "$wg_repo" 2>/dev/null || {
      warn "  WireGuard clone failed, skipping"
      return 1
    }
  fi

  # Copy WireGuard source into kernel
  mkdir -p "$KERNEL_DIR/drivers/net/wireguard"
  cp -r "$wg_repo/src/." "$KERNEL_DIR/drivers/net/wireguard/"

  # Add to Kconfig / Makefile if not present
  if ! grep -q "wireguard" "$KERNEL_DIR/drivers/net/Kconfig" 2>/dev/null; then
    echo "source \"drivers/net/wireguard/Kconfig\"" >> "$KERNEL_DIR/drivers/net/Kconfig"
  fi
  if ! grep -q "wireguard" "$KERNEL_DIR/drivers/net/Makefile" 2>/dev/null; then
    echo "obj-\$(CONFIG_WIREGUARD) += wireguard/" >> "$KERNEL_DIR/drivers/net/Makefile"
  fi

  info "  WireGuard applied successfully"
  return 0
}

# ─── Sultan Kernel Patches ─────────────────────────────────────────────────
patch_sultan() {
  log "Applying Sultan kernel patches ..."
  local sultan_repo="$PATCH_DIR/sultan-kernel-patches"

  if [[ ! -d "$sultan_repo" ]]; then
    info "  Cloning sultan-kernel-patches ..."
    git clone --depth=1 \
      "https://github.com/kdrag0n/sultan-kernel-patches" "$sultan_repo" 2>/dev/null || {
      warn "  Sultan patches clone failed, skipping"
      return 1
    }
  fi

  # Find patches in the repo
  local patches=()
  while IFS= read -r p; do patches+=("$p"); done < <(
    find "$sultan_repo" -name "*.patch" -o -name "*.diff" 2>/dev/null | sort
  )

  if [[ ${#patches[@]} -eq 0 ]]; then
    warn "  No patch files found in sultan-kernel-patches"
    return 1
  fi

  local applied=0 skipped=0
  for p in "${patches[@]}"; do
    local name; name=$(basename "$p")
    if git -C "$KERNEL_DIR" apply --check "$p" 2>/dev/null; then
      git -C "$KERNEL_DIR" apply "$p" 2>/dev/null && {
        info "  ✓ $name"
        ((applied++)) || true
      } || {
        warn "  ✗ $name (apply failed)"
        ((skipped++)) || true
      }
    else
      if $VERBOSE; then
        warn "  - $name (doesn't apply cleanly, skipping)"
      fi
      ((skipped++)) || true
    fi
  done

  info "  Sultan patches: $applied applied, $skipped skipped"
  return 0
}

# ─── LXC Patches ────────────────────────────────────────────────────────────
patch_lxc() {
  log "Applying LXC patches ..."
  local lxc_repo="$PATCH_DIR/lxc-patches"

  if [[ ! -d "$lxc_repo" ]]; then
    info "  Cloning LXC kernel patches ..."
    git clone --depth=1 \
      "https://github.com/lxc/lxc" "$lxc_repo" 2>/dev/null || {
      warn "  LXC clone failed, skipping"
      return 1
    }
  fi

  # Apply LXC config recommendations instead of patches
  local config_needed=(
    "CONFIG_CGROUPS=y"
    "CONFIG_CGROUP_CPUACCT=y"
    "CONFIG_CGROUP_DEVICE=y"
    "CONFIG_CGROUP_FREEZER=y"
    "CONFIG_CGROUP_SCHED=y"
    "CONFIG_CPUSETS=y"
    "CONFIG_MEMCG=y"
    "CONFIG_KEYS=y"
    "CONFIG_VETH=y"
    "CONFIG_BRIDGE=y"
    "CONFIG_BRIDGE_NETFILTER=y"
    "CONFIG_NF_NAT_IPV4=y"
    "CONFIG_IP_NF_FILTER=y"
    "CONFIG_IP6_NF_IPTABLES=y"
    "CONFIG_NF_NAT_IPV6=y"
    "CONFIG_IP6_NF_FILTER=y"
    "CONFIG_IP6_NF_MANGLE=y"
    "CONFIG_VLAN_8021Q=y"
    "CONFIG_NET_SCHED=y"
    "CONFIG_NET_CLS_CGROUP=y"
  )

  local count=0
  for opt in "${config_needed[@]}"; do
    local name="${opt%=*}"
    if ! grep -q "^$name=y" "$KERNEL_DIR/.config" 2>/dev/null; then
      printf "  ○ %s\n" "$opt"
      ((count++))
    fi
  done

  if [[ $count -gt 0 ]]; then
    info "  $count LXC config options need to be enabled"
    info "  Run: kernel-config-optimizer.sh $KERNEL_DIR --out=lxc.config"
  else
    info "  All LXC config options already enabled"
  fi

  return 0
}

# ═══ Main logic ═════════════════════════════════════════════════════════════

usage() {
  cat << 'EOF'
OronyxClang — Kernel Patch Manager
Auto-downloads and applies popular kernel patches.

Usage: kernel-patch.sh <kernel-dir> --apply=kernelsu,wireguard,sultan [options]

Available patches:
EOF
  for desc in "${PATCH_DESCRIPTIONS[@]}"; do
    echo "  $desc"
  done
  cat << 'EOF'

Options:
  --apply=<list>  Comma-separated list of patches to apply
  --verbose       Show detailed output
  --dry-run       Show what would be done without applying
  --help          Show this help

Examples:
  kernel-patch.sh ~/kernel/sdm845 --apply=kernelsu
  kernel-patch.sh ~/kernel/msm-4.19 --apply=kernelsu,wireguard,sultan
  kernel-patch.sh ~/kernel/msm-5.15 --apply=lxc
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply=*)      APPLY_LIST="${1#*=}" ;;
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
  [[ -f "$KERNEL_DIR/Makefile" ]] || die "No Makefile in $KERNEL_DIR — is this a kernel source?"
  [[ -n "$APPLY_LIST" ]] || die "Specify --apply=<patches>"

  PATCH_DIR="$KERNEL_DIR/.oronyx-patches"
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$PATCH_DIR"
  fi
}

main() {
  parse_args "$@"

  # Split comma-separated list
  IFS=',' read -ra patches <<< "$APPLY_LIST"

  local kv kp
  kv=$(grep -E '^VERSION\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  kp=$(grep -E '^PATCHLEVEL\s*=' "$KERNEL_DIR/Makefile" 2>/dev/null | head -1 | awk '{print $3}')
  local kver="$kv.$kp"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Oronyx Kernel Patch Manager"
  info "Kernel: $kver  |  Dir: $KERNEL_DIR"
  info "Patches: ${APPLY_LIST}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local total=${#patches[@]} success=0 fail=0
  for p in "${patches[@]}"; do
    local pname; pname=$(echo "$p" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [[ "$DRY_RUN" == "true" ]]; then
      info "[DRY RUN] Would apply: $pname"
      ((success++))
      continue
    fi

    case "$pname" in
      kernelsu)
        if patch_kernelsu; then ((success++)); else ((fail++)); fi
        ;;
      wireguard)
        if patch_wireguard; then ((success++)); else ((fail++)); fi
        ;;
      sultan)
        if patch_sultan; then ((success++)); else ((fail++)); fi
        ;;
      lxc)
        if patch_lxc; then ((success++)); else ((fail++)); fi
        ;;
      *)
        warn "Unknown patch: $pname"
        ((fail++))
        ;;
    esac
  done

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Patch Summary: $success applied, $fail failed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$fail" -gt 0 ]]; then
    return 1
  fi
}

main "$@"