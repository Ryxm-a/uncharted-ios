#!/usr/bin/env bash
# build_SDL3_ios.sh OUTDIR — static libSDL3 for iOS (arm64), min iOS 16.0.
# Uses the run's upstream checkout's SDL when available, else clones release-3.2.x.
set -euo pipefail
OUT="$1"
UP="${GITHUB_WORKSPACE:-.}"
SRC="$UP/SDL"
[ -d "$SRC" ] || git clone --depth 1 -b release-3.2.x https://github.com/libsdl-org/SDL "$SRC"

cmake -S "$SRC" -B "$OUT/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF \
  -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST_LIBRARY=OFF \
  -DSDL_RENDER=ON -DSDL_CAMERA=OFF -DSDL_JOYSTICK=ON \
  -DSDL_VULKAN=ON -DSDL_METAL=ON
ninja -C "$OUT/build"
mkdir -p "$OUT/lib"
cp -R "$OUT/build/libSDL3.a" "$OUT/lib/" 2>/dev/null || \
  cp "$OUT/build"/*.a "$OUT/lib/" || true
echo "SDL3 (iOS arm64, static) at $OUT/lib"
