#!/bin/bash
# Builds simulator-only libcrypto.a / libssl.a for OpenSSL 1.0.2r, the version
# shipped by OpenSSL-Universal 1.0.2.17. That pod's fat archives have no
# arm64-simulator slice, which Apple-silicon simulators (iOS 27+) require.
#
# Output (git-ignored): Vendor/OpenSSL-simulator/lib/{libcrypto,libssl}.a
#   arm64  — built here for the iOS simulator
#   x86_64 — copied from the pod's archive (already a simulator slice)
#
# Device builds never use these files: the Podfile only adds this directory to
# LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*].
#
# Run after `pod install`:  Vendor/OpenSSL-simulator/build.sh
set -euo pipefail

VERSION=1.0.2r
SHA256=ae51d08bba8a83958e894946f15303ff894d75c2b8bbd44a852b64e3fe11d0d6
MIN_IOS=16.0

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
POD_LIB="$REPO/Pods/OpenSSL-Universal/lib-ios"
OUT="$HERE/lib"

if [ ! -f "$POD_LIB/libcrypto.a" ]; then
    echo "error: $POD_LIB not found, run 'pod install' first" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -o "$WORK/openssl.tar.gz" "https://www.openssl.org/source/old/1.0.2/openssl-$VERSION.tar.gz"
echo "$SHA256  $WORK/openssl.tar.gz" | shasum -a 256 -c - >/dev/null
tar -xzf "$WORK/openssl.tar.gz" -C "$WORK"
cd "$WORK/openssl-$VERSION"

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
CLANG="$(xcrun --sdk iphonesimulator -f clang)"
export CC="$CLANG -arch arm64 -target arm64-apple-ios$MIN_IOS-simulator -isysroot $SDK"

./Configure iphoneos-cross no-asm no-shared --openssldir="$WORK/ssl" >/dev/null
# iphoneos-cross hardcodes -isysroot $(CROSS_TOP)/SDKs/$(CROSS_SDK); CC already carries the simulator sysroot.
sed -i '' 's|-isysroot \$(CROSS_TOP)/SDKs/\$(CROSS_SDK)||' Makefile
make depend >/dev/null 2>&1
make build_libs >/dev/null

mkdir -p "$OUT"
for lib in libcrypto libssl; do
    lipo -thin x86_64 "$POD_LIB/$lib.a" -output "$WORK/$lib-x86_64.a"
    lipo -create "$lib.a" "$WORK/$lib-x86_64.a" -output "$OUT/$lib.a"
done

lipo -info "$OUT/libcrypto.a" "$OUT/libssl.a"
