#!/usr/bin/env bash
# OronyxClang — LLVM Changelog Generator
# Generates changelog between two LLVM versions using git log.
# Usage: bash scripts/llvm-changelog.sh <llvm-dir> <from-tag> [to-tag]
set -euo pipefail

LLVM_DIR="${1:-}"
FROM_TAG="${2:-}"
TO_TAG="${3:-HEAD}"

log()   { echo -e "\033[1;36m[Changelog]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ -d "$LLVM_DIR" ]] || die "LLVM dir not found: $LLVM_DIR"
[[ -d "$LLVM_DIR/.git" ]] || die "Not a git repo: $LLVM_DIR"

# If FROM_TAG not specified, try to find previous version from Oronyx repo
if [[ -z "$FROM_TAG" ]]; then
  ORONYX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  if [[ -f "$ORONYX_ROOT/.llvm-version" ]]; then
    FROM_TAG=$(cat "$ORONYX_ROOT/.llvm-version" | tr -d '[:space:]')
  fi
fi

# Resolve tags to commits for comparison
if [[ -n "$FROM_TAG" ]]; then
  # Try full tag first (llvmorg-22.1.0), then bare version (22.1.0)
  from_commit=$(git -C "$LLVM_DIR" rev-parse "$FROM_TAG" 2>/dev/null || \
                git -C "$LLVM_DIR" rev-parse "llvmorg-$FROM_TAG" 2>/dev/null || echo "")
  if [[ -z "$from_commit" ]]; then
    warn "Could not resolve $FROM_TAG in LLVM repo"
    FROM_TAG=""
  fi
fi

to_commit=$(git -C "$LLVM_DIR" rev-parse "$TO_TAG" 2>/dev/null || \
            git -C "$LLVM_DIR" rev-parse HEAD 2>/dev/null || echo "")

if [[ -z "$to_commit" ]]; then
  die "Could not resolve target commit"
fi

# Get commit range description
from_desc="${FROM_TAG:-initial}"
to_desc=$(git -C "$LLVM_DIR" describe --tags "$to_commit" 2>/dev/null || echo "$TO_TAG")

# Changelog header
echo "## LLVM Changes: $from_desc → $to_desc"
echo ""

if [[ -z "$FROM_TAG" ]]; then
  echo "Initial build — no previous version to compare."
  echo ""
  exit 0
fi

# Count commits in range
commit_count=$(git -C "$LLVM_DIR" rev-list --count "$from_commit..$to_commit" 2>/dev/null || echo 0)
echo "**$commit_count commits** between versions"
echo ""

# Get categorized log
FEAT=""; FIX=""; PERF=""; OTHER=""
while IFS='|' read -r hash subject; do
  [[ -z "$hash" ]] && continue
  short_hash="${hash:0:7}"
  entry="  - $subject ($short_hash)"
  case "$subject" in
    [Cc][Ii]*)         ;; # Skip CI commits
    [Dd]ocs:*)         OTHER="$OTHER\n$entry" ;;
    [Mm]erge*)         ;;
    [Rr]evert*)        FIX="$FIX\n$entry" ;;
    [Ff]ix*)           FIX="$FIX\n$entry" ;;
    [Bb]ug*)           FIX="$FIX\n$entry" ;;
    [Pp]erf*)          PERF="$PERF\n$entry" ;;
    [Ff]eat*)          FEAT="$FEAT\n$entry" ;;
    [Aa]dd*)           FEAT="$FEAT\n$entry" ;;
    [Ss]upport*)       FEAT="$FEAT\n$entry" ;;
    [Ii]mplement*)     FEAT="$FEAT\n$entry" ;;
    *)                 OTHER="$OTHER\n$entry" ;;
  esac
done < <(git -C "$LLVM_DIR" log --pretty=format:"%h|%s" "$from_commit..$to_commit" 2>/dev/null | head -500)

print_section() {
  local emoji="$1" title="$2" content="$3"
  if [[ -n "$content" ]]; then
    echo "### $emoji $title"
    echo -e "$content" | grep -v '^$'
    echo ""
  fi
}

print_section "✨" "Features & Additions" "$FEAT"
print_section "🐛" "Bug Fixes" "$FIX"
print_section "⚡" "Performance" "$PERF"
print_section "📦" "Other Changes" "$OTHER"

echo "---"
echo "**Full comparison**: https://github.com/llvm/llvm-project/compare/$from_desc...$to_desc"