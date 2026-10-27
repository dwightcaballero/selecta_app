#!/usr/bin/env bash
# Cost Regression Check Script
# Scans Dart files in lib/ for dangerous patterns that cause runaway Firestore reads or writes.

set -euo pipefail

echo "=================================================="
echo " Running Firebase Cost Regression Guard Checks"
echo "=================================================="

EXIT_CODE=0
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$PROJECT_DIR/lib"

# 1. Check for unbounded collection snapshots on high-growth collections
echo "Checking for unbounded collection streams..."

UNBOUNDED_PATTERNS=(
  "collection(SCOUT_ROUTES_COLLECTION).snapshots()"
  "collection('scout_routes').snapshots()"
  "collection(PROOF_OF_VISIT_COLLECTION).snapshots()"
  "collection('proof_of_visit').snapshots()"
  "collection(BADORDER_BATCH_COLLECTION_REF).snapshots()"
  "collection('badorder_batch').snapshots()"
  "collection(ERROR_LOG_COLLECTION_REF).snapshots()"
  "collection('error_logs').snapshots()"
)

for pattern in "${UNBOUNDED_PATTERNS[@]}"; do
  if grep -rnF "$pattern" "$LIB_DIR" > /dev/null 2>&1; then
    echo "❌ [VIOLATION] Unbounded snapshot query found for: $pattern"
    grep -rnF "$pattern" "$LIB_DIR"
    EXIT_CODE=1
  fi
done

# 2. Check for unbounded clear/delete all without limit
echo "Checking for unbounded get() calls in batch delete methods..."
if grep -rn "collection(collectionRef).get()" "$LIB_DIR/services/error_log_service.dart" > /dev/null 2>&1; then
  echo "❌ [VIOLATION] Unbounded get() found in error_log_service.dart clear method!"
  EXIT_CODE=1
fi

# 3. Check for raw full points array overwrites in ScoutTrackingService
echo "Checking for scout tracking point array overwrite..."
if grep -rn "'points': _sessionPoints.map" "$LIB_DIR/services/scout_tracking_service.dart" > /dev/null 2>&1; then
  echo "❌ [VIOLATION] Full points array overwrite found in ScoutTrackingService! Use FieldValue.arrayUnion instead."
  EXIT_CODE=1
fi

# 4. Check for un-throttled update checks
echo "Checking for app update check caching..."
if ! grep -rn "Duration(hours: 6)" "$LIB_DIR/services/app_update_service.dart" > /dev/null 2>&1; then
  echo "❌ [VIOLATION] App update cache duration should be throttled to 6 hours!"
  EXIT_CODE=1
fi

if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ All Cost Optimization checks passed! Quotas protected."
else
  echo "❌ Cost optimization violations detected. Please review."
fi

exit $EXIT_CODE
