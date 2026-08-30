#!/usr/bin/env bash
# verify-test-determinism.sh — Run the contract test suite N times and verify
# zero inter-run variance (issue #246 acceptance criterion: 50x repeat with
# zero variance).
#
# Usage:
#   bash scripts/verify-test-determinism.sh [REPEAT_COUNT]
#
# Arguments:
#   REPEAT_COUNT  Number of times to run the suite (default: 50)
#
# Exit codes:
#   0 — all runs passed with identical results
#   1 — at least one run failed or produced different output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONTRACT_DIR="$ROOT_DIR/contracts/amana_escrow"
REPEAT_COUNT="${1:-50}"
LOG_DIR=$(mktemp -d)
trap 'rm -rf "$LOG_DIR"' EXIT

echo "═══════════════════════════════════════════════════════════════"
echo "  Amana Escrow — Determinism Verification"
echo "  Running cargo test $REPEAT_COUNT times from $CONTRACT_DIR"
echo "═══════════════════════════════════════════════════════════════"
echo ""

PASS=0
FAIL=0
FIRST_LOG="$LOG_DIR/run_001.log"

for i in $(seq 1 "$REPEAT_COUNT"); do
  PADDED=$(printf "%03d" "$i")
  RUN_LOG="$LOG_DIR/run_$PADDED.log"

  echo -n "  [$PADDED/$REPEAT_COUNT] cargo test ..."

  if (cd "$CONTRACT_DIR" && cargo test --locked 2>&1) > "$RUN_LOG" 2>&1; then
    echo " ✅"
    PASS=$((PASS + 1))
  else
    echo " ❌ (see $RUN_LOG)"
    FAIL=$((FAIL + 1))
    continue
  fi

  # After the first successful run, compare subsequent outputs
  if [[ "$i" -gt 1 ]]; then
    PREV_PADDED=$(printf "%03d" $((i - 1)))
    PREV_LOG="$LOG_DIR/run_$PREV_PADDED.log"
    # Compare the "test result:" summary lines to detect inter-run variance
    CURRENT_SUMMARY=$(grep '^test result:' "$RUN_LOG" | sort)
    PREVIOUS_SUMMARY=$(grep '^test result:' "$PREV_LOG" | sort)
    if [[ "$CURRENT_SUMMARY" != "$PREVIOUS_SUMMARY" ]]; then
      echo ""
      echo "  ⚠️  Inter-run variance detected between run $((i-1)) and run $i"
      echo "    Previous: $PREVIOUS_SUMMARY"
      echo "    Current:  $CURRENT_SUMMARY"
      echo ""
      echo "  This indicates non-deterministic test behavior."
      echo "  See contracts/amana_escrow/docs/test-determinism.md for fix guidance."
      FAIL=$((FAIL + 1))
    fi
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed (out of $REPEAT_COUNT runs)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "❌ Determinism verification FAILED."
  echo ""
  echo "  Possible causes:"
  echo "    - Non-deterministic collection ordering in assertions"
  echo "    - Wall-clock time dependency in tests"
  echo "    - Parallel test interference (shared mutable state)"
  echo "    - Flaky network or environment dependency"
  echo ""
  echo "  See: contracts/amana_escrow/docs/test-determinism.md"
  exit 1
else
  echo "✅ All $REPEAT_COUNT runs passed with zero inter-run variance."
  exit 0
fi
