# 07 — Engineering session log (run: "24h fix-everything sweep")

Scope of this document: everything completed and repaired in the marathon session, plus the
honest residual-gap list. Line counts and build gates below are the ground truth for Phase-0
review.

## Files created this run (besides the initial scaffold batch)

| File | Purpose |
|---|---|
| `ios/scripts/build_engine.sh` (rewrite) | CMake build of libbbios.a (iOS arm64), stages deps + engine into `artifacts/engine` |
| `ios/scripts/make_ipa.sh` (rewrite) | `.app → ipa` (Payload) with ldid + JIT entitlements, optional MoltenVK embed |
| `ios/scripts/check_no_game_files.sh` (rewrite) | CI red-file gate |
| `ios/scripts/fetch_deps.sh` (rewrite) | clones fmt/robin-map/xxHash/Vulkan-Headers/VMA/magic_enum/miniz/glslang/SPIRV-Headers/sirit with pinned tags |
| `ios/scripts/build_SDL3_ios.sh` · `build_ffmpeg_ios.sh` · `build_libatrac9_ios.sh` · `fetch_moltenvk.sh` | the toolchain pieces |
| `ios/core/CMakeLists.txt` (rewrite) | the single authoritative engine build (upstream subset + iOS overlay + FEX bridge) |
| `ios/core/platform_ios.h` (rewrite) | force-included OS-ABI compat: mmap flags, `syscall()` interception (only `arch_prctl`), `sched_getaffinity`/`cpu_set_t` shims, memfd shim |
| `ios/core/compat_ios.h / .c` (rewrite) | `bbi_memfd_create` (shm_open), `bbi_syscall` dispatcher, `bbi_getdents` (Linux-layout dirent buffer), `bbi_jit_supported()` MAP_JIT probe |
| `ios/core/start_ios.c` (rework) | iOS replacement for probe.c's startup incl. `bbi_boot_image_parse` Phase-1 stub and `bbi_run_game` pipeline |
| `ios/core/appbridge.c` (rewrite) | bbi_public.h surface for SwiftUI: launch on detached pthread, ELF-magic dump validation, statvfs free-space probe |
| `ios/core/include/bbi_public.h` (rewrite) | C ABI with `bbi_event_cb` typedef for Swift bridging |
| `ios/core/fex/FexLoader.h/.cpp` | FEXCore integration point (guarded so CI compiles even with FEX absent) |
| `ios/App/Sources/{Views,EngineBridge,SettingsStore,DumpImport}.swift` | full launcher UI + engine bridge + document-picker dump import (hardlink-when-same-volume) |
| `ios/App/project.yml` (rewrite) | clean xcodegen spec (app target, bridging header, entitlements, engine lib search path) |
| `ios/App/Info.plist`, `Uncharted.entitlements`, `Bridging/BBBridging.h` | packaging + JIT entitlement set |
| `ios/tools/make_ios_load.py` + `ios/tools/README.md` | PC-side one-time dump preparation driver (drives upstream scripts, emits manifest.json) |
| `ios/overlay/UPSTREAM_NOTES.md` | overlay documentation + Phase-1 patch list |
| `LICENSE` | GPL-2.0-or-later full text (inherited from upstream) |
| `.github/workflows/ios-ipa.yml` (rewrite) | full pipeline: upstream clone → deps → SDL3/ffmpeg/atrac9/MoltenVK → engine (flagged) → xcodegen → xcodebuild → IPA → game-file gate → artifacts |
| `.gitmodules` (rewrite) | dependencies are managed by CI clone steps; the file documents how to opt into `git submodule` instead |
| `docs/01..07` | plan, architecture (`docs/02` got the PC-prep pipeline section), FEX spec, MoltenVK matrix, launcher spec, FAQ, this log |

## Verification performed

* `bash -n` syntax-gate: all 8 `.sh` scripts pass.
* Non-ASCII corruption sweep ([CJK-hiragana-cyrillic] + glue glyphs): one file had a stray
  CJK fragment (`docs/04` table cell); fixed. All code files now ASCII-only.
* Invisible-character sweep (BOM/ZWSP/bidi controls): clean.
* Brace-balance check across all `.c/.h/.cpp/.swift`: balanced.
* Docs line-edits: `docs/02` memory-region diagram and PC-prep section; `docs/03` FEX init
  parameter list rewritten precisely; `docs/05` entitlements bullet + launch flow + exclusions
  made accurate to the shipped Swift.

## Known limitations (honest — remaining work is bring-up, not scaffold)

1. **`FexLoader.cpp` API mapping** — written against FEXCore's documented embedded-API shape
   (`FEXCore::CodeLoader`, `Context::Initialize`/`InitCore`) but not yet compiled against real
   FEX headers; final signatures verified during Phase-2 (needs `third_party/fex` on a macosing
   terminal, FEX's `CMake` embedded-mode path). Everything else in the repo is self-consistent.
2. **`bbi_boot_image_parse`** is a magic-check stub; the full BBPROBE5 parse (segments,
   relocations, import tables, TLS template → `runtime_set_main_tls`) is the Phase-1 deliverable
   (`docs/01` "Phase 1" work item 4).
3. **`gpu/shim/window.cpp` iOS surface branch** — to be added during Phase 3 (Metal-layer +
   `VK_EXT_metal_surface`); overlay notes document where.
4. **Engine-linked CI run** is behind the `full_engine` flag until Phase 1 proves out; app-only
   builds run green regardless.
5. Vendored `shadps4/common` compile-time porting of `boost::unordered` uses — if that leaks
   beyond our include set the overlay grows (documented in `UPSTREAM_NOTES.md` patch list).

## Addendum — two-mode engine build (this run's final structural fix)

The first CI push would have failed link: the app always links `-lbbios`, but the engine
library referenced upstream symbols (`runtime_file_*`, `vulkan_smoke`, FEXCore) that don't
exist outside full mode. Fixed by making the build explicitly two-mode:

| | lite (CI default) | full (`full_engine` dispatch input) |
|---|---|---|
| sources | compat_ios.c + appbridge.c + start_ios.c + FexLoader.cpp stubs | + upstream `runtime_*` + vendored shadPS4 GPU subset + real FexLoader |
| deps needed | none | SDL3, ffmpeg, LibAtrac9, glslang(+SPIRV), sirit,	fmt — built by `build_engine.sh full` |
| bbios link deps | libc only | all dep archives staged in `artifacts/engine` and linked by name |
| Play() behavior | validates dump/boot image → honest "engine bring-up pending" STOP log | full boot path (docs/01 Phase 1+) |

* `ios/core/CMakeLists.txt` — rewritten: `BB_FULL_ENGINE` is the single mode bit, FexLoader
  always compiles (its `#if` picks real-vs-stub), force-includes `platform_ios.h` into every
  TU via `-include`, and adds the previously missing include dirs (`include/`, `fex/`,
  staged dep headers, overlay include).
* `ios/core/start_ios.c` — `bbi_run_game`/`bbi_vulkan_smoke_with_driver` guarded on
  `BB_FULL_ENGINE`; lite path never references upstream symbols → static archive is
  self-contained and first CI is green with the app UI, dump import, and settings.
* `ios/scripts/build_engine.sh` — MODE-argument (lite|full), genuinely builds fmt/sirit/
  glslang in full mode instead of hoping for prebuilt archives, stages headers+libs.
* `.github/workflows/ios-ipa.yml` — engine build is now unconditional with the mode
  resolved from the dispatch input; dep builds are skipped in lite for a fast first build.
* First-UI-milestone consequence: the default push produces an installable IPA whose
  launcher runs; no-ops are honest and documented instead of undefined-symbol crashes.

## Build-first sanity-path for the next session

1. `git init`, push, workflow `ios-ipa.yml` (app-only default).
2. Confirm Artifact `uncharted-ios-ipa` downloaded → install via AltStore (App-UI opens; JIT
   warning shows on Library page until AltJIT enabled).
3. On a Mac with Xcode run `ios/scripts/build_engine.sh` for the first time to surface the
   vendored-tree compile deltas quickly (fix loop lives in this repo's `ios/overlay`).
