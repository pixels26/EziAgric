#!/usr/bin/env bash
# cleanup-test-snapshots.sh — Remove unreferenced snapshot files under
# contracts/amana_escrow/test_snapshots/.
#
# A snapshot file is considered "orphaned" when its basename does not appear
# as a string literal in any Rust source file under contracts/amana_escrow/src/
# or contracts/amana_escrow/tests/.  This script never deletes files that
# ARE referenced.
#
# Usage:
#   bash scripts/cleanup-test-snapshots.sh [--dry-run]
#
# Exit codes:
#   0 — no orphaned snapshots (or all cleaned)
#   1 — at least one orphan removed (or --dry-run found orphans)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONTRACT_DIR="$ROOT_DIR/contracts/amana_escrow"
SNAPSHOT_DIR="$CONTRACT_DIR/test_snapshots"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

echo "═══════════════════════════════════════════════════════════════"
echo "  Amana Escrow — Snapshot Cleanup"
echo "═══════════════════════════════════════════════════════════════"

# ── Check snapshot directory exists ────────────────────────────────────────
if [[ ! -d "$SNAPSHOT_DIR" ]]; then
  echo ""
  echo "  ✓ No test_snapshots/ directory found — nothing to clean."
  echo ""
  exit 0
fi

# ── Collect snapshot basenames ─────────────────────────────────────────────
SNAPSHOT_FILES=()
while IFS= read -r -d '' file; do
  SNAPSHOT_FILES+=("$file")
done < <(find "$SNAPSHOT_DIR" -type f -print0 | sort -z)

if [[ ${#SNAPSHOT_FILES[@]} -eq 0 ]]; then
  echo ""
  echo "  ✓ test_snapshots/ is empty — nothing to clean."
  echo ""
  exit 0
fi

echo ""
echo "  Found ${#SNAPSHOT_FILES[@]} snapshot file(s) in test_snapshots/"
echo ""

# ── Build reference set from Rust sources ──────────────────────────────────
# Concatenate all .rs files in src/ and tests/ (excluding _generated/) and
# extract unique filename-like tokens that could be snapshot references.
REFERENCED_TOKENS=$(mktemp)
trap 'rm -f "$REFERENCED_TOKENS"' EXIT

find "$CONTRACT_DIR/src" "$CONTRACT_DIR/tests" \
  -name '*.rs' \
  -not -path '*/_generated/*' \
  -print0 2>/dev/null \
  | xargs -0 cat 2>/dev/null \
  | grep -oE '[a-zA-Z0-9_./-]+\.(json|wasm|bin|expected)' \
  | sort -u > "$REFERENCED_TOKENS" || true

# Also extract any token that looks like a snapshot path pattern
find "$CONTRACT_DIR/src" "$CONTRACT_DIR/tests" \
  -name '*.rs' \
  -not -path '*/_generated/*' \
  -print0 2>/dev/null \
  | xargs -0 cat 2>/dev/null \
  | grep -oE 'test_snapshots/[^"]+' \
  | sed 's|.*/||' \
  | sort -u >> "$REFERENCED_TOKENS" || true

# Deduplicate
sort -u -o "$REFERENCED_TOKENS" "$REFERENCED_TOKENS"

ORPHAN_COUNT=0
CLEANED_COUNT=0

for snapshot in "${SNAPSHOT_FILES[@]}"; do
  basename=$(basename "$snapshot")

  if grep -qF "$basename" "$REFERENCED_TOKENS"; then
    echo "  ✓ referenced: $basename"
  else
    echo "  ✗ orphan:     $basename"
    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
    if [[ "$DRY_RUN" == "false" ]]; then
      rm -f "$snapshot"
      CLEANED_COUNT=$((CLEANED_COUNT + 1))
    fi
  fi
done

# Remove empty directories left behind
if [[ "$DRY_RUN" == "false" ]]; then
  find "$SNAPSHOT_DIR" -type d -empty -delete 2>/dev/null || true
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ "$ORPHAN_COUNT" -eq 0 ]]; then
  echo "  ✅ All ${#SNAPSHOT_FILES[@]} snapshot(s) are referenced."
  exit 0
else
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  ⚠️  Found $ORPHAN_COUNT orphaned snapshot(s). Run without --dry-run to remove."
  else
    echo "  🧹 Removed $ORPHAN_COUNT orphaned snapshot(s) ($CLEANED_COUNT deleted)."
  fi
  exit 1
fi
