# 01 — Port plan & phases

Target: **iOS 16.0+, arm64 (A12 / iPhone XS and later), iPhone/iPad**, adaptive **60 FPS target**,
**30 FPS floor** policy: devices weaker than the target run at reduced resolution, the engine's
existing `BB_FPS` / preset logic already supports this (uncap/30/60/90 patch presets, FSR presets).

---

## Phase 0 — Infrastructure (shipped in this scaffold)

| Item | Status |
|---|---|
| GitHub Actions workflow `ios-ipa.yml` (macos runner → engine lib → app → IPA) | ✓ in repo |
| xcodegen project for the launcher app + entitlements for AltJIT/TrollStore | ✓ |
| Platform compatibility layer for iOS (`ios/core`: `compat_ios.c/h`, `platform_ios.h`) | ✓ first pass |
| In-process engine bridge (Swift ↔ C thread start, `bbi_start`) | ✓ first pass |
| Prebuilt-dump pipeline (`ios/tools/prepare_for_ios.*`) so no Python is needed on device | ✓ first pass |

## Phase 1 — Runtime bring-up without CPU execution (engine boots, no game code)

Goal: `bbi_start` runs through: guest image load → runtime_file/memory/kernel/... init →
`bbgpu_init` (SDL window created on the main UI thread, Vulkan instance grabs MoltenVK ICD) →
Vulkan smoke test reports PASS on the device.

Work items, mapped to the upstream files:

1. `compat_win.c/.h` excluded; new `compat_ios.c` implements the POSIX surface the runtime uses
   (mmap shims, `memfd_create` → `shm_open` fallback, per-platform `bb_setjmp` not needed — the
   translator owns unwinding inside guest frames, so `runtime_fault_recover` becomes translator
   state instead of sigjmp — see `docs/03-CPU_FEX.md#faults`).
2. `runtime_thread.c` — the `arch_prctl(ARCH_SET_GS)` Linux path becomes a no-op under FEX (guest
   TLS is owned by the translator; `runtime_thread_tcb_offset()` is not used on iOS because
   `probe.c`'s `mov rax,fs:[0]` rewriting never runs). Handled with a platform-shim layer, no files
   forked.
3. `runtime_memory.c` — guest image base stays **0x800000000** (32 GiB) — see address-space plan in
   `docs/02-ARCHITECTURE.md`; `MAP_FIXED_NOREPLACE` and `memfd_create` are shimmed.
4. `probe.c` — excluded from the iOS build entirely; replaced with `ios/core/start_ios.c` which
   performs the same sequence without emitting x86 trap stubs: boot image parse, relocation apply,
   import resolution hooks, and then hands guest code execution to FEX instead of `enter_on_stack`.
5. `import_names.inc` reused as-is.
6. Snake-pit exclusion list in CMake: `vulkan_smoke.c` kept (it's the Phase-1 success probe),
   GPU-specific `_WIN32` files untouched on POSIX path.

Success criteria: engine launches with the "graphics device ready" log on-device, SDL Metal layer
draws a test pattern, 4-guest-thread pool idles.

## Phase 2 — CPU execution through FEX (the heart)

Spec: `docs/03-CPU_FEX.md`. Stages:

* 2a — FEXCore linked as a static lib, custom `FEXCore::CodeLoader` implementing `LoadMemory`
  to place `BBPROBE5 boot-linked.bin` at the guest layout, entry point → game's real ELF entry.
  Import-trap model: `runtime_resolve` installs guest-side PLT thunks as before, but those stubs
  become translator code; the host trap (`bb_longjmp` recovery vs `sigjmp`) is replaced by FEX
  "guest-to-host" calls.
* 2b — Block cache & write-protection: game code pages are write-protected via the existing
  `runtime_memory_gpu_protect` machinery; the first fault re-translates via FEX's Translate/Recompile.
* 2c — Performance pass: FEX TSO/cycle heuristics tuned to Uncharted's thread mix
  (13 guest threads documented in `docs/DEVELOPMENT_LOG.ru.md`), AOT profiling via FEX profiles.

## Phase 3 — Renderer bring-up (MoltenVK)

Spec: `docs/04-GPU_MOLTENVK.md`. Expected outcome on iPhone GPUs (A15+ obvious best):
* TAA, FSR 1, full shader recompilation path — should work (upstream shadPS4 already runs on macOS
  via MoltenVK).
* FSR 3.1 (FSR-Vulkan provider) — high probability of working; this is the shipped upscaler on iOS.
* FSR 4 / FSR 4.1.1 — **not pursued on iOS** (needs `VK_EXT_shader_integer_dot_product` +
  mixed-float ops that Metal does not expose); CMake option guards them off.
* DLSS — excluded on iOS (no NGX).
* Frame generation — FSR 3 FG only; validated after 2b.
* Cutscenes (AvPlayer + libavcodec): needs FFmpeg static libs for iOS (script included; minimal
  codec set only, keeps CI ~10 min slower but works).

## Phase 4 — Launcher/UX (shipped as scaffold, iterate)

SwiftUI launcher (Library/Display/Controls/Data/Log pages mirroring the Tk launcher), dump import
via Files (UIDocumentPicker with folder copy + validation by signature of `eboot.bin` /
`big2`/`big3`), writes `bbport.ini` from settings, starts the engine in-process via
`EngineBridge.swift` → `bbi_start(key, argv)` thread. Game restart (Uncharted 2's LoadExec) works
because the engine relaunches inside one process (no `execve`).

## Phase 5 — Performance & device matrix

| Device class | GPU | CPU engine | expect |
|---|---|---|---|
| iPhone 15/16 Pro / Pro Max, iPad M1+ | Metal 3 throttled high | FEX TSO on, JIT high | 60 fps @ 1080p + FSR3 |
| iPhone 14/13/12 | Metal 3 baseline | same | 30–60 fps @ 720p–1080p |
| iPhone XS/11 | Metal 2 | JIT | 30 fps @ 720p, TAA only |

Tuning levers shipped by upstream and reused on iOS: `BB_FPS`, `BB_VBLANK_HZ`, render presets,
`live_resolution=auto` (borrowed rule engine gets an iOS-only "thermal" governor), FSR sharpen.

## Phase 6 — Distribution

AltStore/SideStore recommended (AltJIT), TrollStore best for perf; TestFlight drops JIT → not
suitable (document in FAQ). CI produces `Uncharted-<ver>-ios.ipa` with ldid ad-hoc entitlements
template (the loader applies user's real provisioning at install time).

## Known risks & honest gaps right now

1. **FEX on iOS is not officially packaged** — FEXCore targets Linux; the port has to provide an
   `iOS` personality: custom ELF loader path exists (FEXCore::CodeLoader), guest-VA config must
   drop from 48-bit to fit iOS's VM layout, address-space randomization free of `47-bit` overcommit
   must be verified (see docs/03 §1).
2. **MoltenVK feature gaps** for exact Vulkan 1.3 surface the renderer creates (timeline semaphores
   check needs verification; fallback code goes in the Phase 3 bring-up).
3. **FFmpeg/LibAtrac9 build correctness on iOS from CI** (scripts included and used in CI, first
   pass validated visually).
4. Shader cache warmup loop on first launch (engine compiles thousands of SPIR-V pipelines).
5. **No JIT = no playable speed** — AltStore-only users must keep the JIT toggle enabled; FAQ
   documents why and what to do if AltJIT fails (TrollStore route).

Estimate: Phase 1 ≈ 1–2 weeks focused work; Phase 2a (first frames in-game) is the risk-dense
stretch, realistically 2–4 weeks; Phase 3 overlaps with 2; Phases 4/5/6 mostly exist.
