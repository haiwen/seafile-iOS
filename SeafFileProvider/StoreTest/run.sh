#!/bin/sh
# Standalone macOS check of SeafFPStore / SeafFPIdentifier (no Xcode project needed).
# Usage: SeafFileProvider/StoreTest/run.sh   (from the repository root)
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/seaf-fp-store-test"
LOG="$(mktemp "${TMPDIR:-/tmp}/seaf-fp-store-test.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
clang -fobjc-arc -DDEBUG=1 -Wno-objc-protocol-method-implementation \
  -I "$ROOT/SeafFileProvider/StoreTest" -I "$ROOT/SeafFileProvider" -I "$ROOT/Pod/Classes" \
  -framework Foundation -framework FileProvider -lsqlite3 \
  "$ROOT/SeafFileProvider/SeafFPStore.m" "$ROOT/SeafFileProvider/SeafFPIdentifier.m" \
  "$ROOT/SeafFileProvider/StoreTest/SeafFPStoreTest.m" -o "$OUT"
if "$OUT" > "$LOG" 2>&1; then
  grep -E "FAIL|RESULT" "$LOG"
else
  cat "$LOG"
  exit 1
fi
clang -fobjc-arc -I "$ROOT/SeafFileProvider" -framework Foundation \
  "$ROOT/SeafFileProvider/SeafFPCheckSchedule.m" \
  "$ROOT/SeafFileProvider/StoreTest/SeafFPCheckScheduleTest.m" -o "$OUT-schedule"
if "$OUT-schedule" > "$LOG" 2>&1; then
  grep -E "FAIL|RESULT" "$LOG"
else
  cat "$LOG"
  exit 1
fi
clang -fobjc-arc -I "$ROOT/SeafFileProvider" -framework Foundation -framework FileProvider \
  "$ROOT/SeafFileProvider/SeafFPErrorResolution.m" "$ROOT/SeafFileProvider/SeafFPErrors.m" \
  "$ROOT/SeafFileProvider/StoreTest/SeafFPErrorResolutionTest.m" -o "$OUT-resolution"
if "$OUT-resolution" > "$LOG" 2>&1; then
  grep -E "FAIL|RESULT" "$LOG"
else
  cat "$LOG"
  exit 1
fi
python3 "$ROOT/SeafFileProvider/StoreTest/SeafFPIndexingTest.py"
python3 "$ROOT/SeafFileProvider/StoreTest/SeafFPDirectoryTest.py"
