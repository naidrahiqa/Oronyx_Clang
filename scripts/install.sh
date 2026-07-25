#!/usr/bin/env bash
# Oronyx Clang — One-liner Installer
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/scripts/install.sh)
set -euo pipefail

DIR="${ORONYX_DIR:-$(pwd)}"
CLANG_DIR="$DIR/oronyx-clang"
REPO="naidrahiqa/Oronyx_Clang"
BASE_URL="https://raw.githubusercontent.com/$REPO/main"

# ─── Color helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
  CYAN='\033[1;36m'; NC='\033[0m'; BOLD='\033[1m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''; BOLD=''
fi

info()  { echo -e "${CYAN}[$1/$TOTAL]${NC} $2"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
header(){ echo -e "${BOLD}$1${NC}"; }

TOTAL=7

header "═══════════════════════════════════════════"
header "  Oronyx Clang Installer"
header "═══════════════════════════════════════════"
echo "  Working directory : $DIR"
echo "  Install directory : $CLANG_DIR"
echo ""

# ─── [1/7] Validate dependencies ─────────────────────────────────────────────
info 1 "Checking dependencies ..."
DEPS=(wget tar zstd curl)
MISSING=()
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    MISSING+=("$dep")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  fail "Missing: ${MISSING[*]}"
fi
ok "All dependencies found"

# ─── [2/7] Fetch latest release URL ──────────────────────────────────────────
info 2 "Fetching latest release URL ..."
LATEST_URL=""

# Preferred: source get_latest_url.sh from repo (only var assignments, safe)
URL_SCRIPT=$(curl -sL "$BASE_URL/get_latest_url.sh" 2>/dev/null || true)
if [[ -n "$URL_SCRIPT" ]]; then
  eval "$(echo "$URL_SCRIPT" | grep -E '^LATEST_URL=' || true)"
fi

# Fallback 1: read latest.txt from repo
if [[ -z "$LATEST_URL" ]]; then
  LATEST_URL=$(curl -sL "$BASE_URL/latest.txt" 2>/dev/null || true)
fi

# Fallback 2: GitHub API
if [[ -z "$LATEST_URL" ]]; then
  LATEST_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | \
    grep -oP '"browser_download_url":\s*"\K[^"]+\.tar\.zst' | head -1 || true)
fi

if [[ -z "$LATEST_URL" ]]; then
  fail "Failed to fetch latest release URL"
fi
ok "$(basename "$LATEST_URL")"

# ─── [3/7] Clean up old installation ─────────────────────────────────────────
info 3 "Preparing install directory ..."
if [[ -d "$CLANG_DIR/bin" ]]; then
  warn "Removing old installation at $CLANG_DIR ..."
  rm -rf "$CLANG_DIR"
  ok "Old installation removed"
fi
mkdir -p "$CLANG_DIR"
ok "Directory ready"

# ─── [4/7] Download & extract ────────────────────────────────────────────────
info 4 "Downloading and extracting ..."
if wget -qO- "$LATEST_URL" | tar -I zstd -xf - -C "$CLANG_DIR" --strip-components=1; then
  ok "Download and extraction complete"
else
  fail "Download or extraction failed"
fi

# ─── [5/7] Fix ld symlink ────────────────────────────────────────────────────
info 5 "Fixing ld symlink ..."
if [[ -f "$CLANG_DIR/bin/ld.lld" && ! -e "$CLANG_DIR/bin/ld" ]]; then
  ln -sf ld.lld "$CLANG_DIR/bin/ld"
  ok "ld → ld.lld symlink created"
else
  ok "ld symlink already in place"
fi

# ─── [6/7] Set up toolchain file (optional) ──────────────────────────────────
info 6 "Setting up toolchain file ..."
TOOLCHAIN_FILE="$CLANG_DIR/toolchain.cmake"
if [[ ! -f "$TOOLCHAIN_FILE" ]]; then
  cat > "$TOOLCHAIN_FILE" <<- CMAKEEOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSROOT $CLANG_DIR/sysroot)
set(CMAKE_C_COMPILER $CLANG_DIR/bin/clang)
set(CMAKE_CXX_COMPILER $CLANG_DIR/bin/clang++)
set(CMAKE_LINKER $CLANG_DIR/bin/ld.lld)
set(CMAKE_AR $CLANG_DIR/bin/llvm-ar)
set(CMAKE_RANLIB $CLANG_DIR/bin/llvm-ranlib)
set(CMAKE_NM $CLANG_DIR/bin/llvm-nm)
CMAKEEOF
  ok "Toolchain file created at toolchain.cmake"
else
  ok "Toolchain file already exists"
fi

# ─── [7/7] Verify ────────────────────────────────────────────────────────────
info 7 "Verifying installation ..."
if [[ -x "$CLANG_DIR/bin/clang" ]]; then
  VERSION=$("$CLANG_DIR/bin/clang" --version | head -1)
  ok "$VERSION"
else
  fail "clang binary not found"
fi

echo ""
header "═══════════════════════════════════════════"
header "  Installation complete!"
header "═══════════════════════════════════════════"
echo ""
echo "  ${BOLD}Add to your PATH:${NC}"
echo "    export PATH=\"$CLANG_DIR/bin:\$PATH\""
echo ""
echo "  ${BOLD}Or add to ~/.bashrc / ~/.zshrc:${NC}"
echo "    echo 'export PATH=\"$CLANG_DIR/bin:\$PATH\"' >> ~/.bashrc"
echo ""
header "═══════════════════════════════════════════"
