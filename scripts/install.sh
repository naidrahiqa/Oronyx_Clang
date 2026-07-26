#!/usr/bin/env bash
# Oronyx Clang — One-liner Installer (delegates to get_clang.sh)
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/scripts/install.sh)
set -euo pipefail

REPO="naidrahiqa/Oronyx_Clang"
BASE_URL="https://raw.githubusercontent.com/$REPO/main"
INSTALL_DIR="${ORONYX_DIR:-$HOME/toolchains/oronyx}"

# ─── Color helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
  CYAN='\033[1;36m'; NC='\033[0m'; BOLD='\033[1m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''; BOLD=''
fi

info()  { echo -e "${CYAN}$1${NC} $2"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
header(){ echo -e "${BOLD}$1${NC}"; }

header "═══════════════════════════════════════════"
header "  Oronyx Clang Installer"
header "═══════════════════════════════════════════"
echo "  Install directory: $INSTALL_DIR"
echo ""

# ─── Step 1: Download via get_clang.sh ───────────────────────────────────────
info "Step 1" "Running get_clang.sh ..."

GET_CLANG_SCRIPT=$(curl -sL "$BASE_URL/get_clang.sh" 2>/dev/null || true)
if [[ -z "$GET_CLANG_SCRIPT" ]]; then
  fail "Failed to fetch get_clang.sh from repo"
fi

# Run get_clang.sh with ORONYX_DIR set to our target
ORONYX_DIR="$INSTALL_DIR" bash <(echo "$GET_CLANG_SCRIPT")

# ─── Step 2: Set up toolchain.cmake ──────────────────────────────────────────
info "Step 2" "Setting up toolchain.cmake ..."
TOOLCHAIN_FILE="$INSTALL_DIR/toolchain.cmake"
if [[ ! -f "$TOOLCHAIN_FILE" ]]; then
  cat > "$TOOLCHAIN_FILE" <<- CMAKEEOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSROOT $INSTALL_DIR/sysroot)
set(CMAKE_C_COMPILER $INSTALL_DIR/bin/clang)
set(CMAKE_CXX_COMPILER $INSTALL_DIR/bin/clang++)
set(CMAKE_LINKER $INSTALL_DIR/bin/ld.lld)
set(CMAKE_AR $INSTALL_DIR/bin/llvm-ar)
set(CMAKE_RANLIB $INSTALL_DIR/bin/llvm-ranlib)
set(CMAKE_NM $INSTALL_DIR/bin/llvm-nm)
CMAKEEOF
  ok "toolchain.cmake created"
else
  ok "toolchain.cmake already exists"
fi

echo ""
header "═══════════════════════════════════════════"
header "  Installation complete!"
header "═══════════════════════════════════════════"
echo ""
echo "  ${BOLD}Add to your PATH:${NC}"
echo "    export PATH=\"$INSTALL_DIR/bin:\$PATH\""
echo ""
echo "  ${BOLD}Or add to ~/.bashrc / ~/.zshrc:${NC}"
echo "    echo 'export PATH=\"$INSTALL_DIR/bin:\$PATH\"' >> ~/.bashrc"
echo ""
header "═══════════════════════════════════════════"
