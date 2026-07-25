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

fmt_commit_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "🔧 Commit: <a href=\"https://github.com/llvm/llvm-project/commit/$commit\"><code>${commit:0:7}</code></a>"
  else
    echo "🔧 Commit: <code>pending</code> <i>(will update after clone)</i>"
  fi
}

fmt_llvm_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "⚙️ LLVM Commit: <a href=\"https://github.com/llvm/llvm-project/commit/$commit\"><code>${commit:0:7}</code></a>"
  else
    echo "⚙️ LLVM Commit: <code>pending (will clone)</code>"
  fi
}

fmt_oronyx_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "🔧 Oronyx Clang: <a href=\"https://github.com/$REPO/commit/$commit\"><code>${commit:0:7}</code></a>"
  else
    echo "🔧 Oronyx Clang: <code>unknown</code>"
  fi
}

# ─── Message handlers ─────────────────────────────────────────────────────────
case "$MESSAGE_TYPE" in
  started)
    MSG="$(fmt_header "Oronyx Clang Build #$RUN_NUMBER Started")"
    MSG="$MSG
🛠 <b>Build #$RUN_NUMBER triggered</b>"
    MSG="$MSG
$(fmt_oronyx_link "$ORONYX_COMMIT")"
    MSG="$MSG
📌 Branch: <code>$LLVM_BRANCH</code>"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $ENABLE_PGO | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
🔥 Targets: $TARGETS"
    MSG="$MSG
📆 Date: $BUILD_DATE"
    MSG="$MSG
📝 Patches: $PATCH_COUNT pending"
    MSG="$MSG
$(fmt_section)
🚀 <b>Building custom LLVM/Clang for Android kernel development</b>"
    MSG="$MSG
👋 Queued at $(date -u +%H:%M:%S) UTC"
    MSG="$MSG
🔗 <a href=\"$RUN_URL\">View Run #$RUN_NUMBER</a>"
    send_msg "$MSG"
    ;;

  success)
    CHANGELOG_TEXT=""
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      raw_changelog=$(cat "$CHANGELOG_FILE" 2>/dev/null || true)
      CHANGELOG_TEXT=$(convert_markdown_to_html "$raw_changelog" | head -c 1500 || true)
    fi

    PGO_STR="✅ Enabled"
    [[ "$ENABLE_PGO" == "false" ]] && PGO_STR="❌ Disabled"

    ORONYX_VER="${RELEASE_TAG#oronyx-}"
    [[ -z "$ORONYX_VER" ]] && ORONYX_VER="$CLANG_VERSION"
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"

    MSG="$(fmt_header "Oronyx Clang Build #$RUN_NUMBER SUCCEEDED")"
    MSG="$MSG
📅 $(date -u +%d/%m/%y) | ⏱ <code>$BUILD_DURATION</code>"
    MSG="$MSG
🔧 <b>$CLANG_VERSION</b> | 🎯 <code>$TARGETS</code>"
    MSG="$MSG
👤 By:@$(echo "$REPO" | cut -d/ -f2)"
    MSG="$MSG
$(fmt_section)
📋 <b>Changes:</b>"
    MSG="$MSG
• LLVM <code>$LLVM_BRANCH</code>"
    MSG="$MSG
• PGO: $PGO_STR"
    MSG="$MSG
• ThinLTO: $LTO_MODE"
    MSG="$MSG
• Patches: <code>$PATCH_COUNT</code> applied"
    if [[ -n "$TARBALL_NAME" ]]; then
      MSG="$MSG
$(fmt_section)
📦 <b>Package:</b>"
      MSG="$MSG
📦 File: <code>$TARBALL_NAME</code>"
      MSG="$MSG
📦 Size: <code>$PACKAGE_SIZE</code>"
      MSG="$MSG
🏷 Tag: <code>${RELEASE_TAG:-none}</code>"
    fi

    if [[ -n "$RELEASE_TAG" ]]; then
      MSG="$MSG
$(fmt_section)
📥 <b>Download</b> (<a href=\"$RELEASE_URL\">GitHub Release</a>)"
    fi

    MSG="$MSG
$(fmt_section)
🔗 <a href=\"$RUN_URL\">View Run #$RUN_NUMBER</a>"
    send_msg "$MSG"

    if [[ -n "$CHANGELOG_TEXT" ]]; then
      CHANGELOG_MSG="$(fmt_header "Build #$RUN_NUMBER Changelog")"
      CHANGELOG_MSG="$CHANGELOG_MSG
$CHANGELOG_TEXT"
      CHANGELOG_MSG="$CHANGELOG_MSG
$(fmt_section)
🔗 <a href=\"$RELEASE_URL\">View Release</a>"
      send_msg "$CHANGELOG_MSG"
    fi
    ;;

  failure)
    ERROR_SNIPPET=""
    ERROR_FIRST_LINE=""
    if [[ -n "$ERROR_LOG" ]]; then
      ERROR_SNIPPET=$(echo "$ERROR_LOG" | tail -c 1000)
      ERROR_FIRST_LINE=$(echo "$ERROR_LOG" | grep -i "error\|fatal\|failed" | head -1 | head -c 120)
    elif [[ -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" && -s "$ERROR_DUMP_FILE" ]]; then
      ERROR_SNIPPET=$(tail -c 1000 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 120)
    fi

    ERROR_SNIPPET=$(escape_html "$ERROR_SNIPPET")
    ERROR_FIRST_LINE=$(escape_html "$ERROR_FIRST_LINE")

    MSG="$(fmt_header "Oronyx Clang Build #$RUN_NUMBER FAILED")"
    MSG="$MSG
$(fmt_oronyx_link "$ORONYX_COMMIT")"
    MSG="$MSG
📌 Branch: <code>$LLVM_BRANCH</code>"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $ENABLE_PGO | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
📆 Date: $BUILD_DATE"
    MSG="$MSG
📝 Stage: <code>${BUILD_STAGE:-unknown}</code>"
    MSG="$MSG
⏱ Duration: <code>${BUILD_DURATION:-unknown}</code>"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$(fmt_section)
🐛 <b>Error:</b>
<pre><code>$ERROR_FIRST_LINE</code></pre>"
    fi

    MSG="$MSG
$(fmt_section)
⚡ <b>Quick Fix Suggestions:</b>"
    MSG="$MSG
• Check if LLVM branch <code>$LLVM_BRANCH</code> exists"
    MSG="$MSG
• Verify patch compatibility with upstream"
    MSG="$MSG
• Review build log for missing dependencies"
    MSG="$MSG
• Check disk space and memory"

    if [[ -n "$ERROR_SNIPPET" ]]; then
      MSG="$MSG
$(fmt_section)
🔍 <b>Build Log (last 1000 chars):</b>
<pre><code>$ERROR_SNIPPET</code></pre>"
    else
      MSG="$MSG
$(fmt_section)
ℹ️ <i>No error log available — build may have failed before logging started</i>"
    fi

    MSG="$MSG
$(fmt_section)
🔗 <a href=\"$RUN_URL\">View Full Run #$RUN_NUMBER</a>"
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

    MSG="$(fmt_header "Oronyx Clang Build #$RUN_NUMBER — Error Dump")"
    MSG="$MSG
🐛 <b>Full error log from failed build</b>"
    MSG="$MSG
$(fmt_section)
$(fmt_oronyx_link "$ORONYX_COMMIT")"
    MSG="$MSG
📌 Branch: <code>$LLVM_BRANCH</code>"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $ENABLE_PGO | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
🎯 Targets: $TARGETS"
    MSG="$MSG
📝 Stage: <code>${BUILD_STAGE:-unknown}</code>"
    MSG="$MSG
⏱ Duration: <code>${BUILD_DURATION:-unknown}</code>"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$(fmt_section)
⚡ <b>First Error:</b>
<pre><code>$ERROR_FIRST_LINE</code></pre>"
    fi

    if [[ -n "$FULL_LOG" ]]; then
      MSG="$MSG
$(fmt_section)
🔍 <b>Build Log (last 3000 chars):</b>
<pre><code>$FULL_LOG</code></pre>"
    else
      MSG="$MSG
$(fmt_section)
ℹ️ <i>No error log available — build may have failed before logging started</i>"
    fi

    MSG="$MSG
$(fmt_section)
🔗 <a href=\"$RUN_URL\">View Run #$RUN_NUMBER</a>"
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
    PGO_STR="✅ Enabled"
    [[ "$ENABLE_PGO" == "false" ]] && PGO_STR="❌ Disabled"
    BOLT_STR="✅"
    [[ "$ENABLE_BOLT" != "true" ]] && BOLT_STR="❌"

    MSG="$(fmt_header "Oronyx Clang $ORONYX_VER Released")"
    MSG="$MSG
📅 Update:$(date -u +%d/%m/%y)"
    MSG="$MSG
🔧 Version: <code>$ORONYX_VER</code>"
    MSG="$MSG
🎯 Target: <code>$TARGETS</code>"
    MSG="$MSG
👤 By:@$(echo "$REPO" | cut -d/ -f2)"
    MSG="$MSG
$(fmt_section)
📋 <b>Changelog:</b>"
    MSG="$MSG
• LLVM <code>$LLVM_BRANCH</code>"
    MSG="$MSG
• PGO: $PGO_STR"
    MSG="$MSG
• ThinLTO: $LTO_MODE"
    MSG="$MSG
• BOLT: $BOLT_STR"
    MSG="$MSG
• Polly Loop Optimizer"
    MSG="$MSG
• Kernel 4.14+ to 6.x+ Support"
    MSG="$MSG
• ThinLTO for Kernel 5.12+"
    MSG="$MSG
• Bundled libc++/libc++abi"
    MSG="$MSG
• and others"
    MSG="$MSG
$(fmt_section)
📦 <b>Download</b> (<a href=\"$RELEASE_URL\">GitHub Release</a>)"
    MSG="$MSG
📦 File: <code>$TARBALL_NAME</code>"
    MSG="$MSG
📦 Size: <code>$PACKAGE_SIZE</code>"
    MSG="$MSG
$(fmt_section)
🙏 <b>Credits:</b>"
    MSG="$MSG
@llvm-project — LLVM/Clang source"
    MSG="$MSG
@AOSP — Android kernel compatibility"
    MSG="$MSG
$(fmt_section)
📢 <b>Follow my Channel</b> (<a href=\"https://t.me/naidrahiqa\">@naidrahiqa</a>)"
    MSG="$MSG
💬 <b>Join support group</b> (<a href=\"https://t.me/bwabwabwa_discus\">@bwabwabwa_discus</a>)"
    MSG="$MSG
$(fmt_section)
#OronyxClang #LLVM #Clang #Toolchain #AndroidKernel #AArch64 #ARM #ThinLTO #PGO #BOLT"
    send_msg "$MSG"
    ;;

  release_old)
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    MSG="$(fmt_header "Oronyx Clang $RELEASE_TAG Released")"
    MSG="$MSG
✅ <b>Release published successfully!</b>"
    MSG="$MSG
$(fmt_section)
📦 <b>Release Info:</b>"
    MSG="$MSG
📦 Tag: $RELEASE_TAG"
    MSG="$MSG
📦 File: ${TARBALL_NAME:-unknown}"
    MSG="$MSG
📦 Size: ${PACKAGE_SIZE:-unknown}"
    MSG="$MSG
$(fmt_section)
🚀 <b>Quick Download:</b>
<pre><code>wget $RELEASE_URL/download/$RELEASE_TAG/${TARBALL_NAME:-oronyx-clang.tar.zst}</code></pre>"
    MSG="$MSG
🔗 <a href=\"$RELEASE_URL\">View Release</a>"
    send_msg "$MSG"
    ;;
esac
