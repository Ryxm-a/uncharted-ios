# 02 — Architecture: PC port → iOS

## Component mapping

| Upstream (PC) | iOS counterpart | Notes |
|---|---|---|
| `Uncharted.exe` (PyInstaller Tkinter launcher) | `Uncharted.app` (SwiftUI, ships in the IPA) | launcher **and** runner are one binary; no subprocess on iOS |
| `run.py` + `run.sh` + scripts/prepare/link/patches/content (Python) | `ios/tools/prepare_for_ios` (run once on PC/Mac) → produces 3 files placed next to the dump; the app consumes them | iOS cannot exec Python; scripts run at *import time*: `boot-linked.bin` (BBPROBE5), `patches.bin` (BBPATCH2), `content.bin` (BBCONT01) |
| `bb-probe.exe` (`src/probe.c`) | `ios/core/start_ios.c → FexLoader.cpp` | no x86 trap stubs; boot image parsed, relocations applied, CPU entries delivered to FEX |
| PS4 code execution `enter_on_stack` on native x86 stack | FEXCore::Context guest thread (each guest thread becomes one FEX CPU context) | guest TLS no longer tied to GS/FS; TCB pointers handed to FEX |
| `gpu/shim` + vendored shadPS4 video_core | unchanged (POSIX path already works); SDL3 window target = iOS CAMetalLayer; Vulkan driver = MoltenVK ICD | see docs/04 |
| `bbport_dlss.dll` (NVIDIA NGX bridge) | excluded on iOS | no NGX |
| FSR 4.1.1 assets | excluded on iOS (feature-gated) | see docs/04 |
| ATRAC9 audio via LibAtrac9 + SDL3 audio | unchanged, static lib link | SDL3 iOS is standard |
| Save data `<user>/savedata/...` | app sandbox Documents/saves | same layout |
| `user/last_run.log`, `BB_FPS_LOG` | same files under app Documents; rendered in launcher Log page | |

## Memory layout (iOS)

iOS on arm64 gives app processes a modern large VA space; the engine needs three regions:

```
0x0001_0000_0000...                  guest image base 0x800000000 (32 GiB) — same as PC
  ...
0x0800_0000_0000..0x0FFF_FFFF_FFFF   guest direct memory / flexible pools (runtime_memory.c)
```

Constraints handled by `platform_ios.h` and `compat_ios.c`:
* `MAP_FIXED_NOREPLACE` is shimmed (`platform_ios.h`), since Linux-only; call sites retry with
  `MAP_FIXED` after a probe-map freed check (iOS app owns its VA space; collisions are impossible
  once the launcher allocates nothing else in that range).
* `memfd_create` is not on Darwin: `platform_ios.h` red-flags it to `bbi_memfd_create` in
  `compat_ios.c` which uses `shm_open` + `ftruncate` + `shm_unlink` (iOS allows POSIX shm in
  sandbox). `MAP_NORESERVE` is defined to 0x0 — pages commit on first touch; enough RAM headroom
  exists only on ≥6 GB devices (a launch-time check in `bbi_start` enforces the floor).
* `MAP_ANONYMOUS` (not `MAP_ANON`) is normalized; `PROT_NOREPLACE` is unused.

## One-time PC-side preparation (before import)

The iOS app cannot run Python, so the upstream pipeline (prepare → link_libc → link_modules →
content_profile → patches) is executed **once on a PC or Mac** by `ios/tools/make_ios_load.py`,
dropping `boot-linked.bin` + `patches.bin` + `content.bin` beside `eboot.bin` in the dump.
The app imports the result through Files; manifest checksums let it validate the copy integrity.

## Threads & guest TLS (FEX-owned)

PS4 guest threads become FEX CPU contexts. The C-runtime's per-thread state (errno, TCB pointer,
guest FPU flags) is attached through FEX's context userdata instead of host TLS. Guest pthread
library, cond/mutex/rwlock, fiber — all in the same runtime files (POSIX-friendly already).

## JIT / W^X handling

iOS allows JIT only with an entitlement, and only with `MAP_JIT` + `pthread_jit_write_protect_np`
per-thread toggling. All translation happens on FEX's worker threads, so the bridge handles
`mmap(MAP_JIT)` when `__arm64__` + installed entitlement claimed, otherwise the `mmap` of
PROT_EXEC fails — the explicit failure is reported on the Log page
("Enable AltJIT, or install via TrollStore").

## Files the iOS build compiles

CMake (ios/core/CMakeLists.txt) enumerates:

* upstream `src/*.c` **except** `probe.c`, `compat_win.c`, gated by `BB_PLATFORM_IOS`.
* `ios/core/*.c` — compat layer, entry point, FEX bridge, app-thread bridge, self/image loader.
* vendored shadPS4 tree via the upstream `gpu/CMakeLists.txt` structure, with an iOS exclude
  list in the overlay (see `ios/core/CMakeLists.txt` and `ios/overlay/UPSTREAM_PATCHES.md`).

## Addressizable psuedorandom pieces

* `runtime_guest_errno` — FreeBSD errno values used by libkernel: bridged with compat function
  identical to upstream Linux branch (no change needed).
* `MLINFO` (x86-64 trap stub emission in probe.c) — not compiled on iOS: FEX's own import
  trapping replaces `mov rsi...; jmp unresolved` stubs (see docs/03 §2).
* In-game restart (`sceSystemServiceLoadExec`) — in-process relaunch through
  `bbi_request_exec(key)` rather than `CreateProcessA`, keeping the FEX context alive.

## What stays native

Vulkan (MoltenVK), Metal (via SDL3's CAMetalLayer), SDL3 (input: MFi, touch, audio session),
FFmpeg (minimal codec set), Dear ImGui, the shadPS4 shader recompiler, LibAtrac9.
