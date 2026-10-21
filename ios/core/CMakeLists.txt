# iOS engine CMakeLists — the single authority for building libbbios.a (iOS arm64).
#
# Two build modes:
#   lite (default CI): only the iOS shim layer (compat/appbridge/start/FEX-stub) —
#                      the SwiftUI app links and runs; Play hits the honest
#                      "engine bring-up pending" path (docs/01 Phase 0→1).
#   full:              + upstream runtime + vendored shadPS4 GPU subset + FEXCore
#                      (requires UPSTREAM_ROOT, DEPS_DIR, staged dep libs, FEX).
#
#   cmake -S ios/core -B build -G Ninja -DCMAKE_SYSTEM_NAME=iOS \
#         -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
#         [-DBB_ENGINE_LITE=ON  (default)]
#         [-DBB_FULL_ENGINE=ON -DUPSTREAM_ROOT=... -DDEPS_DIR=... -DBB_WITH_FEX=ON]
# Output: libbbios.a

cmake_minimum_required(VERSION 3.24)
project(bbios C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(BB_FULL_ENGINE "compile the full upstream engine surface"        OFF)
option(BB_WITH_FEX    "compile against FEXCore headers (full mode only)" OFF)
option(BB_WITH_FSR4   "include FSR4/DLSS GPU paths"                     OFF)  # always OFF on iOS (docs/04)
set(BB_FEX_DIR        "" CACHE PATH "FEX checkout providing FEXCore headers")

if(NOT UPSTREAM_ROOT)
  set(UPSTREAM_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../upstream")
endif()
if(NOT DEPS_DIR)
  set(DEPS_DIR "${CMAKE_CURRENT_LIST_DIR}/../../deps")
endif()

# ------------------------------------------------------- iOS shim layer (both modes)
set(ENGINE_SOURCES "")
list(APPEND ENGINE_SOURCES
  "${CMAKE_CURRENT_LIST_DIR}/compat_ios.c"
  "${CMAKE_CURRENT_LIST_DIR}/start_ios.c"
  "${CMAKE_CURRENT_LIST_DIR}/appbridge.c")

# FexLoader always compiles: its internal #if selects the real FEXCore bridge only
# when BB_WITH_FEX; otherwise it provides honest bring-up stubs.
file(GLOB FEXBRIDGE "${CMAKE_CURRENT_LIST_DIR}/fex/*.cpp")
list(APPEND ENGINE_SOURCES ${FEXBRIDGE})

# ------------------------------------------------------- full mode: upstream tree
if(BB_FULL_ENGINE)
  file(GLOB RUNTIME_SRC "${UPSTREAM_ROOT}/src/runtime_*.c")
  list(APPEND ENGINE_SOURCES ${RUNTIME_SRC}
    "${UPSTREAM_ROOT}/src/runtime.c"
    "${UPSTREAM_ROOT}/src/vulkan_smoke.c")
  list(FILTER ENGINE_SOURCES EXCLUDE REGEX "runtime_thread\\.c$")   # iOS variant below
  list(FILTER ENGINE_SOURCES EXCLUDE REGEX "compat_win\\.c$")       # never on iOS

  if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../overlay/src/runtime_thread_ios.c")
    list(APPEND ENGINE_SOURCES "${CMAKE_CURRENT_LIST_DIR}/../overlay/src/runtime_thread_ios.c")
  else()
    list(APPEND ENGINE_SOURCES "${UPSTREAM_ROOT}/src/runtime_thread.c")
  endif()

  file(GLOB_RECURSE VIDEOCORE "${UPSTREAM_ROOT}/gpu/shadps4/video_core/*.cpp")
  file(GLOB_RECURSE RECOMP    "${UPSTREAM_ROOT}/gpu/shadps4/shader_recompiler/*.cpp")
  file(GLOB_RECURSE SHIM      "${UPSTREAM_ROOT}/gpu/shim/*.cpp")
  list(FILTER VIDEOCORE EXCLUDE REGEX "renderdoc|vk_fsr4|fsr411|vk_dlss|vulkan_full")
  list(FILTER RECOMP    EXCLUDE REGEX "renderdoc")
  list(FILTER SHIM      EXCLUDE REGEX "renderdoc|bbport_dlss")
  list(APPEND ENGINE_SOURCES ${VIDEOCORE} ${RECOMP} ${SHIM})

  file(GLOB VENCOMMON "${UPSTREAM_ROOT}/gpu/shadps4/common/*.cpp")
  file(GLOB VENLOG    "${UPSTREAM_ROOT}/gpu/shadps4/common/logging/*.cpp")
  file(GLOB VENGNM    "${UPSTREAM_ROOT}/gpu/shadps4/core/libraries/gnmdriver/*.cpp")
  file(GLOB VENVO     "${UPSTREAM_ROOT}/gpu/shadps4/core/libraries/videoout/*.cpp")
  file(GLOB VENAVP    "${UPSTREAM_ROOT}/gpu/shadps4/core/libraries/avplayer/*.cpp")
  file(GLOB VENDEC    "${UPSTREAM_ROOT}/gpu/shadps4/core/libraries/videodec/*.cpp")
  list(APPEND ENGINE_SOURCES ${VENCOMMON} ${VENLOG} ${VENGNM} ${VENVO} ${VENAVP} ${VENDEC})
endif()

add_library(bbios STATIC ${ENGINE_SOURCES})

target_compile_definitions(bbios PRIVATE
  BB_PLATFORM_IOS=1
  SDL_MAIN_HANDLED=1
  $<$<BOOL:${BB_FULL_ENGINE}>:BB_FULL_ENGINE=1>
  $<$<BOOL:${BB_WITH_FEX}>:BB_WITH_FEX=1>)

# Every translation unit — ours and the upstream tree's — gets the iOS ABI shim.
# (platform_ios.h is double/include-guarded, so our .c files including it directly add nothing.)
target_compile_options(bbios PRIVATE "-include" "platform_ios.h")

target_include_directories(bbios SYSTEM PRIVATE
  "${CMAKE_CURRENT_LIST_DIR}"            # platform_ios.h / compat_ios.h for -include
  "${CMAKE_CURRENT_LIST_DIR}/include"    # bbi_public.h
  "${CMAKE_CURRENT_LIST_DIR}/fex")       # FexLoader.h

if(BB_FULL_ENGINE)
  target_include_directories(bbios SYSTEM PRIVATE
    "${UPSTREAM_ROOT}/src"
    "${UPSTREAM_ROOT}/gpu"
    "${CMAKE_BINARY_DIR}/libbbios-deps/include"   # staged dep headers (SDL3/ffmpeg/atrac9)
    "${DEPS_DIR}/fmt/include"
    "${DEPS_DIR}/robin-map/include"
    "${DEPS_DIR}/VulkanHeaders/include"
    "${DEPS_DIR}/VulkanMemoryAl/include"
    "${DEPS_DIR}/XXHash"
    "${DEPS_DIR}/magic_enum/include"
    "${DEPS_DIR}/glslang/glslang/Include"
    "${DEPS_DIR}/glslang/glslang/Public"
    "${DEPS_DIR}/glslang/SPIRV"
    "${DEPS_DIR}/SPIRVHeaders/include"
    "${CMAKE_CURRENT_LIST_DIR}/../overlay/include")
  if(BB_WITH_FEX AND BB_FEX_DIR)
    target_include_directories(bbios SYSTEM PRIVATE "${BB_FEX_DIR}/include")
  endif()
endif()

# Static dep archives are staged by ios/scripts/build_engine.sh into
# ${CMAKE_BINARY_DIR}/libbbios-deps. Recorded only in full mode: the final link
# happens in the app (xcodegen → xcodebuild), which links these by name.
if(BB_FULL_ENGINE)
  target_link_libraries(bbios PRIVATE
    "${CMAKE_BINARY_DIR}/libbbios-deps/libSDL3.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libatrac9.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libavcodec.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libavformat.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libavutil.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libswscale.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libswresample.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libglslang.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libSPIRV.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libsirit.a"
    "${CMAKE_BINARY_DIR}/libbbios-deps/libfmt.a")
  if(BB_WITH_FEX AND BB_FEX_DIR)
    target_link_libraries(bbios PRIVATE "${BB_FEX_DIR}/lib/libFEXCore.a")
  endif()
endif()

target_link_options(bbios PRIVATE
  "-framework" "Metal"
  "-framework" "MetalKit"
  "-framework" "UIKit"
  "-framework" "Foundation"
  "-framework" "CoreFoundation"
  "-framework" "AudioToolbox"
  "-framework" "AVFoundation")
