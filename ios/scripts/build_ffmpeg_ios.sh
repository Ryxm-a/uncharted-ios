#!/usr/bin/env bash
# build_ffmpeg_ios.sh OUTDIR — minimal static FFmpeg for iOS arm64 (cutscene video decode only).
set -euo pipefail
OUT="$1"; mkdir -p "$OUT/lib" "$OUT/include"
SRC="$OUT/src"
if [ ! -d "$SRC" ]; then
  git clone --depth 1 --branch n7.1 https://git.ffmpeg.org/ffmpeg.git "$SRC"
fi
SDK=$(xcrun -sdk iphoneos -show-sdk-path)
(cd "$SRC" && \
  CC="xcrun -sdk iphoneos clang" \
  ./configure \
    --enable-cross-compile --target-os=darwin --arch=arm64 \
    --prefix="$OUT" --disable-shared --enable-static \
    --disable-programs --disable-doc --disable-avdevice \
    --disable-postproc --disable-network --disable-iconv \
    --disable-sdl2 --disable-xlib --disable-zlib --disable-bzlib --disable-lzma \
    --disable-outdevs --disable-indevs \
    --enable-avcodec --enable-avformat --enable-swscale \
    --enable-parser=h264,hevc,vp8 --enable-decoder=h264,hevc,vp8 \
    --enable-demuxer=mov,matroska,webm,mpegts \
    --enable-protocol=file \
    --extra-cflags="-arch arm64 -mios-version-min=16.0 -isysroot $SDK -fPIC" \
    --extra-ldflags="-arch arm64 -mios-version-min=16.0") \
  && (make -C "$SRC" -j"$(sysctl -n hw.ncpu)" && make -C "$SRC" install)
echo "ffmpeg static libs at $OUT/lib"
