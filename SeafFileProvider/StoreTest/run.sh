#!/bin/sh
# Standalone macOS check of SeafFPStore / SeafFPIdentifier (no Xcode project needed).
# Usage: SeafFileProvider/StoreTest/run.sh   (from the repository root)
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/seaf-fp-store-test"
clang -fobjc-arc -DDEBUG=1 -Wno-objc-protocol-method-implementation \
  -I "$ROOT/SeafFileProvider/StoreTest" -I "$ROOT/SeafFileProvider" -I "$ROOT/Pod/Classes" \
  -framework Foundation -framework FileProvider -lsqlite3 \
  "$ROOT/SeafFileProvider/SeafFPStore.m" "$ROOT/SeafFileProvider/SeafFPIdentifier.m" \
  "$ROOT/SeafFileProvider/StoreTest/SeafFPStoreTest.m" -o "$OUT"
"$OUT" 2>&1 | grep -E "FAIL|RESULT"
