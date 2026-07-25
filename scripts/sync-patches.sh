#!/usr/bin/env bash
# Oronyx Clang — Auto Sync Patches from LLVM Stable
# Automatically finds relevant commits between current LLVM version
# and latest stable release, then generates .patch files.
set -euo pipefail

LLVM_DIR="${LLVM_DIR:-$(pwd)/llvm-project}"
PATCHES_DIR="$(cd "$(dirname "$0")/../patches" && pwd)"
LLVM_REMOTE="https://github.com/llvm/llvm-project.git"
BUILD_SCRIPT="$(cd "$(dirname "$0")" && pwd)/build.sh"

log() { echo -e "\033[1;32m[Sync-Patches]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

mkdir -p "$PATCHES_DIR"

# ─── Get current LLVM version from build.sh ────────────────────────────────
get_current_version() {
  local branch
  branch=$(grep -oP 'LLVM_BRANCH:-\K[^}]+' "$BUILD_SCRIPT" 2>/dev/null || echo "main")
  echo "$branch"
}

# ─── Get latest LLVM stable release tag ────────────────────────────────────
get_latest_release() {
  # Fetch latest release tag from GitHub API
  local latest
  latest=$(curl -s "https://api.github.com/repos/llvm/llvm-project/releases/latest" 2>/dev/null | \
    grep -oP '"tag_name":\s*"\K[^"]+' || echo "")
  
  if [[ -z "$latest" ]]; then
    # Fallback: try to get the latest release tag from git
    latest=$(git ls-remote --tags "$LLVM_REMOTE" 2>/dev/null | \
      grep -oP 'refs/tags/\Kllvmorg-\d+\.\d+\.\d+$' | \
      sort -V | tail -1 || echo "")
  fi
  
  echo "$latest"
}

# ─── Get commits between two tags ──────────────────────────────────────────
get_commits_between() {
  local from="$1"
  local to="$2"
  
  # Fetch both tags
  git -C "$LLVM_DIR" fetch origin "refs/tags/$from:refs/tags/$from" 2>/dev/null || true
  git -C "$LLVM_DIR" fetch origin "refs/tags/$to:refs/tags/$to" 2>/dev/null || true
  
  # Get commits between them
  git -C "$LLVM_DIR" log --oneline "refs/tags/$from..refs/tags/$to" 2>/dev/null | \
    grep -iE '(fix|bug|patch|revert|crash|security|regression|backport)' | \
    head -20 || echo ""
}

# ─── Get next patch number ────────────────────────────────────────────────
next_number() {
  local max=0
  for f in "$PATCHES_DIR"/*.patch; do
    [[ -f "$f" ]] || continue
    local n
    n=$(basename "$f" | grep -oP '^\K\d+')
    n="${n:-0}"
    [[ "$n" -gt "$max" ]] && max="$n"
  done
  echo $((max + 1))
}

# ─── Main ──────────────────────────────────────────────────────────────────
main() {
  log "Checking LLVM versions..."
  
  local current_version
  current_version=$(get_current_version)
  log "Current version: $current_version"
  
  local latest_release
  latest_release=$(get_latest_release)
  
  if [[ -z "$latest_release" ]]; then
    die "Could not fetch latest LLVM release"
  fi
  
  log "Latest release: $latest_release"
  
  # Check if we're already on the latest
  if [[ "$current_version" == "$latest_release" ]]; then
    log "Already on latest release ($latest_release), checking for backported commits..."
  fi
  
  # Ensure LLVM source is available
  if [[ ! -d "$LLVM_DIR/.git" ]]; then
    log "Cloning LLVM for commit lookup..."
    git clone --filter=blob:none --no-checkout "$LLVM_REMOTE" "$LLVM_DIR"
    # Fetch only the two tags we need (current + latest), not all tags
    if [[ "$current_version" != "main" ]]; then
      git -C "$LLVM_DIR" fetch --depth=1 origin "refs/tags/$current_version:refs/tags/$current_version" 2>/dev/null || true
    fi
    if [[ -n "$latest_release" && "$latest_release" != "$current_version" ]]; then
      git -C "$LLVM_DIR" fetch --depth=1 origin "refs/tags/$latest_release:refs/tags/$latest_release" 2>/dev/null || true
    fi
    git -C "$LLVM_DIR" checkout HEAD 2>/dev/null || true
  fi
  
  # Try to find commits between versions
  local commits
  if [[ "$current_version" != "main" && "$current_version" != "$latest_release" ]]; then
    log "Finding commits between $current_version and $latest_release..."
    commits=$(get_commits_between "$current_version" "$latest_release")
  else
    log "Finding recent bug fix commits from main..."
    commits=$(git -C "$LLVM_DIR" log --oneline -100 HEAD 2>/dev/null | \
      grep -iE '(fix|bug|patch|revert|crash|security|regression)' | \
      head -20 || echo "")
  fi
  
  if [[ -z "$commits" ]]; then
    log "No relevant commits found"
    echo "applied=0" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "skipped=0" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "failed=0" >> "${GITHUB_OUTPUT:-/dev/null}"
    return 0
  fi
  
  log "Found relevant commits:"
  echo "$commits"
  
  # Process each commit
  local SKIPPED=0 APPLIED=0 FAILED=0
  
  while IFS= read -r line; do
    local commit_hash commit_msg
    commit_hash=$(echo "$line" | awk '{print $1}')
    commit_msg=$(echo "$line" | cut -d' ' -f2-)
    
    [[ -z "$commit_hash" ]] && continue
    
    log "Processing: $commit_msg"
    
    # Skip if patch already exists
    if ls "$PATCHES_DIR"/*-"${commit_hash:0:7}"*.patch &>/dev/null 2>&1; then
      log "  → Skipped (already exists)"
      ((SKIPPED++)) || true
      continue
    fi
    
    # Fetch the specific commit
    if ! git -C "$LLVM_DIR" fetch origin "$commit_hash" 2>/dev/null; then
      warn "  → Failed to fetch $commit_hash"
      ((FAILED++)) || true
      continue
    fi
    
    # Generate patch
    local subject
    subject=$(echo "$commit_msg" | sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-60)
    
    local num
    num=$(next_number)
    local patch_file
    patch_file="$PATCHES_DIR/$(printf '%04d' "$num")-${commit_hash:0:7}-${subject:0:50}.patch"
    
    if git -C "$LLVM_DIR" format-patch -1 "$commit_hash" -o "$PATCHES_DIR" 2>/dev/null; then
      local gen_file
      gen_file=$(ls -t "$PATCHES_DIR"/*.patch 2>/dev/null | head -1)
      if [[ -n "$gen_file" && "$gen_file" != "$patch_file" ]]; then
        mv "$gen_file" "$patch_file"
      fi
      log "  → Created: $(basename "$patch_file")"
      ((APPLIED++)) || true
    else
      warn "  → Failed to create patch"
      ((FAILED++)) || true
    fi
  done <<< "$commits"
  
  echo ""
  log "Summary: $APPLIED applied, $SKIPPED skipped, $FAILED failed"
  
  # Output for GitHub Actions
  echo "applied=$APPLIED" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "skipped=$SKIPPED" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "failed=$FAILED" >> "${GITHUB_OUTPUT:-/dev/null}"
}

main "$@"
