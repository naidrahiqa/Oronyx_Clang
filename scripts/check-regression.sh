#!/usr/bin/env bash
# Oronyx Clang — Performance Regression Alert
# Compares current benchmark results against baseline and alerts if regression > threshold
# Usage: bash scripts/check-regression.sh [threshold_percent]
set -euo pipefail

THRESHOLD="${1:-5}"  # Default 5% regression threshold
RESULTS_FILE="benchmark/results.json"
BASELINE_FILE="benchmark/baseline.json"

if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "❌ No benchmark results found at $RESULTS_FILE"
  exit 1
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "⚠️  No baseline found. Saving current results as baseline."
  cp "$RESULTS_FILE" "$BASELINE_FILE"
  exit 0
fi

# Parse results
CURRENT_COMPILE=$(jq -r '.compile_time_ms // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
BASELINE_COMPILE=$(jq -r '.compile_time_ms // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")

CURRENT_SIZE=$(jq -r '.binary_size_bytes // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
BASELINE_SIZE=$(jq -r '.binary_size_bytes // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")

CURRENT_MEM=$(jq -r '.peak_memory_bytes // 0' "$RESULTS_FILE" 2>/dev/null || echo "0")
BASELINE_MEM=$(jq -r '.peak_memory_bytes // 0' "$BASELINE_FILE" 2>/dev/null || echo "0")

# Calculate regression percentage using awk (no bc dependency)
calc_regression() {
  local current="$1"
  local baseline="$2"
  
  if [[ "$baseline" == "0" || "$baseline" == "" || "$baseline" == "null" ]]; then
    echo "0"
    return
  fi
  
  awk "BEGIN {printf \"%.2f\", (($current - $baseline) / $baseline) * 100}"
}

COMPILE_REG=$(calc_regression "$CURRENT_COMPILE" "$BASELINE_COMPILE")
SIZE_REG=$(calc_regression "$CURRENT_SIZE" "$BASELINE_SIZE")
MEM_REG=$(calc_regression "$CURRENT_MEM" "$BASELINE_MEM")

echo "📊 Performance Regression Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Threshold: ${THRESHOLD}%"
echo ""
echo "Metric              Current         Baseline        Regression"
echo "─────────────────────────────────────────────────────────────"

has_regression=false

check_metric() {
  local name="$1"
  local current="$2"
  local baseline="$3"
  local regression="$4"
  
  # Check if regression exceeds threshold using awk
  local exceeds
  exceeds=$(awk "BEGIN {print ($regression > $THRESHOLD) ? 1 : 0}")
  local is_better
  is_better=$(awk "BEGIN {print ($regression < -$THRESHOLD) ? 1 : 0}")
  
  if [[ "$exceeds" == "1" ]]; then
    echo "❌ $name              $current         $baseline        +${regression}%"
    has_regression=true
  elif [[ "$is_better" == "1" ]]; then
    echo "✅ $name              $current         $baseline        ${regression}%"
  else
    echo "✅ $name              $current         $baseline        ${regression}%"
  fi
}

check_metric "Compile Time (ms)" "$CURRENT_COMPILE" "$BASELINE_COMPILE" "$COMPILE_REG"
check_metric "Binary Size (bytes)" "$CURRENT_SIZE" "$BASELINE_SIZE" "$SIZE_REG"
check_metric "Peak Memory (bytes)" "$CURRENT_MEM" "$BASELINE_MEM" "$MEM_REG"

echo ""

if [[ "$has_regression" == "true" ]]; then
  echo "🚨 REGRESSION DETECTED!"
  echo "Performance regression exceeds ${THRESHOLD}% threshold."
  echo ""
  echo "Possible causes:"
  echo "  - New LLVM version has performance issues"
  echo "  - Build flags changed"
  echo "  - PGO profile data is stale"
  echo ""
  echo "Recommended actions:"
  echo "  1. Review recent changes to build.sh or config/"
  echo "  2. Compare with previous release benchmark"
  echo "  3. Check LLVM release notes for known regressions"
  exit 1
else
  echo "✅ No significant regression detected."
  exit 0
fi
