#!/usr/bin/env bash
# OronyxClang — Core Build Script
# Performs a 2-stage PGO + ThinLTO Clang build targeting Android kernels.
set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
LLVM_BRANCH="${LLVM_BRANCH:-llvmorg-22.1.8}"
LLVM_SOURCE="${LLVM_SOURCE:-upstream}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/oronyx}"
BUILD_DIR="${BUILD_DIR:-$(pwd)/build}"
LLVM_DIR="${LLVM_DIR:-$(pwd)/llvm-project}"
ENABLE_PGO="${ENABLE_PGO:-true}"
ENABLE_BOLT="${ENABLE_BOLT:-true}"
PGO_WORKLOAD="${PGO_WORKLOAD:-sqlite}"
LTO_MODE="${LTO_MODE:-Thin}"
ZSTD_LEVEL="${ZSTD_LEVEL:-10}"
PRESET="${PRESET:-}"

# Load build preset if specified
CONFIG_FILE="$(cd "$(dirname "$0")/.." && pwd)/config/build.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

PRESET_DIR="$(cd "$(dirname "$0")/.." && pwd)/config/presets"
if [[ -n "$PRESET" ]]; then
  preset_file="$PRESET_DIR/${PRESET}.conf"
  if [[ -f "$preset_file" ]]; then
    echo -e "\033[1;35m[Preset]\033[0m Loading preset: $PRESET ($preset_file)"
    source "$preset_file"
  else
    echo -e "\033[1;31m[ERROR]\033[0m Preset '$PRESET' not found at $preset_file"
    exit 1
  fi
fi

# Memory-aware job scaling
if [[ -z "${JOBS:-}" ]]; then
  if command -v free &>/dev/null; then
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
  elif [[ -f /proc/meminfo ]]; then
    TOTAL_RAM_GB=$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)
  else
    TOTAL_RAM_GB=8
  fi

  if [[ "$TOTAL_RAM_GB" -lt 4 ]]; then
    JOBS=$TOTAL_RAM_GB
  elif [[ "$TOTAL_RAM_GB" -lt 8 ]]; then
    JOBS=$((TOTAL_RAM_GB * 2))
  elif [[ "$TOTAL_RAM_GB" -lt 16 ]]; then
    JOBS=$(nproc 2>/dev/null || echo 4)
  else
    JOBS=$(nproc 2>/dev/null || echo 8)
  fi
  [[ "$JOBS" -lt 1 ]] && JOBS=1
fi

LLVM_TARGETS="${LLVM_TARGETS:-AArch64;ARM}"
LLVM_PROJECTS="${LLVM_PROJECTS:-clang;lld;compiler-rt;polly}"
LLVM_RUNTIMES="${LLVM_RUNTIMES:-}"
CLANG_VENDOR="${CLANG_VENDOR:-Oronyx Clang}"
DEFAULT_TARGET_TRIPLE="${DEFAULT_TARGET_TRIPLE:-aarch64-linux-android}"

# ─── Host Compiler Detection ──────────────────────────────────────────────
detect_host_compiler() {
  HOST_CC="${HOST_CC:-}"
  HOST_CXX="${HOST_CXX:-}"

  if [[ -z "$HOST_CC" ]]; then
    if command -v clang &>/dev/null; then
      HOST_CC="clang"
      HOST_CXX="clang++"
    else
      HOST_CC="cc"
      HOST_CXX="c++"
    fi
  fi

  HOST_PROFDATA=""
  if [[ "$HOST_CC" == *clang* ]]; then
    HOST_HAS_CLANG=true
    local resolved_cc
    resolved_cc=$(command -v "$HOST_CC" || echo "$HOST_CC")
    if [[ -L "$resolved_cc" ]]; then
      resolved_cc=$(readlink -f "$resolved_cc")
    fi
    local host_dir
    host_dir=$(dirname "$resolved_cc")

    local suffix=""
    if [[ "$HOST_CC" =~ clang(-[0-9]+) ]]; then
      suffix="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$suffix" && -x "$host_dir/llvm-profdata$suffix" ]]; then
      HOST_PROFDATA="$host_dir/llvm-profdata$suffix"
    elif [[ -x "$host_dir/llvm-profdata" ]]; then
      HOST_PROFDATA="$host_dir/llvm-profdata"
    elif [[ -n "$suffix" ]] && command -v "llvm-profdata$suffix" &>/dev/null; then
      HOST_PROFDATA=$(command -v "llvm-profdata$suffix")
    elif command -v llvm-profdata &>/dev/null; then
      HOST_PROFDATA=$(command -v llvm-profdata)
    fi
  else
    HOST_HAS_CLANG=false
  fi
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo -e "\n\033[1;36m[OronyxClang]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Check available disk space (in KB). Die if below threshold.
# Usage: check_disk_space <min_kb> <stage_name>
check_disk_space() {
  local min_kb="$1" stage_name="$2"
  local avail_kb
  if df --output=avail / &>/dev/null; then
    avail_kb=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ')
  else
    avail_kb=$(df -P / 2>/dev/null | tail -1 | awk '{print $4}')
  fi
  if [[ -n "$avail_kb" && "$avail_kb" -lt "$min_kb" ]]; then
    local avail_gb=$((avail_kb / 1048576))
    local need_gb=$((min_kb / 1048576))
    die "Not enough disk space for $stage_name (${avail_gb}GB available, need ~${need_gb}GB). Aborting."
  fi
}

# ─── Bundle libc++ shared libraries into toolchain ────────────────────────────
# CMake builds libc++ but may not install .so files to the toolchain.
# This ensures libc++.so.1 and libc++abi.so.1 are present for consumers.
bundle_libcxx() {
  local build_dir="$1"
  local lib_dir="$INSTALL_DIR/lib"

  mkdir -p "$lib_dir"

  local found=0
  for name in libc++.so.1 libc++abi.so.1 libc++.so libc++abi.so; do
    # Skip symlinks, only copy real files
    local src
    src=$(find "$build_dir/lib" -name "$name" -not -type l 2>/dev/null | head -1)
    if [[ -n "$src" && -f "$src" ]]; then
      cp -f "$src" "$lib_dir/"
      # Create major-version symlinks if missing
      if [[ "$name" == "libc++.so.1" && ! -e "$lib_dir/libc++.so" ]]; then
        ln -sf libc++.so.1 "$lib_dir/libc++.so"
      fi
      if [[ "$name" == "libc++abi.so.1" && ! -e "$lib_dir/libc++abi.so" ]]; then
        ln -sf libc++abi.so.1 "$lib_dir/libc++abi.so"
      fi
      found=$((found + 1))
    fi
  done

  # Also check install dir's own lib (cmake may have put them there)
  if [[ -f "$lib_dir/libc++.so.1" ]]; then
    log "libc++ bundled successfully: $lib_dir/libc++.so.1"
  else
    warn "libc++.so.1 not found after install — consumers may need system libc++"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
START_EPOCH=$(date +%s)

# Build timing (global scope so stage_timer_* functions can access)
declare -A STAGE_TIMES
stage_timer_start() { STAGE_TIMES["$1"]=$(date +%s); }
stage_timer_end() {
  local key="$1" start="${STAGE_TIMES[$1]:-0}"
  local end; end=$(date +%s)
  local elapsed=$((end - start))
  STAGE_TIMES["$1"]=$elapsed
}

notify() {
  local type="$1"
  export BUILD_STAGE="${2:-}"
  [[ -x "$NOTIFY_SCRIPT" ]] && bash "$NOTIFY_SCRIPT" "$type" || true
}

build_duration() {
  local now elapsed h m s
  now=$(date +%s)
  elapsed=$((now - START_EPOCH))
  h=$((elapsed / 3600))
  m=$(((elapsed % 3600) / 60))
  s=$((elapsed % 60))
  printf "%dh %dm %ds" "$h" "$m" "$s"
}

gen_changelog() {
  local cl="$BUILD_DIR/changelog.txt"
  local patches_dir="$REPO_DIR/patches"

  {
    echo "*Date:* $BUILD_DATE"
    echo "*Branch:* \`$LLVM_BRANCH\`"
    echo "*LLVM Commit:* \`$LLVM_COMMIT\`"
    echo "*PGO:* $ENABLE_PGO | *LTO:* $LTO_MODE"

    if ls "$patches_dir"/*.patch &>/dev/null 2>&1; then
      echo ""
      echo "*Applied Patches:*"
      for pf in "$patches_dir"/*.patch; do
        local name subj
        name=$(basename "$pf")
        subj=$(grep -m1 '^Subject: ' "$pf" 2>/dev/null | sed 's/^Subject: //' || echo "")
        echo "  • \`$name\`${subj:+ — $subj}"
      done
    fi
  } > "$cl"
  echo "$cl"
}

# ─── Stage 0: Clone LLVM ──────────────────────────────────────────────────────
clone_llvm() {
  if [[ -d "$LLVM_DIR" ]]; then
    log "LLVM already cloned, skipping."
    return
  fi

  local repo_url
  case "$LLVM_SOURCE" in
    android)
      repo_url="https://android.googlesource.com/toolchain/llvm-project"
      log "Cloning LLVM from Android fork (branch: $LLVM_BRANCH) ..."
      ;;
    upstream)
      repo_url="https://github.com/llvm/llvm-project.git"
      log "Cloning LLVM from upstream (branch: $LLVM_BRANCH) ..."
      ;;
    *)
      repo_url="https://github.com/llvm/llvm-project.git"
      log "Unknown LLVM_SOURCE='$LLVM_SOURCE', falling back to upstream"
      ;;
  esac

  local max_attempts=3
  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    if git clone "$repo_url" \
      --depth=1 --branch "$LLVM_BRANCH" "$LLVM_DIR" 2>&1; then
      return 0
    fi
    warn "Clone attempt $attempt/$max_attempts failed"
    rm -rf "$LLVM_DIR" 2>/dev/null || true
    if [[ $attempt -lt $max_attempts ]]; then
      local delay=$((attempt * 10))
      log "Retrying in ${delay}s ..."
      sleep "$delay"
    fi
  done
  die "Failed to clone LLVM after $max_attempts attempts"
}

# ─── Apply Custom Patches ─────────────────────────────────────────────────────
apply_patches() {
  log "Applying custom patches ..."
  bash "$SCRIPT_DIR/patch.sh" "$LLVM_DIR"
}

# ─── CMake Configure Helper ───────────────────────────────────────────────────
cmake_configure() {
  local src="$1" build="$2" install="$3" projects="$4" targets="${5:-$LLVM_TARGETS}"
  shift 5

  local cmake_extra_args=()

  # Warn about stale system gold plugin (version mismatch with LTO)
  if [[ -f /usr/lib/bfd-plugins/LLVMgold.so ]]; then
    warn "System gold plugin detected at /usr/lib/bfd-plugins/LLVMgold.so"
    warn "This may cause LTO errors if the plugin LLVM version differs from the build."
    warn "Consider: sudo apt remove llvm-*-linker-tools  or  remove it manually."
  fi
  if [[ -f /usr/lib/llvm-16/lib/LLVMgold.so ]]; then
    warn "LLVM 16 gold plugin detected — remove with: sudo apt remove llvm-16-linker-tools"
  fi

  # Disable gold plugin build (not needed; we use LLD for ThinLTO)
  cmake_extra_args+=("-DLLVM_BINUTILS_INCDIR=")

  # Enable ccache if available (aggressive mode for faster rebuilds)
  if command -v ccache &>/dev/null; then
    cmake_extra_args+=("-DLLVM_CCACHE_BUILD=ON")
    cmake_extra_args+=("-DLLVM_CCACHE_PARAMS=sloppiness=file_stat_matches|compression=true|compression_level=9")
  fi

  # Limit parallel link jobs to avoid OOM during ThinLTO linking
  # Default: JOBS/2 with min 1 — safe on GitHub runners (16GB RAM, JOBS=4 → link_jobs=2)
  local link_jobs="${PARALLEL_LINK_JOBS:-$(( JOBS > 2 ? JOBS / 2 : 1 ))}"
  [[ "$link_jobs" -lt 1 ]] && link_jobs=1
  cmake_extra_args+=("-DLLVM_PARALLEL_LINK_JOBS=$link_jobs")

  # Use shared ThinLTO cache across targets to save disk + time
  cmake_extra_args+=("-DLLVM_THIN_LTO_CACHE_DIR=$BUILD_DIR/lto-cache")

  # Skip appending git hash to version string (saves rebuilds + disk)
  cmake_extra_args+=("-DLLVM_APPEND_VC_REV=OFF")

  # Use LLD as the linker if available (much faster than GNU ld)
  local lld_path=""
  if command -v ld.lld &>/dev/null; then
    lld_path=$(command -v ld.lld)
  else
    # Handle versioned names (e.g. ld.lld-18 on Ubuntu 24.04)
    for v in 18 17 16 15 14; do
      if command -v "ld.lld-$v" &>/dev/null; then
        lld_path=$(command -v "ld.lld-$v")
        break
      fi
    done
  fi
  if [[ -n "$lld_path" ]]; then
    # Do NOT use -DLLVM_USE_LINKER=lld here — it propagates to sub-builds
    # where the just-built Clang may fail the -fuse-ld=lld compiler check.
    # Instead, use standard CMake variables which don't get forwarded.
    cmake_extra_args+=("-DCMAKE_LINKER=$lld_path")
    cmake_extra_args+=("-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld")
    cmake_extra_args+=("-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld")
    cmake_extra_args+=("-DCMAKE_MODULE_LINKER_FLAGS=-fuse-ld=lld")
  fi

  # Use llvm-ar / llvm-ranlib to avoid triggering the system's gold plugin
  local llvm_ar=""
  if command -v llvm-ar &>/dev/null; then
    llvm_ar=$(command -v llvm-ar)
  else
    # Handle versioned names (e.g. llvm-ar-18 on Ubuntu 24.04)
    for v in 18 17 16 15 14; do
      if command -v "llvm-ar-$v" &>/dev/null; then
        llvm_ar=$(command -v "llvm-ar-$v")
        break
      fi
    done
  fi
  [[ -n "$llvm_ar" ]] && cmake_extra_args+=("-DCMAKE_AR=$llvm_ar")

  local llvm_ranlib=""
  if command -v llvm-ranlib &>/dev/null; then
    llvm_ranlib=$(command -v llvm-ranlib)
  else
    for v in 18 17 16 15 14; do
      if command -v "llvm-ranlib-$v" &>/dev/null; then
        llvm_ranlib=$(command -v "llvm-ranlib-$v")
        break
      fi
    done
  fi
  [[ -n "$llvm_ranlib" ]] && cmake_extra_args+=("-DCMAKE_RANLIB=$llvm_ranlib")

  cmake -S "$src/llvm" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install" \
    -DLLVM_TARGETS_TO_BUILD="$targets" \
    -DLLVM_ENABLE_PROJECTS="$projects" \
    -DLLVM_ENABLE_RUNTIMES="$LLVM_RUNTIMES" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_BUILD_DOCS=OFF \
    -DPOLLY_ENABLE_GPGPU_CODEGEN=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCOMPILER_RT_USE_LIBCXX=ON \
    -DCOMPILER_RT_LINK_CXX_LIBRARY=ON \
    -DCOMPILER_RT_ENABLE_PIC=ON \
    -DCMAKE_SHARED_LINKER_FLAGS="-lc++ -lc++abi -lm" \
    -DCLANG_VENDOR="$CLANG_VENDOR" \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DCLANG_DEFAULT_TARGET_TRIPLE="$DEFAULT_TARGET_TRIPLE" \
    "${cmake_extra_args[@]}" \
    "$@"
}

# ─── Stage 1: Instrumented Build (PGO profiling) ──────────────────────────────
stage1_build() {
  log "Stage 1: Building instrumented Clang for PGO ..."
  local s1_build="$BUILD_DIR/stage1"
  local s1_install="$BUILD_DIR/stage1-install"

  # Include lld and compiler-rt (without sanitizers/xray/libfuzzer) so Stage 1 Clang
  # has a modern LTO-compatible linker and builtins to pass CMake compiler checks.
  local stage1_projects="clang;lld;compiler-rt"

  # Stage 1 is only used for PGO profile collection and gets deleted afterwards —
  # it does NOT need libcxx/libcxxabi/libunwind. Building runtimes here wastes time
  # and fails when the preset's LLVM_RUNTIMES omits libunwind (LIBCXXABI
  # requires it). Final runtimes are built in Stage 2/3 only.
  local saved_runtimes="$LLVM_RUNTIMES"
  LLVM_RUNTIMES=""

  cmake_configure "$LLVM_DIR" "$s1_build" "$s1_install" "$stage1_projects" "X86" \
    -DCMAKE_C_COMPILER="$HOST_CC" \
    -DCMAKE_CXX_COMPILER="$HOST_CXX" \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_BUILD_INSTRUMENTED=IR \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_CRT=OFF

  LLVM_RUNTIMES="$saved_runtimes"

  # Ensure just-built shared libraries are findable by child processes (runtimes cmake).
  local old_ld_path="${LD_LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="$s1_build/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  cmake --build "$s1_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  export LD_LIBRARY_PATH="$old_ld_path"
  cmake --install "$s1_build" 2>&1 | tee -a "$BUILD_DIR/build.log"

  export STAGE1_CC="$s1_install/bin/clang"
  export STAGE1_CXX="$s1_install/bin/clang++"

  # Remove object files from stage1 build to save disk space
  # Keep only binaries needed for profile collection
  log "Removing Stage 1 object files to free disk space ..."
  find "$s1_build" -name "*.o" -delete 2>/dev/null || true
  find "$s1_build" -name "*.obj" -delete 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true
}

# ─── PGO Profile Collection: SQLite ───────────────────────────────────────────
collect_sqlite() {
  log "Collecting PGO profiles via SQLite workload ..."
  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/oronyx-%p.profraw"

  local workload_dir="$BUILD_DIR/workload"
  mkdir -p "$workload_dir"

  log "Downloading SQLite amalgamation ..."
  local sqlite_url="https://www.sqlite.org/2024/sqlite-amalgamation-3460000.zip"
  local sqlite_sha256="712a7d09d2a22652fb06a49af516e051979a3984adb067da86760e60ed51a7f5"
  if ! curl -sSL "$sqlite_url" -o "$workload_dir/sqlite.zip"; then
    warn "SQLite download failed"
    return 1
  fi

  log "Verifying SQLite checksum ..."
  local actual_sha256
  actual_sha256=$(sha256sum "$workload_dir/sqlite.zip" | cut -d' ' -f1)
  if [[ "$actual_sha256" != "$sqlite_sha256" ]]; then
    warn "SQLite checksum mismatch (expected $sqlite_sha256, got $actual_sha256)"
    return 1
  fi

  log "Extracting SQLite amalgamation ..."
  if ! unzip -q "$workload_dir/sqlite.zip" -d "$workload_dir"; then
    warn "SQLite unzip failed"
    return 1
  fi

  log "Compiling SQLite workload with Stage 1 Clang ..."
  if ! "$STAGE1_CC" -c -O2 -o /dev/null \
    "$workload_dir/sqlite-amalgamation-3460000/sqlite3.c"; then
    warn "SQLite compilation failed"
    return 1
  fi

  log "SQLite workload completed successfully."
}

# ─── PGO Profile Collection: Real Kernel ─────────────────────────────────────
collect_kernel() {
  log "Collecting PGO profiles via real Android kernel build ..."
  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/oronyx-%p.profraw"

  local kernel_dir="$BUILD_DIR/kernel-workload"
  log "Cloning android-mainline kernel (--depth=1) ..."
  local max_attempts=3
  local cloned=false
  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    if git clone --depth=1 \
      https://android.googlesource.com/kernel/common "$kernel_dir" 2>&1; then
      cloned=true
      break
    fi
    warn "Kernel clone attempt $attempt/$max_attempts failed"
    rm -rf "$kernel_dir" 2>/dev/null || true
    if [[ $attempt -lt $max_attempts ]]; then
      log "Retrying in 5s ..."
      sleep 5
    fi
  done
  if [[ "$cloned" != "true" ]]; then
    warn "Kernel clone failed after $max_attempts attempts"
    return 1
  fi

  pushd "$kernel_dir" > /dev/null
  log "Configuring kernel (defconfig ARCH=arm64) ..."
  if ! make defconfig ARCH=arm64 CC="$STAGE1_CC"; then
    warn "Kernel defconfig failed"
    popd > /dev/null
    rm -rf "$kernel_dir"
    return 1
  fi

  log "Building kernel subsystems (drivers/gpu + kernel/) ..."
  make -j"$JOBS" ARCH=arm64 CC="$STAGE1_CC" drivers/gpu/ kernel/ || warn "Kernel partial build had errors/warnings"
  popd > /dev/null

  log "Cleaning up kernel source (saves ~2GB) ..."
  rm -rf "$kernel_dir"

  shopt -s nullglob
  local profiles=("$profile_dir"/*.profraw)
  shopt -u nullglob
  if (( ${#profiles[@]} == 0 )); then
    warn "Kernel workload generated no profiles."
    return 1
  fi
  log "Kernel workload completed successfully."
}

# ─── PGO Profile Collection: LLVM Self-Build ──────────────────────────────
collect_llvm() {
  log "Collecting PGO profiles via LLVM self-build ..."
  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/oronyx-%p.profraw"

  local llvm_build="$BUILD_DIR/llvm-workload"
  mkdir -p "$llvm_build"

  # Build a subset of LLVM using stage1 clang — this generates the most
  # representative profile for a C/C++ compiler workload.
  log "Building LLVM tablegen + clang frontend with instrumented stage1 ..."

  cmake -S "$LLVM_DIR/llvm" -B "$llvm_build" -G Ninja \
    -DCMAKE_C_COMPILER="$STAGE1_CC" \
    -DCMAKE_CXX_COMPILER="$STAGE1_CXX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_TARGETS_TO_BUILD="AArch64;ARM" \
    -DLLVM_ENABLE_PROJECTS="clang" \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_BUILD_DOCS=OFF \
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DLLVM_TABLEGEN="$STAGE1_INSTALL/bin/llvm-tblgen" \
    -DCLANG_TABLEGEN="$STAGE1_INSTALL/bin/clang-tblgen" \
    2>&1 | tail -5 >> "$BUILD_DIR/build.log" || true

  # Build only the most-used targets: clang frontend, codegen, basic utils
  # This hits the hot compiler paths without building everything
  local targets=(
    "clang/lib/Sema"
    "clang/lib/CodeGen"
    "clang/lib/Parse"
    "clang/lib/AST"
    "clang/lib/Basic"
    "llvm/lib/IR"
    "llvm/lib/CodeGen"
    "llvm/lib/Transforms"
    "llvm/lib/Target/AArch64"
  )

  for target in "${targets[@]}"; do
    log "  ninja $target ..."
    ninja -C "$llvm_build" "$target" 2>&1 | tail -3 >> "$BUILD_DIR/build.log" || true
  done

  log "Cleaning up LLVM workload build ..."
  rm -rf "$llvm_build"

  shopt -s nullglob
  local profiles=("$profile_dir"/*.profraw)
  shopt -u nullglob
  if (( ${#profiles[@]} == 0 )); then
    warn "LLVM workload generated no profiles."
    return 1
  fi
  log "LLVM self-build workload completed: ${#profiles[@]} profiles."
}

# ─── PGO Profile Collection ───────────────────────────────────────────────────
collect_profiles() {
  local workload="${PGO_WORKLOAD:-sqlite}"
  log "Collecting PGO profiles (workload: $workload) ..."

  local profile_dir="$BUILD_DIR/profiles"
  mkdir -p "$profile_dir"

  if [[ "$workload" == "kernel" ]]; then
    collect_kernel || { warn "Kernel workload failed, falling back to SQLite workload..."; collect_sqlite; } || return 1
  elif [[ "$workload" == "llvm" ]]; then
    collect_llvm || { warn "LLVM workload failed, falling back to SQLite workload..."; collect_sqlite; } || return 1
  else
    collect_sqlite || return 1
  fi

  shopt -s nullglob
  local profiles=("$profile_dir"/*.profraw)
  shopt -u nullglob

  if (( ${#profiles[@]} == 0 )); then
    warn "No .profraw profile files were generated in $profile_dir."
    return 1
  fi

  log "Merging PGO profiles ..."
  local profdata_bin="$STAGE1_INSTALL/bin/llvm-profdata"
  if [[ -n "${HOST_PROFDATA:-}" && -x "$HOST_PROFDATA" ]]; then
    log "Using host llvm-profdata ($HOST_PROFDATA) to match host compiler instrumentation..."
    profdata_bin="$HOST_PROFDATA"
  fi

  if ! "$profdata_bin" merge \
    -output="$BUILD_DIR/pgo.prof" \
    "${profiles[@]}"; then
    warn "llvm-profdata merge failed"
    return 1
  fi

  export PGO_PROF="$BUILD_DIR/pgo.prof"
  log "PGO profile ready: $PGO_PROF"
}

# ─── Intermediate Cleanup ─────────────────────────────────────────────────────
cleanup_stage1_artifacts() {
  log "Cleaning up Stage 1 artifacts to free disk space ..."
  local s1_build="$BUILD_DIR/stage1"

  # Remove Stage 1 build tree (keep stage1-install/bin/clang needed for Stage 2)
  if [[ -d "$s1_build" ]]; then
    local before
    before=$(du -sh "$s1_build" 2>/dev/null | cut -f1)
    rm -rf "$s1_build"
    log "Removed Stage 1 build dir: $before"
  fi

  # Remove raw .profraw files (already merged into pgo.prof)
  if [[ -d "$BUILD_DIR/profiles" ]]; then
    local before
    before=$(du -sh "$BUILD_DIR/profiles" 2>/dev/null | cut -f1)
    rm -rf "$BUILD_DIR/profiles"
    log "Removed raw profile data: $before"
  fi

  # Remove SQLite workload download
  if [[ -d "$BUILD_DIR/workload" ]]; then
    local before
    before=$(du -sh "$BUILD_DIR/workload" 2>/dev/null | cut -f1)
    rm -rf "$BUILD_DIR/workload"
    log "Removed workload files: $before"
  fi

  # Remove ccache stats (regenerated on demand)
  rm -f "$BUILD_DIR/.ccache_stats" 2>/dev/null || true

  # Remove unnecessary files from stage1-install to save space
  local s1_install="$BUILD_DIR/stage1-install"
  if [[ -d "$s1_install" ]]; then
    # Remove docs, examples, cmake files from stage1-install (not needed for stage2)
    rm -rf "$s1_install/lib/cmake" 2>/dev/null || true
    rm -rf "$s1_install/share" 2>/dev/null || true
    rm -rf "$s1_install/include" 2>/dev/null || true
    # Remove static libraries from stage1 (lib/*.a) — saves ~1GB, not needed for stage2
    find "$s1_install/lib" -name "*.a" -delete 2>/dev/null || true
    # Remove unnecessary stage1 binaries (keep only clang, clang++, lld, llvm-profdata)
    for tool in "$s1_install/bin/"*; do
      local name
      name=$(basename "$tool")
      case "$name" in
        clang*|lld*|ld.lld*|llvm-profdata*|llvm-ar*|llvm-nm*|llvm-objcopy*|llvm-objdump*|llvm-strip*)
          ;; # Keep these and versioned variants (e.g., clang-22)
        *)
          rm -f "$tool" 2>/dev/null || true
          ;;
      esac
    done
    log "Cleaned up stage1-install"
  fi

  # Prune LLVM git aggressively (saves ~1GB) — skip if .git already removed
  if [[ -d "$LLVM_DIR/.git" ]]; then
    log "Pruning LLVM git objects ..."
    git -C "$LLVM_DIR" gc --aggressive --prune=now 2>/dev/null || true
    git -C "$LLVM_DIR" reflog expire --expire=now --all 2>/dev/null || true
    rm -rf "$LLVM_DIR/.git/refs/remotes" 2>/dev/null || true
    rm -rf "$LLVM_DIR/.git/logs" 2>/dev/null || true
    rm -rf "$LLVM_DIR/.git/hooks" 2>/dev/null || true
    rm -rf "$LLVM_DIR/.git/info" 2>/dev/null || true
  fi

  # Clear ccache stats cache
  rm -f "$BUILD_DIR/.ccache_stats" 2>/dev/null || true

  # Remove ThinLTO cache from stage1 (not needed for stage2)
  rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true

  # Aggressively free more space
  sudo apt-get clean 2>/dev/null || true
  sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || true
  sudo rm -rf /tmp/* 2>/dev/null || true

  df -h / 2>/dev/null | tail -1 || true
  log "Disk cleanup complete"
}

# ─── Stage 2: Optimized Build (intermediate) ─────────────────────────────────
stage2_build() {
  local stage2_install="${1:-$BUILD_DIR/stage2-install}"
  log "Stage 2: Building optimized Clang (LTO=$LTO_MODE) → $stage2_install ..."
  local s2_build="$BUILD_DIR/stage2"

  # Prepend Stage 1 bin to PATH so that CMake and Clang find lld, llvm-profdata, etc.
  local old_path="$PATH"
  export PATH="$STAGE1_INSTALL/bin:$PATH"

  # Validate LTO mode
  case "$LTO_MODE" in
    Thin|Full|Off) ;;
    *) warn "Invalid LTO_MODE='$LTO_MODE', defaulting to Thin"; LTO_MODE="Thin" ;;
  esac

  # Enable runtimes (libcxx, libcxxabi) for stage2 — the only stage that needs them.
  local saved_runtimes="$LLVM_RUNTIMES"
  LLVM_RUNTIMES="libcxx;libcxxabi;libunwind"

  # Detect host CPU for native tuning flags
  local arch_flags=""
  if command -v clang &>/dev/null; then
    # Let Clang detect the host CPU and generate appropriate flags
    arch_flags="-march=native -mtune=native"
  fi

  cmake_configure "$LLVM_DIR" "$s2_build" "$stage2_install" "$LLVM_PROJECTS" "" \
    -DCMAKE_C_COMPILER="$STAGE1_CC" \
    -DCMAKE_CXX_COMPILER="$STAGE1_CXX" \
    -DCMAKE_C_FLAGS="$arch_flags" \
    -DCMAKE_CXX_FLAGS="$arch_flags" \
    -DLLVM_ENABLE_LTO="$LTO_MODE" \
    -DCOMPILER_RT_ENABLE_LTO=OFF \
    -DLLVM_PROFDATA_FILE="$PGO_PROF" \
    -DLLVM_ENABLE_PLUGINS=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CRT=OFF \
    -DPOLLY_ENABLE_LOOP_EXTRACT=ON
  LLVM_RUNTIMES="$saved_runtimes"

  # Ensure just-built shared libraries (libc++, libc++abi) are findable by child
  # processes.  The runtimes sub-build uses the just-built clang as its compiler;
  # without this, clang/ld.lld fail to start and CMake's linker-check aborts.
  local old_ld_path="${LD_LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="$s2_build/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  cmake --build "$s2_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  export LD_LIBRARY_PATH="$old_ld_path"

  # Free disk BEFORE install: remove object files + ThinLTO cache
  # Do NOT delete $s2_build/lib — cmake --install needs cmake_install.cmake scripts there
  log "Stage 2 build done. Cleaning object files + LTO cache before install ..."
  find "$s2_build" -name "*.o" -delete 2>/dev/null || true
  find "$s2_build" -name "*.obj" -delete 2>/dev/null || true
  rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true
  sudo apt-get clean 2>/dev/null || true
  sudo rm -rf /var/lib/apt/lists/* /tmp/* 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  cmake --install "$s2_build" 2>&1 | tee -a "$BUILD_DIR/build.log"

  # Ensure libc++ shared libraries are bundled in the toolchain
  bundle_libcxx "$s2_build"

  # Wipe entire stage2 build dir after install (saves ~15GB before BOLT)
  log "Removing Stage 2 build directory ..."
  rm -rf "$s2_build" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  export PATH="$old_path"
}

# ─── Stage 3: Final Optimized Build (3-stage PGO) ────────────────────────────
stage3_build() {
  log "Stage 3: Final optimized build using Stage 2 Clang + refined PGO ..."
  local s3_build="$BUILD_DIR/stage3"

  local old_path="$PATH"
  export PATH="$STAGE2_INSTALL/bin:$PATH"

  local arch_flags="-march=native -mtune=native"

  local saved_runtimes="$LLVM_RUNTIMES"
  LLVM_RUNTIMES="libcxx;libcxxabi;libunwind"

  cmake_configure "$LLVM_DIR" "$s3_build" "$INSTALL_DIR" "$LLVM_PROJECTS" "" \
    -DCMAKE_C_COMPILER="$STAGE2_INSTALL/bin/clang" \
    -DCMAKE_CXX_COMPILER="$STAGE2_INSTALL/bin/clang++" \
    -DCMAKE_C_FLAGS="$arch_flags" \
    -DCMAKE_CXX_FLAGS="$arch_flags" \
    -DLLVM_ENABLE_LTO="$LTO_MODE" \
    -DCOMPILER_RT_ENABLE_LTO=OFF \
    -DLLVM_PROFDATA_FILE="${PGO_PROF_2:-}" \
    -DLLVM_ENABLE_PLUGINS=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CRT=OFF \
    -DPOLLY_ENABLE_LOOP_EXTRACT=ON
  LLVM_RUNTIMES="$saved_runtimes"

  local old_ld_path="${LD_LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="$s3_build/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  cmake --build "$s3_build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  export LD_LIBRARY_PATH="$old_ld_path"

  log "Stage 3 build done. Cleaning object files + LTO cache before install ..."
  find "$s3_build" -name "*.o" -delete 2>/dev/null || true
  find "$s3_build" -name "*.obj" -delete 2>/dev/null || true
  rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true
  sudo apt-get clean 2>/dev/null || true
  sudo rm -rf /var/lib/apt/lists/* /tmp/* 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  cmake --install "$s3_build" 2>&1 | tee -a "$BUILD_DIR/build.log"
  bundle_libcxx "$s3_build"

  log "Removing Stage 3 build directory ..."
  rm -rf "$s3_build" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  export PATH="$old_path"
}

# ─── 3-Stage PGO Profile Collection ──────────────────────────────────────────
collect_profiles_stage2() {
  local workload="${PGO_WORKLOAD:-sqlite}"
  log "Stage 2 PGO: collecting refined profiles using Stage 2 Clang ..."

  local profile_dir="$BUILD_DIR/profiles-stage2"
  mkdir -p "$profile_dir"

  export LLVM_PROFILE_FILE="$profile_dir/oronyx-%p.profraw"
  export STAGE1_CC="$STAGE2_INSTALL/bin/clang"
  export STAGE1_CXX="$STAGE2_INSTALL/bin/clang++"
  export STAGE1_INSTALL="$STAGE2_INSTALL"

  if [[ "$workload" == "kernel" ]]; then
    collect_kernel || collect_sqlite || return 1
  elif [[ "$workload" == "llvm" ]]; then
    collect_llvm || collect_sqlite || return 1
  else
    collect_sqlite || return 1
  fi

  local profiles=("$profile_dir"/*.profraw)
  if [[ ${#profiles[@]} -eq 0 ]]; then
    warn "Stage 2 PGO: no profiles generated."
    return 1
  fi

  log "Merging Stage 2 PGO profiles ..."
  local profdata_bin="$STAGE2_INSTALL/bin/llvm-profdata"
  if ! "$profdata_bin" merge -output="$BUILD_DIR/pgo-stage2.prof" "${profiles[@]}"; then
    warn "llvm-profdata merge failed for stage2 profiles"
    return 1
  fi

  export PGO_PROF_2="$BUILD_DIR/pgo-stage2.prof"
  rm -rf "$profile_dir"
  log "Stage 2 PGO profile ready: $PGO_PROF_2"
}

# ─── BOLT Post-Build Optimization ────────────────────────────────────────────
apply_bolt() {
  [[ "$ENABLE_BOLT" == "true" ]] || return 0

  local llvm_bolt="${INSTALL_DIR}/bin/llvm-bolt"
  local perf2bolt="${INSTALL_DIR}/bin/perf2bolt"

  [[ -x "$llvm_bolt" ]] || { warn "llvm-bolt not found, skipping BOLT"; return 0; }
  command -v perf &>/dev/null || { warn "perf not found, skipping BOLT"; return 0; }

  local bolt_dir="$BUILD_DIR/bolt"
  mkdir -p "$bolt_dir"
  local bolt_report="$bolt_dir/report.txt"

  log "Applying BOLT optimization ..."
  echo "BOLT Optimization Report" > "$bolt_report"
  echo "=======================" >> "$bolt_report"
  echo "" >> "$bolt_report"

  # ─── Binaries to BOLT-optimize ────────────────────────────────────────────
  local targets=()
  if [[ -x "$INSTALL_DIR/bin/clang" ]]; then
    targets+=("$INSTALL_DIR/bin/clang:Compile C source:compile")
  fi
  if [[ -x "$INSTALL_DIR/bin/ld.lld" ]]; then
    targets+=("$INSTALL_DIR/bin/ld.lld:Link object files:link")
  fi
  if [[ -x "$INSTALL_DIR/bin/llvm-ar" ]]; then
    targets+=("$INSTALL_DIR/bin/llvm-ar:Archive static lib:archive")
  fi
  if [[ -x "$INSTALL_DIR/bin/llvm-objcopy" ]]; then
    targets+=("$INSTALL_DIR/bin/llvm-objcopy:Copy/convert binary:objcopy")
  fi
  if [[ -x "$INSTALL_DIR/bin/llvm-strip" ]]; then
    targets+=("$INSTALL_DIR/bin/llvm-strip:Strip binary:strip")
  fi

  for entry in "${targets[@]}"; do
    IFS=':' read -r bin_path bin_desc workload_type <<< "$entry"
    local bin_name; bin_name=$(basename "$bin_path")
    echo "────────────────────────────────────────" >> "$bolt_report"
    echo "Binary: $bin_name" >> "$bolt_report"
    echo "────────────────────────────────────────" >> "$bolt_report"

    local perf_data="$bolt_dir/${bin_name}.perf.data"
    local fdata="$bolt_dir/${bin_name}.fdata"
    local bolted_out="$bolt_dir/${bin_name}.bolt"
    local test_dir="$bolt_dir/workload-${bin_name}"
    mkdir -p "$test_dir"

    log "  BOLT: $bin_name ($bin_desc) ..."

    # Collect perf profile with binary-specific workload
    local perf_ok=false
    case "$workload_type" in
      compile)
        local test_c="$test_dir/test.c"
        echo 'int main(void) { return 0; }' > "$test_c"
        perf record -e cycles:u -j any,u -o "$perf_data" \
          "$bin_path" -c -O2 -o /dev/null "$test_c" 2>/dev/null && perf_ok=true
        ;;
      link)
        local test_a="$test_dir/a.o" test_b="$test_dir/b.o"
        echo 'int foo(void) { return 42; }' > "$test_dir/a.c"
        echo 'int foo(void); int main(void) { return foo(); }' > "$test_dir/b.c"
        if "$INSTALL_DIR/bin/clang" -c -o "$test_a" "$test_dir/a.c" 2>/dev/null &&
           "$INSTALL_DIR/bin/clang" -c -o "$test_b" "$test_dir/b.c" 2>/dev/null; then
          perf record -e cycles:u -j any,u -o "$perf_data" \
            "$bin_path" -o "$test_dir/test" "$test_a" "$test_b" 2>/dev/null && perf_ok=true
        fi
        ;;
      archive)
        local test_o="$test_dir/test.o"
        echo 'int test_func(void) { return 0; }' > "$test_dir/test.c"
        if "$INSTALL_DIR/bin/clang" -c -o "$test_o" "$test_dir/test.c" 2>/dev/null; then
          perf record -e cycles:u -j any,u -o "$perf_data" \
            "$bin_path" rcs "$test_dir/libtest.a" "$test_o" 2>/dev/null && perf_ok=true
        fi
        ;;
      objcopy|strip)
        local test_bin="$test_dir/test_copy"
        if [[ -x "$INSTALL_DIR/bin/clang" ]]; then
          cp "$INSTALL_DIR/bin/clang" "$test_dir/test_binary" 2>/dev/null || true
        fi
        if [[ -f "$test_dir/test_binary" ]]; then
          local copy_cmd=("$bin_path")
          [[ "$workload_type" == "strip" ]] && copy_cmd+=(--strip-all -g)
          copy_cmd+=("$test_dir/test_binary" "$test_bin")
          perf record -e cycles:u -j any,u -o "$perf_data" \
            "${copy_cmd[@]}" 2>/dev/null && perf_ok=true
        fi
        ;;
    esac

    if [[ "$perf_ok" != "true" ]]; then
      warn "    Perf record failed for $bin_name, skipping"
      rm -rf "$test_dir"
      continue
    fi

    [[ -s "$perf_data" ]] || { warn "    No perf data for $bin_name"; rm -rf "$test_dir"; continue; }

    # Convert perf data to BOLT format
    if [[ -x "$perf2bolt" ]]; then
      "$perf2bolt" -p "$perf_data" -o "$fdata" "$bin_path" 2>/dev/null || {
        warn "    perf2bolt failed for $bin_name"
        rm -rf "$test_dir"
        continue
      }
    else
      warn "    perf2bolt not found, skipping"
      rm -rf "$test_dir"
      continue
    fi

    # Apply BOLT optimization
    "$llvm_bolt" "$bin_path" \
      -data="$fdata" \
      -o "$bolted_out" \
      -reorder-blocks=ext-tsp \
      -reorder-functions=hfsort+ \
      -split-functions \
      -split-all-cold \
      -dyno-stats \
      -icf=1 \
      -use-gnu-stack \
      2>&1 | tee -a "$BUILD_DIR/build.log" || {
      warn "    BOLT optimization failed for $bin_name"
      rm -rf "$test_dir"
      continue
    }

    # Replace original binary
    if [[ -s "$bolted_out" ]]; then
      local original_size bolted_size saved_pct=0
      original_size=$(stat -c%s "$bin_path" 2>/dev/null || stat -f%z "$bin_path" 2>/dev/null || echo 0)
      bolted_size=$(stat -c%s "$bolted_out" 2>/dev/null || stat -f%z "$bolted_out" 2>/dev/null || echo 0)

      cp "$bolted_out" "$bin_path"
      chmod +x "$bin_path"

      if [[ "$original_size" -gt 0 ]]; then
        saved_pct=$(( (original_size - bolted_size) * 100 / original_size ))
      fi

      local result="OK: ${original_size} → ${bolted_size} bytes (${saved_pct}% smaller)"
      log "    $bin_name: $result"
      echo "$result" >> "$bolt_report"
    else
      warn "    BOLT output empty for $bin_name"
    fi

    rm -rf "$test_dir"
  done

  log "BOLT report: $bolt_report"
}

# ─── Simple Build (no PGO) ────────────────────────────────────────────────────
simple_build() {
  log "Building OronyxClang (no PGO, LTO=$LTO_MODE) ..."
  local build="$BUILD_DIR/simple"
  local cc="" cxx=""
  local old_path="$PATH"

  # Validate LTO mode
  case "$LTO_MODE" in
    Thin|Full|Off) ;;
    *) warn "Invalid LTO_MODE='$LTO_MODE', defaulting to Thin"; LTO_MODE="Thin" ;;
  esac

  # Use Stage 1 Clang if available, else host Clang, else no LTO
  if [[ -n "${STAGE1_CC:-}" && -x "${STAGE1_CC:-}" ]]; then
    cc="$STAGE1_CC"; cxx="$STAGE1_CXX"
    export PATH="$STAGE1_INSTALL/bin:$PATH"
  elif [[ "$HOST_HAS_CLANG" == "true" ]]; then
    cc="$HOST_CC"; cxx="$HOST_CXX"
  else
    LTO_MODE="Off"
  fi

  local cmake_args=()
  if [[ -n "$cc" ]]; then
    local arch_flags="-march=native -mtune=native"
    cmake_args+=(-DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" -DLLVM_ENABLE_LTO="$LTO_MODE")
    cmake_args+=(-DCMAKE_C_FLAGS="$arch_flags" -DCMAKE_CXX_FLAGS="$arch_flags")
  else
    warn "No Clang host compiler found — building without LTO"
    cmake_args+=(-DLLVM_ENABLE_LTO=Off)
  fi

  # Runtimes (libcxx, libcxxabi) are only built in stage2 via cmake_configure.
  # simple_build() skips them because the just-built Clang targets AArch64
  # (via CLANG_DEFAULT_TARGET_TRIPLE) but the runtimes sub-build runs on the
  # x86_64 host, causing CMake compiler detection to fail.
  cmake_configure "$LLVM_DIR" "$build" "$INSTALL_DIR" "$LLVM_PROJECTS" "" "${cmake_args[@]}"

  # Prepend build bin to PATH so the just-built clang can find lld, llvm-ar, etc.
  export PATH="$build/bin:$PATH"

  # Ensure just-built shared libraries are findable by child processes.
  local old_ld_path="${LD_LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="$build/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  cmake --build "$build" -j"$JOBS" 2>&1 | tee -a "$BUILD_DIR/build.log"
  export LD_LIBRARY_PATH="$old_ld_path"

  # Free disk BEFORE install: remove object files + ThinLTO cache
  # Do NOT delete $build/lib — cmake --install needs cmake_install.cmake scripts there
  log "Build done. Cleaning object files before install ..."
  find "$build" -name "*.o" -delete 2>/dev/null || true
  find "$build" -name "*.obj" -delete 2>/dev/null || true
  rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  cmake --install "$build" 2>&1 | tee -a "$BUILD_DIR/build.log"

  # Wipe entire build dir after install
  log "Removing build directory ..."
  rm -rf "$build" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  export PATH="$old_path"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  detect_host_compiler
  BUILD_DATE=$(date -u +%Y-%m-%d)
  PATCH_COUNT=0

  if ls "$REPO_DIR/patches/"*.patch &>/dev/null 2>&1; then
    PATCH_COUNT=$(ls -1 "$REPO_DIR/patches/"*.patch 2>/dev/null | wc -l)
  fi

  export LLVM_BRANCH BUILD_DATE LTO_MODE PATCH_COUNT ZSTD_LEVEL
  export GITHUB_RUN_NUMBER="${GITHUB_RUN_NUMBER:-}"
  export GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
  export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

  # ── Pre-flight disk space check ─────────────────────────────────────────────
  local avail_kb
  avail_kb=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ')
  if [[ -n "$avail_kb" ]]; then
    local avail_gb=$((avail_kb / 1048576))
    log "Available disk space: ${avail_gb}GB"
    if [[ "$avail_kb" -lt 10000000 ]]; then
      die "Not enough disk space (${avail_gb}GB available, need ~10GB minimum). Aborting."
    fi
  fi

  log "Starting OronyxClang build (PGO=$ENABLE_PGO, LTO=$LTO_MODE, JOBS=$JOBS) ..."
  mkdir -p "$BUILD_DIR"

  # Clone LLVM first — set commit AFTER clone so notification has correct info
  BUILD_STAGE="Cloning LLVM"
  export BUILD_STAGE
  stage_timer_start "clone"
  clone_llvm
  stage_timer_end "clone"

  # Get commit hash BEFORE cleaning up .git
  LLVM_COMMIT=$(git -C "$LLVM_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  LLVM_COMMIT_FULL=$(git -C "$LLVM_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
  export LLVM_COMMIT LLVM_COMMIT_FULL

  # Aggressively clean LLVM source tree to save disk space
  log "Cleaning LLVM source tree (removing tests, docs, examples) ..."
  rm -rf "$LLVM_DIR/llvm/test" 2>/dev/null || true
  rm -rf "$LLVM_DIR/clang/test" 2>/dev/null || true
  rm -rf "$LLVM_DIR/lld/test" 2>/dev/null || true
  rm -rf "$LLVM_DIR/compiler-rt/test" 2>/dev/null || true
  rm -rf "$LLVM_DIR/polly/test" 2>/dev/null || true
  rm -rf "$LLVM_DIR/docs" 2>/dev/null || true
  rm -rf "$LLVM_DIR/llvm/docs" 2>/dev/null || true
  rm -rf "$LLVM_DIR/clang/docs" 2>/dev/null || true
  rm -rf "$LLVM_DIR/llvm/examples" 2>/dev/null || true
  rm -rf "$LLVM_DIR/clang/examples" 2>/dev/null || true
  rm -rf "$LLVM_DIR/llvm/utils/lit" 2>/dev/null || true
  rm -rf "$LLVM_DIR/llvm/unittests" 2>/dev/null || true
  df -h / 2>/dev/null | tail -1 || true

  BUILD_STAGE="Applying patches"
  export BUILD_STAGE
  stage_timer_start "patches"
  apply_patches
  stage_timer_end "patches"

  # Now remove .git AFTER patches applied (git apply needs it)
  rm -rf "$LLVM_DIR/.git" 2>/dev/null || true
  log "Removed LLVM .git directory"
  df -h / 2>/dev/null | tail -1 || true

  BUILD_SUCCESS=false
  if [[ "$ENABLE_PGO" == "true" ]]; then
    export STAGE1_INSTALL="$BUILD_DIR/stage1-install"

    check_disk_space 5000000 "Stage 1"
    BUILD_STAGE="Stage 1: Instrumented build"
    export BUILD_STAGE
    stage_timer_start "stage1"
    stage1_build
    stage_timer_end "stage1"

    log "Available disk after Stage 1: $(df -h / | tail -1 | awk '{print $4}')"

    BUILD_STAGE="PGO profile collection (1)"
    export BUILD_STAGE
    stage_timer_start "pgo_collect"
    if collect_profiles; then
      stage_timer_end "pgo_collect"
      cleanup_stage1_artifacts

      # ── Aggressive disk cleanup before Stage 2 ─────────────────────────────
      log "Performing aggressive disk cleanup before Stage 2 ..."
      rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true
      rm -rf "$BUILD_DIR/profiles" 2>/dev/null || true
      rm -rf "$BUILD_DIR/workload" 2>/dev/null || true
      rm -f "$BUILD_DIR/.ccache_stats" 2>/dev/null || true
      sudo apt-get clean 2>/dev/null || true
      sudo rm -rf /var/lib/apt/lists/* /tmp/* 2>/dev/null || true
      # Prune ccache to minimum
      if command -v ccache &>/dev/null; then
        ccache --set-config=max_size=500M 2>/dev/null || true
        ccache -c 2>/dev/null || true
      fi
      df -h / 2>/dev/null | tail -1 || true

      # ── Stage 2 (intermediate) ─────────────────────────────────────────────
      log "Available disk before Stage 2: $(df -h / | tail -1 | awk '{print $4}')"
      check_disk_space 6000000 "Stage 2"
      BUILD_STAGE="Stage 2: Optimized build (intermediate)"
      export BUILD_STAGE
      stage_timer_start "stage2"
      export STAGE2_INSTALL="$BUILD_DIR/stage2-install"
      stage2_build "$STAGE2_INSTALL"
      stage_timer_end "stage2"

      # ── Stage 2 PGO collection ─────────────────────────────────────────────
      log "Available disk before Stage 2 PGO: $(df -h / | tail -1 | awk '{print $4}')"
      BUILD_STAGE="PGO profile collection (2)"
      export BUILD_STAGE
      stage_timer_start "pgo_collect2"
      if collect_profiles_stage2; then
        stage_timer_end "pgo_collect2"

        # ── Aggressive disk cleanup before Stage 3 ──────────────────────────
        log "Performing aggressive disk cleanup before Stage 3 ..."
        rm -rf "$BUILD_DIR/lto-cache" 2>/dev/null || true
        rm -rf "$BUILD_DIR/profiles-stage2" 2>/dev/null || true
        sudo apt-get clean 2>/dev/null || true
        sudo rm -rf /var/lib/apt/lists/* /tmp/* 2>/dev/null || true
        if command -v ccache &>/dev/null; then
          ccache -c 2>/dev/null || true
        fi
        df -h / 2>/dev/null | tail -1 || true

        # ── Stage 3 (final) ──────────────────────────────────────────────────
        log "Available disk before Stage 3: $(df -h / | tail -1 | awk '{print $4}')"
        check_disk_space 6000000 "Stage 3"
        BUILD_STAGE="Stage 3: Final optimized build"
        export BUILD_STAGE
        stage_timer_start "stage3"
        stage3_build
        stage_timer_end "stage3"

        # Cleanup stage2 install AFTER stage3 uses it
        log "Cleaning Stage 2 install dir ..."
        rm -rf "$STAGE2_INSTALL" 2>/dev/null || true
        df -h / 2>/dev/null | tail -1 || true

        BUILD_STAGE="BOLT optimization"
        export BUILD_STAGE
        stage_timer_start "bolt"
        apply_bolt
        stage_timer_end "bolt"
        BUILD_SUCCESS=true
      else
        stage_timer_end "pgo_collect2"
        warn "Stage 2 PGO collection failed. Falling back to Stage 2 build."
        # Move stage2 install to final location
        if [[ -d "$STAGE2_INSTALL/bin" ]]; then
          log "Using Stage 2 build as final ..."
          mkdir -p "$INSTALL_DIR"
          for _d in "$STAGE2_INSTALL"/* "$STAGE2_INSTALL"/.[!.]*; do
            [[ -e "$_d" ]] && mv "$_d" "$INSTALL_DIR/"
          done
          rm -rf "$STAGE2_INSTALL" 2>/dev/null || true
          BUILD_STAGE="BOLT optimization"
          export BUILD_STAGE
          stage_timer_start "bolt"
          apply_bolt
          stage_timer_end "bolt"
          BUILD_SUCCESS=true
        fi
      fi
    else
      stage_timer_end "pgo_collect"
      warn "PGO profile collection failed. Falling back to non-PGO build."
      ENABLE_PGO="false"
      export ENABLE_PGO
      BUILD_STAGE="Simple build (no PGO fallback)"
      export BUILD_STAGE
      check_disk_space 5000000 "Simple build"
      stage_timer_start "simple"
      simple_build
      stage_timer_end "simple"
      BUILD_SUCCESS=true
    fi
  else
    BUILD_STAGE="Simple build"
    export BUILD_STAGE
    check_disk_space 5000000 "Simple build"
    stage_timer_start "simple"
    simple_build
    stage_timer_end "simple"
    BUILD_SUCCESS=true
  fi

  if [[ "$BUILD_SUCCESS" == "true" ]]; then
    BUILD_STAGE="Packaging"
    export BUILD_STAGE
    CLANG_VERSION=$("$INSTALL_DIR/bin/clang" --version | head -1 | grep -oP '\d+\.\d+\.\d+\S*' | head -1)
    BUILD_DURATION=$(build_duration)
    export CLANG_VERSION BUILD_DURATION
    local changelog_file; changelog_file=$(gen_changelog)
    export CHANGELOG_FILE="$changelog_file"

    # Generate build metadata
    local metadata="$BUILD_DIR/build_metadata.json"
    {
      echo "{"
      echo "  \"llvm_branch\": \"$LLVM_BRANCH\","
      echo "  \"llvm_commit\": \"$LLVM_COMMIT\","
      echo "  \"clang_version\": \"$CLANG_VERSION\","
      echo "  \"build_date\": \"$BUILD_DATE\","
      echo "  \"pgo\": $ENABLE_PGO,"
      echo "  \"bolt\": $ENABLE_BOLT,"
      echo "  \"lto\": \"$LTO_MODE\","
      echo "  \"jobs\": $JOBS,"
      echo "  \"zstd_level\": $ZSTD_LEVEL,"
      echo "  \"patches\": $PATCH_COUNT,"
      echo "  \"duration\": \"$BUILD_DURATION\","
      echo "  \"stages\": {"
      local first=true
      for key in clone patches stage1 pgo_collect stage2 pgo_collect2 stage3 bolt simple; do
        if [[ -n "${STAGE_TIMES[$key]:-}" ]]; then
          [[ "$first" == "true" ]] || echo ","
          printf '    "%s": %d' "$key" "${STAGE_TIMES[$key]}"
          first=false
        fi
      done
      echo ""
      echo "  }"
      echo "}"
    } > "$metadata"
    log "Build metadata: $metadata"

    # LLVM commit info was saved before .git removal — ensure package.sh uses it
    export LLVM_COMMIT LLVM_COMMIT_FULL

    # Final cleanup: remove LLVM source tree to free disk space for packaging
    log "Cleaning up LLVM source tree ..."
    rm -rf "$LLVM_DIR"
    df -h / 2>/dev/null | tail -1 || true

    log "Build complete! Toolchain installed to: $INSTALL_DIR"
    log "Clang version: $CLANG_VERSION"
    notify success
  fi
}

cleanup() {
  local exit_code=$?
  if [[ "${NOTIFIED_FAILURE:-false}" == "true" ]]; then
    return
  fi
  if [[ $exit_code -ne 0 ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
    BUILD_DURATION=$(build_duration 2>/dev/null || echo "unknown")

    # Capture error from build.log if it exists
    local error_log=""
    if [[ -f "$BUILD_DIR/build.log" && -s "$BUILD_DIR/build.log" ]]; then
      error_log=$(tail -c 4000 "$BUILD_DIR/build.log" 2>/dev/null || true)
    fi

    export BUILD_DURATION
    export ERROR_LOG="${error_log:-${ERROR_LOG:-}}"
    export BUILD_STAGE="Build Failed"
    export ERROR_DUMP_CHAT_ID="${ERROR_DUMP_CHAT_ID:-}"
    export ERROR_DUMP_FILE="${ERROR_DUMP_FILE:-$BUILD_DIR/build.log}"
    bash "$NOTIFY_SCRIPT" failure || true
    bash "$NOTIFY_SCRIPT" error_dump || true
  fi
}
trap cleanup EXIT

main "$@"
