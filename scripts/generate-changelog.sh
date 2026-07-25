#!/usr/bin/env bash
# Oronyx Clang — Auto-generate CHANGELOG from commits
# Usage: bash scripts/generate-changelog.sh [from_tag] [to_tag]
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-naidrahiqa/Oronyx_Clang}"
FROM_TAG="${1:-}"
TO_TAG="${2:-HEAD}"

# Get the last release tag if not specified
if [[ -z "$FROM_TAG" ]]; then
  FROM_TAG=$(gh api repos/$REPO/releases/latest -q '.tag_name' 2>/dev/null || echo "")
  if [[ -z "$FROM_TAG" ]]; then
    # Try to get the first commit
    FROM_TAG=$(git rev-list --max-parents=0 HEAD | head -1)
  fi
fi

echo "# Changelog"
echo ""
echo "## [$TO_TAG] - $(date -u +%Y-%m-%d)"
echo ""

# Get commits between tags
COMMITS=$(git log --pretty=format:"%h|%s|%an|%ad" --date=short "$FROM_TAG..$TO_TAG" 2>/dev/null || \
          git log --pretty=format:"%h|%s|%an|%ad" --date=short "$FROM_TAG..HEAD" 2>/dev/null || echo "")

if [[ -z "$COMMITS" ]]; then
  echo "No changes."
  exit 0
fi

# Categorize commits
FEAT=""
FIX=""
DOCS=""
CI=""
CHORE=""
PERF=""
OTHER=""

while IFS='|' read -r hash subject author date; do
  [[ -z "$hash" ]] && continue
  
  entry="- $subject ($hash by $author on $date)"
  
  case "$subject" in
    feat:*)    FEAT="$FEAT\n$entry" ;;
    fix:*)     FIX="$FIX\n$entry" ;;
    docs:*)    DOCS="$DOCS\n$entry" ;;
    ci:*)      CI="$CI\n$entry" ;;
    chore:*)   CHORE="$CHORE\n$entry" ;;
    perf:*)    PERF="$PERF\n$entry" ;;
    *)         OTHER="$OTHER\n$entry" ;;
  esac
done <<< "$COMMITS"

# Print sections
print_section() {
  local title="$1"
  local content="$2"
  if [[ -n "$content" ]]; then
    echo "### $title"
    echo -e "$content" | grep -v '^$'
    echo ""
  fi
}

print_section "🚀 Features" "$FEAT"
print_section "🐛 Bug Fixes" "$FIX"
print_section "⚡ Performance" "$PERF"
print_section "📝 Documentation" "$DOCS"
print_section "🔧 CI/CD" "$CI"
print_section "🧹 Maintenance" "$CHORE"
print_section "📦 Other" "$OTHER"

echo "---"
echo "**Full Changelog**: https://github.com/$REPO/compare/$FROM_TAG...$TO_TAG"
