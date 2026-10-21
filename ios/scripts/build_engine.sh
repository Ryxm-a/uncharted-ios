#!/usr/bin/env bash
# build_engine.sh MODE [DEPS SDL FFMPEG ATRAC9] — builds libbbios.a (iOS arm64) via CMake
# and stages every archive the SwiftUI app links into $UP/artifacts/engine.
#
#   lite — shim layer only (compat/start/appbridge/FEX-stub). No dep args needed.
#          This is the CI default so the IPA is green before Phase 1 lands.
#   full — + upstream runtime + vendored shadPS4 GPU subset; also builds fmt/glslang
#          from the fetched sources and requires third_party/fex for BB_WITH_FEX.
#
# Env: GITHUB_WORKSPACE (repo root), MOLTENVK_DIR (optional).
set -euo pipefail

MODE="${1:-lite}"
DEPS="${2:-}"; SDL="${3:-}"; FFMPEG="${4:-}"; ATRAC9="${5:-}"
UP="${GITHUB_WORKSPACE:-.}"
CORE="$UP/ios/core"
BUILD="$UP/build-engine"
DEP_BUILD="$BUILD/libbbios-deps"
OUT="$UP/artifacts/engine"
mkdir -p "$BUILD" "$OUT"

COMMON_FLAGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -G Ninja
)

if [ "$MODE" != "full" ]; then
  echo "== engine: LITE build (shim layer only) =="
  cmake -S "$CORE" -B "$BUILD" "${COMMON_FLAGS[@]}" \
    -DUPSTREAM_ROOT="$UP/upstream" \
    -DDEPS_DIR="${DEPS:-$UP/deps}"
  ninja -C "$BUILD" bbios
else
  echo "== engine: FULL build (upstream + vendored GPU subset) =="
  : "${DEPS:?full mode requires DEPS}" "${SDL:?full mode requires SDL}" \
    "${FFMPEG:?full mode requires FFMPEG}" "${ATRAC9:?full mode requires ATRAC9}"

  # -- stage dep headers where CMakeLists expects them -------------------------------
  mkdir -p "$DEP_BUILD/include"
  cp -R "$SDL"/include/.                       "$DEP_BUILD/include/" 2>/dev/null || true
  cp -R "$SDL"/build/include/.                 "$DEP_BUILD/include/" 2>/dev/null || true
  cp -R "$FFMPEG"/include/.                    "$DEP_BUILD/include/" 2>/dev/null || true
  cp -R "$ATRAC9"/include/.                    "$DEP_BUILD/include/" 2>/dev/null || true

  # -- stage dep static archives ----------------------------------------------------
  mkdir -p "$DEP_BUILD"
  cp "$SDL"/lib/*.a      "$DEP_BUILD/" 2>/dev/null || true
  cp "$ATRAC9"/lib/*.a   "$DEP_BUILD/" 2>/dev/null || true
  cp "$FFMPEG"/lib/*.a   "$DEP_BUILD/" 2>/dev/null || true

  # -- build fmt (full mode) --------------------------------------------------------
  if [ -d "$DEPS/fmt" ]; then
    cmake -S "$DEPS/fmt" -B "$DEPS/fmt/build-ios" "${COMMON_FLAGS[@]}" \
      -DFMT_TEST=OFF -DFMT_DOC=OFF -DBUILD_SHARED_LIBS=OFF \
      -DFMT_SYSTEM_HEADERS=ON -DFMT_INSTALL=OFF -DFMT_OS=OFF
    ninja -C "$DEPS/fmt/build-ios" fmt
    cp "$DEPS"/fmt/build-ios/libfmt.a "$DEP_BUILD/" 2>/dev/null || true
  fi

  # -- build sirit + glslang (full mode) --------------------------------------------
  if [ -d "$DEPS/glslang" ]; then
    if [ -d "$DEPS/sirit" ]; then
      cmake -S "$DEPS/sirit" -B "$DEPS/sirit/build-ios" "${COMMON_FLAGS[@]}" \
        -DSPIRV_HEADERS_INCLUDE_DIR="$DEPS/SPIRVHeaders/include" \
        -DSIRIT_TESTS=OFF -DBUILD_SHARED_LIBS=OFF
      ninja -C "$DEPS/sirit/build-ios"
      cp "$DEPS"/sirit/build-ios/*.a "$DEP_BUILD/" 2>/dev/null || true
    fi
    cmake -S "$DEPS/glslang" -B "$DEPS/glslang/build-ios" "${COMMON_FLAGS[@]}" \
      -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_OPT=OFF -DENABLE_PCH=OFF \
      -DBUILD_SHARED_LIBS=OFF -DENABLE_SPVREMAPPER=OFF \
      -DCMAKE_CXX_FLAGS="-I$DEPS/SPIRVHeaders/include"
    ninja -C "$DEPS/glslang/build-ios" glslang SPIRV
    cp "$DEPS"/glslang/build-ios/glslang/libglslang.a \
       "$DEPS"/glslang/build-ios/SPIRV/libSPIRV.a \
       "$DEP_BUILD/" 2>/dev/null || \
       cp "$DEPS"/glslang/build-ios/Output/lib/*.a "$DEP_BUILD/" 2>/dev/null || true
  fi

  FEX_ARGS=(-DBB_WITH_FEX=OFF)
  if [ -d "$UP/third_party/fex" ]; then
    FEX_ARGS=(-DBB_WITH_FEX=ON -DBB_FEX_DIR="$UP/third_party/fex")
  else
    echo "note: third_party/fex missing — building WITHOUT FEXCore (CPU engine stubs)"
  fi

  cmake -S "$CORE" -B "$BUILD" "${COMMON_FLAGS[@]}" \
    -DBB_FULL_ENGINE=ON "${FEX_ARGS[@]}" \
    -DUPSTREAM_ROOT="$UP/upstream" \
    -DDEPS_DIR="$DEPS"
  ninja -C "$BUILD" bbios
fi

# -- stage for the Xcode app link: engine archive + every dep archive -----------------
cp "$BUILD/libbbios.a" "$OUT/" 2>/dev/null || cp "$BUILD"/*.a "$OUT/" || true
if [ "$MODE" = "full" ]; then
  cp "$DEP_BUILD"/*.a "$OUT/" 2>/dev/null || true
fi
ICD="$UP/${MOLTENVK_DIR:-moltenvk}/MoltenVK_icd.json"
echo "engine[$MODE] staged into $OUT (MoltenVK ICD: $ICD)"
ls -la "$OUT" || true
