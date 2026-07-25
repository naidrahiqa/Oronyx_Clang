#!/usr/bin/env bash
# OronyxClang — Build Test Script
# Validates that build scripts are syntactically correct and tools are available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

GRN="\033[0;32m"
RED="\033[0;31m"
YLW="\033[0;33m"
RST="\033[0m"

ok()   { echo -e " ${GRN}PASS${RST} $1"; ((PASS++)); }
fail() { echo -e " ${RED}FAIL${RST} $1"; ((FAIL++)); }
warn() { echo -e " ${YLW}WARN${RST} $1"; }

echo "OronyxClang Build Tests"
echo "======================="
echo ""

# ─── 1. Check required files exist ─────────────────────────────────────────
echo "1. Required files"
for f in scripts/build.sh scripts/package.sh scripts/patch.sh scripts/notify.sh; do
  if [[ -f "$SCRIPT_DIR/$f" ]]; then
    ok "$f exists"
  else
    fail "$f missing"
  fi
done

# ─── 2. Check scripts are executable ────────────────────────────────────────
echo ""
echo "2. Script permissions"
for f in scripts/*.sh get_clang.sh; do
  if [[ -x "$SCRIPT_DIR/$f" ]]; then
    ok "$f is executable"
  else
    warn "$f is not executable (chmod +x)"
  fi
done

# ─── 3. Bash syntax check ──────────────────────────────────────────────────
echo ""
echo "3. Bash syntax"
for f in scripts/*.sh get_clang.sh; do
  if bash -n "$SCRIPT_DIR/$f" 2>/dev/null; then
    ok "$f syntax OK"
  else
    fail "$f has syntax errors"
  fi
done

# ─── 4. Check VERSION file ─────────────────────────────────────────────────
echo ""
echo "4. Version"
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
  VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
  ok "VERSION = $VERSION"
else
  fail "VERSION file missing"
fi

# ─── 5. Check LICENSE file ─────────────────────────────────────────────────
echo ""
echo "5. License"
if [[ -f "$SCRIPT_DIR/LICENSE" ]]; then
  if grep -q "Apache License" "$SCRIPT_DIR/LICENSE"; then
    ok "LICENSE is Apache-2.0"
  else
    warn "LICENSE exists but may not be Apache-2.0"
  fi
else
  fail "LICENSE file missing"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "======================="
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}FAILED${RST} — $FAIL failed, $PASS passed"
  exit 1
else
  echo -e "${GRN}PASSED${RST} — $PASS tests passed"
  exit 0
fi
