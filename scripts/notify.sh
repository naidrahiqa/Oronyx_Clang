#!/usr/bin/env bash
# Oronyx Clang — Telegram Notification Script
# Sends build status notifications via Telegram Bot API with HTML formatting.
# Usage: ./notify.sh <started|success|failure|error_dump|changelog|release>
set -euo pipefail

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
MESSAGE_TYPE="${1:-}"

[[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]] || exit 0

escape_html() {
  local input="$1"
  echo "$input" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

send_msg() {
  local text="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$text" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true > /dev/null 2>&1 || true
}

send_msg_to() {
  local cid="$1" text="$2"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$cid" \
    -d text="$text" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true > /dev/null 2>&1 || true
}

# ─── Build metadata ───────────────────────────────────────────────────────────
RUN_NUMBER="${GITHUB_RUN_NUMBER:-local}"
RUN_ID="${GITHUB_RUN_ID:-0}"
REPO="${GITHUB_REPOSITORY:-naidrahiqa/Oronyx_Clang}"
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
ORONYX_COMMIT="${GITHUB_SHA:-unknown}"

CLANG_VERSION="${CLANG_VERSION:-unknown}"
LLVM_BRANCH="${LLVM_BRANCH:-main}"
LLVM_COMMIT="${LLVM_COMMIT:-unknown}"
ENABLE_PGO="${ENABLE_PGO:-true}"
ENABLE_BOLT="${ENABLE_BOLT:-true}"
LTO_MODE="${LTO_MODE:-Thin}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%d)}"
RELEASE_TAG="${RELEASE_TAG:-}"
CHANGELOG_FILE="${CHANGELOG_FILE:-}"
BUILD_DURATION="${BUILD_DURATION:-}"
BUILD_STAGE="${BUILD_STAGE:-}"
ERROR_LOG="${ERROR_LOG:-}"
PACKAGE_SIZE="${PACKAGE_SIZE:-}"
PATCH_COUNT="${PATCH_COUNT:-0}"
TARBALL_NAME="${TARBALL_NAME:-}"
TARGETS="${LLVM_TARGETS:-AArch64;ARM;X86}"
ERROR_DUMP_CHAT_ID="${ERROR_DUMP_CHAT_ID:-}"
ERROR_DUMP_FILE="${ERROR_DUMP_FILE:-}"

# ─── Helpers ──────────────────────────────────────────────────────────────────
DIVIDER="━━━━━━━━━━━━━━━━━━━━"

# Convert llvmorg-22.1.8 → 22.1.8, main → Rolling
llvm_version() {
  if [[ "$LLVM_BRANCH" == "main" ]]; then
    echo "Rolling (main)"
  else
    echo "${LLVM_BRANCH#llvmorg-}"
  fi
}

# Build mode summary: PGO+BOLT, PGO only, or plain
build_mode() {
  local mode=""
  if [[ "$ENABLE_PGO" == "true" && "$ENABLE_BOLT" == "true" ]]; then
    mode="PGO+BOLT"
  elif [[ "$ENABLE_PGO" == "true" ]]; then
    mode="PGO"
  elif [[ "$ENABLE_BOLT" == "true" ]]; then
    mode="BOLT"
  else
    mode="Plain"
  fi
  echo "$mode · LTO=$LTO_MODE"
}

# ─── Message handlers ─────────────────────────────────────────────────────────
case "$MESSAGE_TYPE" in
  started)
    MSG="🔨 <b>OronyxClang #$RUN_NUMBER</b>
$DIVIDER
<b>LLVM</b> <code>$(llvm_version)</code>
<b>Commit</b> <code>${ORONYX_COMMIT:0:7}</code>
<b>Mode</b> <code>$(build_mode)</code>
<b>Targets</b> <code>$TARGETS</code>
<b>Date</b> $BUILD_DATE · <b>Patches</b> $PATCH_COUNT
$DIVIDER
⏱ Started $(date -u +%H:%M:%S) UTC
<a href=\"$RUN_URL\">View Run</a>"
    send_msg "$MSG"
    ;;

  success)
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"

    MSG="✅ <b>OronyxClang #$RUN_NUMBER</b>
$DIVIDER
<b>Clang</b> <code>$CLANG_VERSION</code>
<b>Duration</b> <code>$BUILD_DURATION</code>
<b>Targets</b> <code>$TARGETS</code>
$DIVIDER
📦 <code>$TARBALL_NAME</code> ($PACKAGE_SIZE)
<a href=\"$RELEASE_URL\">Download Release</a>"
    send_msg "$MSG"
    ;;

  failure)
    ERROR_FIRST_LINE=""
    if [[ -n "$ERROR_LOG" ]]; then
      ERROR_FIRST_LINE=$(echo "$ERROR_LOG" | grep -i "error\|fatal\|failed" | head -1 | head -c 120)
    elif [[ -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" && -s "$ERROR_DUMP_FILE" ]]; then
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 120)
    fi
    ERROR_FIRST_LINE=$(escape_html "$ERROR_FIRST_LINE")

    MSG="❌ <b>OronyxClang #$RUN_NUMBER</b>
$DIVIDER
<b>LLVM</b> <code>$(llvm_version)</code>
<b>Stage</b> <code>${BUILD_STAGE:-unknown}</code>
<b>Duration</b> <code>${BUILD_DURATION:-unknown}</code>"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$DIVIDER
<pre><code>$ERROR_FIRST_LINE</code></pre>"
    fi

    MSG="$MSG
$DIVIDER
<a href=\"$RUN_URL\">View Logs</a>"
    send_msg "$MSG"
    ;;

  error_dump)
    [[ -z "$ERROR_DUMP_CHAT_ID" ]] && exit 0
    FULL_LOG=""
    ERROR_FIRST_LINE=""
    if [[ -n "$ERROR_LOG" ]]; then
      FULL_LOG="$ERROR_LOG"
      ERROR_FIRST_LINE=$(echo "$ERROR_LOG" | grep -i "error\|fatal\|failed" | head -1 | head -c 150)
    fi
    if [[ -z "$FULL_LOG" && -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" && -s "$ERROR_DUMP_FILE" ]]; then
      # Last 40 lines to fit Telegram's 4096 char limit
      FULL_LOG=$(tail -40 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 150)
    fi

    FULL_LOG=$(escape_html "$FULL_LOG")
    ERROR_FIRST_LINE=$(escape_html "$ERROR_FIRST_LINE")

    MSG="🐛 <b>Build #$RUN_NUMBER — Error Log</b>
$DIVIDER
<b>LLVM</b> <code>$(llvm_version)</code>
<b>Stage</b> <code>${BUILD_STAGE:-unknown}</code>
<b>Duration</b> <code>${BUILD_DURATION:-unknown}</code>"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$DIVIDER
<pre><code>$ERROR_FIRST_LINE</code></pre>"
    fi

    if [[ -n "$FULL_LOG" ]]; then
      MSG="$MSG
$DIVIDER
<pre><code>$FULL_LOG</code></pre>"
    fi

    MSG="$MSG
$DIVIDER
<a href=\"$RUN_URL\">View Run</a>"
    send_msg_to "$ERROR_DUMP_CHAT_ID" "$MSG"
    ;;

  changelog)
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CONTENT=$(cat "$CHANGELOG_FILE")
      # Simple markdown → HTML
      HTML_CONTENT=$(echo "$CONTENT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      HTML_CONTENT=$(echo "$HTML_CONTENT" | sed -E 's/\*([^*]+)\*/<b>\1<\/b>/g')
      HTML_CONTENT=$(echo "$HTML_CONTENT" | sed -E 's/`([^`]+)`/<code>\1<\/code>/g')

      MSG="📋 <b>OronyxClang #$RUN_NUMBER — Changelog</b>
$DIVIDER
$HTML_CONTENT
$DIVIDER
<a href=\"https://github.com/$REPO/releases/tag/$RELEASE_TAG\">View Release</a>"
      send_msg "$MSG"
    fi
    ;;

  release)
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    ORONYX_VER="${RELEASE_TAG#oronyx-}"
    LLVM_COMMIT_HASH="${LLVM_COMMIT:-unknown}"
    LLVM_COMMIT_MSG="${LLVM_COMMIT_MSG:-Automated build}"

    MSG="🚀 <b>OronyxClang $ORONYX_VER</b>
$DIVIDER
<b>Clang</b> <code>$CLANG_VERSION</code>
<b>Commit</b> <a href=\"https://github.com/llvm/llvm-project/commit/$LLVM_COMMIT_HASH\"><code>${LLVM_COMMIT_HASH:0:7}</code></a>
<b>Size</b> <code>$PACKAGE_SIZE</code>
$DIVIDER
<b>Install</b>
<pre><code>bash &lt;(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/get_clang.sh)</code></pre>
$DIVIDER
<b>Features</b>
• PGO · ThinLTO · BOLT
• Polly loop optimizer
• Kernel 4.14+ · AArch64/ARM
$DIVIDER
📦 <code>$TARBALL_NAME</code>
<a href=\"$RELEASE_URL\">GitHub Release</a>"
    send_msg "$MSG"
    ;;

esac
