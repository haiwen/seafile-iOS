#!/bin/sh
# Logic tests for resumable uploads (plan §13.2): decision policy, record store,
# segment request builder. Pure Foundation + SQLite, so they build and run on
# the Mac in a few seconds without a simulator or a server.
#
#   seafileTests/ResumableUploadLogicTests/run_tests.sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/Pod/Classes/ResumableUpload"
OUT="${TMPDIR:-/tmp}/seafile-resumable-logic-tests"
mkdir -p "$OUT"
xcrun clang -fobjc-arc -fmodules -Wall -Werror -Wno-deprecated-declarations \
  -I "$SRC" \
  "$SRC/SeafResumableUploadDefines.m" \
  "$SRC/SeafResumableUploadRecord.m" \
  "$SRC/SeafResumableUploadPolicy.m" \
  "$SRC/SeafResumableUploadStore.m" \
  "$SRC/SeafChunkRequestBuilder.m" \
  "$HERE/main.m" \
  -framework Foundation -framework Security -lsqlite3 \
  -o "$OUT/run"
"$OUT/run" "$OUT/data"
