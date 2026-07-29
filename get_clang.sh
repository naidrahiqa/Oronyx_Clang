#!/usr/bin/env bash
# Oronyx Clang — One-liner Installer
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/get_clang.sh)
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

info()  { echo -e "${CYAN}[$1/$TOTAL]${NC} $2"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
header(){ echo -e "${BOLD}$1${NC}"; }

TOTAL=6

header "═══════════════════════════════════════════"
header "  Oronyx Clang Installer"
header "═══════════════════════════════════════════"
echo "  Directory: $INSTALL_DIR"
echo ""

# ─── [1/6] Validate dependencies ─────────────────────────────────────────────
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

# ─── [2/6] Fetch latest release URL ──────────────────────────────────────────
info 2 "Fetching latest release URL ..."
LATEST_URL=""

# Preferred: read get_latest_url.sh from repo (only var assignments, safe)
URL_SCRIPT=$(curl -sL "$BASE_URL/get_latest_url.sh" 2>/dev/null || true)
if [[ -n "$URL_SCRIPT" ]]; then
  LATEST_URL=$(echo "$URL_SCRIPT" | grep -E '^LATEST_URL=' | head -1 | cut -d= -f2- | tr -d '"' || true)
fi

# Fallback 1: read latest.txt from repo
if [[ -z "$LATEST_URL" ]]; then
  LATEST_URL=$(curl -sL "$BASE_URL/latest.txt" 2>/dev/null || true)
fi

# Fallback 2: GitHub API
if [[ -z "$LATEST_URL" ]]; then
  API_JSON=$(curl -sL --retry 3 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || true)
  if command -v jq &>/dev/null; then
    LATEST_URL=$(echo "$API_JSON" | jq -r '.assets[] | select(.name | endswith(".tar.zst")) | .browser_download_url' 2>/dev/null | head -1 || true)
  else
    LATEST_URL=$(echo "$API_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+\.tar\.zst' | head -1 || true)
  fi
fi

if [[ -z "$LATEST_URL" ]]; then
  fail "Failed to fetch latest release URL"
fi
ok "$(basename "$LATEST_URL")"

# ─── [3/6] Clean up old installation ─────────────────────────────────────────
info 3 "Preparing install directory ..."
if [[ -d "$INSTALL_DIR/bin" ]]; then
  warn "Removing old installation at $INSTALL_DIR ..."
  rm -rf "$INSTALL_DIR"
  ok "Old installation removed"
fi
mkdir -p "$INSTALL_DIR"
ok "Directory ready"

# ─── [4/6] Download & extract ────────────────────────────────────────────────
info 4 "Downloading and extracting ..."
TMPFILE="$(mktemp /tmp/oronyx-clang-XXXXXX.tar.zst)"
trap 'rm -f "$TMPFILE"' EXIT

if ! wget -qO "$TMPFILE" "$LATEST_URL"; then
  fail "Download failed"
fi

# Verify archive integrity before extraction
if ! tar -I zstd -tf "$TMPFILE" >/dev/null 2>&1; then
  fail "Downloaded archive is corrupted or not a valid zstd tar"
fi

if tar -I zstd -xf "$TMPFILE" -C "$INSTALL_DIR" --strip-components=1; then
  ok "Download and extraction complete"
else
  fail "Extraction failed"
fi

# ─── [5/6] Fix ld symlink ────────────────────────────────────────────────────
info 5 "Fixing ld symlink ..."
if [[ -f "$INSTALL_DIR/bin/ld.lld" && ! -e "$INSTALL_DIR/bin/ld" ]]; then
  ln -sf ld.lld "$INSTALL_DIR/bin/ld"
  ok "ld → ld.lld symlink created"
else
  ok "ld symlink already in place"
fi

# ─── [6/6] Verify ────────────────────────────────────────────────────────────
info 6 "Verifying installation ..."
if [[ -x "$INSTALL_DIR/bin/clang" ]]; then
  VERSION=$("$INSTALL_DIR/bin/clang" --version | head -1)
  ok "$VERSION"
else
  fail "clang binary not found"
fi

echo ""
header "═══════════════════════════════════════════"
header "  Installation complete!"
header "═══════════════════════════════════════════"
echo ""
echo "  ${BOLD}Add to your shell profile:${NC}"
echo "    export PATH=\"$INSTALL_DIR/bin:\$PATH\""
echo ""
echo "  ${BOLD}Or run directly:${NC}"
echo "    $INSTALL_DIR/bin/clang --version"
echo ""
header "═══════════════════════════════════════════"
