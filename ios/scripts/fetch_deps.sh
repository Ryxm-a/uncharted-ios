#!/usr/bin/env bash
# fetch_deps.sh OUT — collects what the engine lib needs (fmt, robin-map, xxhash,
# Vulkan-Headers, VMA, magic_enum, miniz, glslang, SPIRV-Headers, sirit).
# Usage: fetch_deps.sh /path/to/deps
set -euo pipefail
DEPS="$1"
mkdir -p "$DEPS"
cd "$DEPS"

clone () {
  local name="$1" url="$2" sha="${3:-}"
  if [ -d "$name" ]; then echo "have $name"; return 0; fi
  git clone --depth 1 "$url" "$name"
  if [ -n "$sha" ]; then git -C "$name" checkout "$sha" 2>/dev/null || true; fi
}

clone fmt             https://github.com/fmtlib/fmt                                      11.1.4
clone robin-map       https://github.com/Tessil/robin-map                                v1.3.0
clone XXHash          https://github.com/Cyan4973/xxHash                                 v0.8.2
clone VulkanHeaders   https://github.com/KhronosGroup/Vulkan-Headers                     v1.3.296
clone VulkanMemoryAl  https://github.com/GPUOpen-LibrariesAnd-SDKs/VulkanMemoryAllocator d1bb01e
clone magic_enum      https://github.com/Neargye/magic_enum                              v0.9.6
clone miniz           https://github.com/richgel999/miniz                                3.0.2
clone glslang         https://github.com/KhronosGroup/glslang                            14.3.0
clone SPIRVHeaders    https://github.com/KhronosGroup/SPIRV-Headers                      v1.3.290.0
clone sirit           https://github.com/shadps4-emu/sirit

# sirit expects SPIRV-Headers next to it (subprojects layout in meson, CMake path here):
if [ ! -d "$DEPS/sirit-external/SPIRV-Headers" ]; then
  mkdir -p "$DEPS/sirit-external"
  cp -R "$DEPS/SPIRVHeaders" "$DEPS/sirit-external/SPIRV-Headers"
fi

echo "deps ready at $DEPS"
