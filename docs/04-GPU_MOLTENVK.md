# 04 — Renderer: Vulkan → MoltenVK → Metal on iOS

The vendored shadPS4 renderer speaks Vulkan 1.3. On iOS that means **MoltenVK** (MIT) translating
Vulkan to Metal. The shadPS4 code already runs on macOS over MoltenVK (upstream), which is why this
port is feasible; the deltas for iPhone are documented here.

## Bring-up pieces included

| Piece | iOS behavior |
|---|---|
| `shim/window.cpp` (SDL3) | OS-if branch in `CreateWindowProps`: uses `SDL_WINDOW_METAL` layer properties + iOS surface `VK_EXT_metal_surface` → `vkCreateIOSSurfaceMVK` equivalent; window resize/fullscreen semantics map to device orientation & safe areas |
| Vulkan ICD selection | `bbport_vulkan.py` is Linux-only; on iOS the bundled `MoltenVK_icd.json` inside the app bundle is forced via `VK_ICD_FILENAMES` in `bbi_start` env setup |
| `vk_instance.cpp` feature checks | tweaks via `ios/overlay/src/vk_instance_ios.cpp` — see feature matrix below |
| Timeline semaphores in `vk_scheduler.h` | MoltenVK implements timeline semaphores on Metal 3 devices (A15+); older devices need a fence-chain fallback — gating and code listed in the work items |
| `bb:DrawRec` / `vk_draw_pipe.h` two-stage pipeline | unchanged (CPU-side) |
| ImGui overlay `bbport_overlay.cpp` | unchanged (Vulkan backend works on MoltenVK); font atlas upload path validated on Metal |
| `vk_fsr4.cpp` / `fsr411/` / `vk_dlss.cpp` | **excluded on iOS** by CMake option `BB_IOS_ALLOW_FSR4=0` |

## Feature → Metal matrix (verified against MoltenVK's documented support)

| Vulkan feature the renderer uses | Metal on iPhone | iOS verdict |
|---|---|---|
| `VK_KHR_swapchain` + CAMetalLayer | ✓ | works |
| Compute pipelines + push descriptors | ✓ | works |
| `timelineSemaphore` | A13+ OK / older partial | **sanity check in bring-up**, fence-chain fallback coded |
| `VK_EXT_shader_stencil_export` (dynamic-res fallback path) | not on Metal | **not available**: the *startup-resolution* patch path is the default on iOS instead (same as upstream default) — no functional loss |
| `VK_KHR_fragment_shader_barycentric` (live-res "auto" gate) | Metal 3 has barycentric on Apple silicon? *No on Metal for Apple GPUs* | gate freed with `live_resolution=0` default on iOS (upstream default too) |
| Storage images/buffers, integer math, fp16 | ✓ (Metal 2+ GPU family) | works |
| `VK_EXT_shader_integer_dot_product` (FSR 4.1.1) | n/a | excluded |
| Mixed-float dot products (FSR 4.1.1) | n/a | excluded |
| Blit/Copy formats the `SceneTargets` path uses | ✓ RGBA8/RGBA16F/D32S8 | works |
| Geometry shader / tessellation | ✓ (Metal tess via MSL translation) | works |
| Indirect draws | ✓ | works |
| shaderInteger16 etc. (Metal 3) | ✓ | works |

## What ships

* Upscaler default on iOS: **FSR 3.1** (the FSR-Vulkan provider is a git submodule upstream with
  its two patches applied — both are pre-existing bbport patches; they compile on Apple).
* Native TAA: supported and cheap; games are 30→60 fps trivially on Metal 3 devices via the
  `BB_FPS` presets in `patches.py`'s `FPS_PRESETS` contract.
* Frame generation: **FSR 3 frame generation** (provider in FSR-Vulkan); DLSS FG excluded.

## Work items in bring-up order

1. `bbi_start` marks env: `BB_PLATFORM=ios`, `VK_ICD_FILENAMES=<bundle>/MoltenVK_icd.json`,
   `SDL_RENDER_DRIVER=` unset; brings up SDL Metal view.
2. `vulkan_smoke.c --vulkan-only` must PASS with MoltenVK on device (Phase 1 success test).
3. Static start: `bbgpu_init` with `BB_PRESENT_MODE=Mailbox`, `BB_DMEM_MB=2048`
   (game VM: 6 GB budget met on iPad M1/Pro; iPhone 15 Pro Max 8 GB ram revised: `BB_DMEM_MB=4096`).
4. Replace `patch_tcb_loads` exclusion & x86-only code with the FEX path (see docs/03).
5. Cutscene decode: FFmpeg iOS static libs (`ios/scripts/build_ffmpeg_ios.sh`, minimal codec set:
   `--enable-parser=h264 --enable-decoder=h264,hevc,atrac9? --enable-protocol=file`); AvPlayer/HLE
   untouched because it consumes FFmpeg API.
6. ATRAC9 audio path: LibAtrac9 static lib decode; SDL3 iOS audio uses AVAudioSession — activated
   for `.playback` with `.defaultToSpeaker` on iPad.
7. Save icon → in-app cover: `sce_sys/icon0.png` per game; launcher Data page reuses it.
