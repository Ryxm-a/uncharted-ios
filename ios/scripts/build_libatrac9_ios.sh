#!/usr/bin/env bash
# build_libatrac9_ios.sh OUTDIR — LibAtrac9 (Sony ATRAC9 decoder) static lib for iOS.
set -euo pipefail
OUT="$1"
SRC="$OUT/src"
if [ ! -d "$SRC" ]; then
  git clone --depth 1 https://github.com/Thealexbarney/LibAtrac9.git "$SRC"
fi
mkdir -p "$OUT/lib" "$OUT/include"
cmake -S "$SRC/C" -B "$OUT/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF
ninja -C "$OUT/build"
cp "$OUT"/build/*.a "$OUT/lib/" 2>/dev/null || true
cp -R "$SRC/C/include/." "$OUT/include/" 2>/dev/null || true
echo "LibAtrac9 static lib at $OUT/lib"
