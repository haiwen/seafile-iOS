#!/bin/sh
# Standalone macOS check of the SDK's retry rules (no Xcode project needed).
# Usage: Pod/Tests/run.sh   (from the repository root)
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/seaf-sdk-retry-test"
LOG="$(mktemp "${TMPDIR:-/tmp}/seaf-sdk-retry-test.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
clang -fobjc-arc -Wall -I "$ROOT/Pod/Classes" -framework Foundation \
  "$ROOT/Pod/Tests/SeafRetryBackoffTest.m" -o "$OUT"
if "$OUT" > "$LOG" 2>&1; then
  grep -E "FAIL|RESULT" "$LOG"
else
  cat "$LOG"
  exit 1
fi
