#!/usr/bin/env bash
# Oronyx Clang — Enhanced Telegram Notification Script
# Sends build status notifications via Telegram Bot API with rich HTML formatting,
# build metadata, and changelog support.
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

convert_markdown_to_html() {
  local input="$1"
  local escaped
  escaped=$(escape_html "$input")
  # Convert bold (*text*) to <b>text</b>
  escaped=$(echo "$escaped" | sed -E 's/\*([^*]+)\*/<b>\1<\/b>/g')
  # Convert inline code (`code`) to <code>code</code>
  escaped=$(echo "$escaped" | sed -E 's/`([^`]+)`/<code>\1<\/code>/g')
  echo "$escaped"
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

# ─── Formatting helpers ───────────────────────────────────────────────────────
LINE="━━━━━━━━━━━━━━━━━━━━"

fmt_section() { echo "$LINE"; }
fmt_header() { echo "🤖 <b>$1</b>
$LINE"; }
fmt_kv() { echo "$1 $2: <code>$3</code>"; }
fmt_kv_raw() { echo "$1 $2: $3"; }

# ─── Message handlers ─────────────────────────────────────────────────────────
case "$MESSAGE_TYPE" in
  started)
    MSG="🔨 <b>Oronyx Clang Build #$RUN_NUMBER</b>
━━━━━━━━━━━━━━━━━━━━
Branch: <code>$LLVM_BRANCH</code>
Commit: <code>${ORONYX_COMMIT:0:7}</code>
PGO: $ENABLE_PGO | LTO: $LTO_MODE
Targets: <code>$TARGETS</code>
Date: $BUILD_DATE
Patches: $PATCH_COUNT
━━━━━━━━━━━━━━━━━━━━
Started at $(date -u +%H:%M:%S) UTC
<a href=\"$RUN_URL\">View Run</a>"
    send_msg "$MSG"
    ;;

  success)
    ORONYX_VER="${RELEASE_TAG#oronyx-}"
    [[ -z "$ORONYX_VER" ]] && ORONYX_VER="$CLANG_VERSION"
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"

    MSG="✅ <b>Oronyx Clang Build #$RUN_NUMBER</b>
━━━━━━━━━━━━━━━━━━━━
Clang: <code>$CLANG_VERSION</code>
Duration: <code>$BUILD_DURATION</code>
Targets: <code>$TARGETS</code>
━━━━━━━━━━━━━━━━━━━━
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

    MSG="❌ <b>Oronyx Clang Build #$RUN_NUMBER</b>
━━━━━━━━━━━━━━━━━━━━
Branch: <code>$LLVM_BRANCH</code>
Stage: <code>${BUILD_STAGE:-unknown}</code>
Duration: <code>${BUILD_DURATION:-unknown}</code>"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
━━━━━━━━━━━━━━━━━━━━
<pre><code>$ERROR_FIRST_LINE</code></pre>"
    fi

    MSG="$MSG
━━━━━━━━━━━━━━━━━━━━
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
      FULL_LOG=$(tail -c 3000 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 150)
    fi

    FULL_LOG=$(escape_html "$FULL_LOG")
    ERROR_FIRST_LINE=$(escape_html "$ERROR_FIRST_LINE")

    MSG="🐛 <b>Build #$RUN_NUMBER Error Dump</b>
━━━━━━━━━━━━━━━━━━━━
Branch: <code>$LLVM_BRANCH</code>
Stage: <code>${BUILD_STAGE:-unknown}</code>
Duration: <code>${BUILD_DURATION:-unknown}</code>"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
━━━━━━━━━━━━━━━━━━━━
<pre><code>$ERROR_FIRST_LINE</code></pre>"
    fi

    if [[ -n "$FULL_LOG" ]]; then
      MSG="$MSG
━━━━━━━━━━━━━━━━━━━━
<pre><code>$FULL_LOG</code></pre>"
    fi

    MSG="$MSG
━━━━━━━━━━━━━━━━━━━━
<a href=\"$RUN_URL\">View Run</a>"
    send_msg_to "$ERROR_DUMP_CHAT_ID" "$MSG"
    ;;

  changelog)
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CONTENT=$(cat "$CHANGELOG_FILE")
      HTML_CONTENT=$(convert_markdown_to_html "$CONTENT")
      MSG="$(fmt_header "Build #$RUN_NUMBER Changelog")"
      MSG="$MSG
$HTML_CONTENT"
      MSG="$MSG
$(fmt_section)
🔗 <a href=\"https://github.com/$REPO/releases/tag/$RELEASE_TAG\">View Release</a>"
      send_msg "$MSG"
    fi
    ;;

  release)
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    ORONYX_VER="${RELEASE_TAG#oronyx-}"
    
    # Get LLVM commit info
    LLVM_COMMIT_HASH="${LLVM_COMMIT:-unknown}"
    LLVM_COMMIT_MSG="${LLVM_COMMIT_MSG:-Automated build}"
    
    MSG="$(fmt_header "Oronyx Clang $ORONYX_VER Released")"
    MSG="$MSG
Clang version: <code>$CLANG_VERSION</code>"
    MSG="$MSG
LLVM repo commit: $LLVM_COMMIT_MSG"
    MSG="$MSG
Link: <a href=\"https://github.com/llvm/llvm-project/commit/$LLVM_COMMIT_HASH\"><code>${LLVM_COMMIT_HASH:0:7}</code></a>"
    MSG="$MSG
$(fmt_section)
<b>Installation</b>"
    MSG="$MSG
<pre><code>bash &lt;(wget -qO- https://raw.githubusercontent.com/naidrahiqa/Oronyx_Clang/main/get_clang.sh)</code></pre>"
    MSG="$MSG
$(fmt_section)
<b>Features</b>"
    MSG="$MSG
• PGO (Profile-Guided Optimization)"
    MSG="$MSG
• ThinLTO / FullLTO"
    MSG="$MSG
• BOLT post-build optimization"
    MSG="$MSG
• Polly loop optimizer"
    MSG="$MSG
• Kernel 4.14+ support"
    MSG="$MSG
• AArch64 / ARM targets"
    MSG="$MSG
$(fmt_section)
📦 <code>$TARBALL_NAME</code> (<code>$PACKAGE_SIZE</code>)"
    MSG="$MSG
$(fmt_section)
<a href=\"$RELEASE_URL\">GitHub Release</a>"
    send_msg "$MSG"
    ;;

esac
