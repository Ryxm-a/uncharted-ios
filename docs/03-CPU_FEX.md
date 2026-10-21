# 03 — CPU engine: FEX-Emu integration on iOS

The PC port runs PS4 x86-64 code natively. On iOS the CPU is ARM64, so guest instructions are
translated by [FEX-Emu](https://fex-emu.com) (`FEXCore`, MIT). This file specifies the exact
integration. The bridge code lives in `ios/core/fex/` (`FexLoader.h/.cpp`).

## 1. Guest address space policy

FEX normally relies on Linux's 47-bit user VA with its "guest base" relocation feature
(`GuestBase`) to place a 48-bit space; iOS gives app processes a smaller reachable region, so:

* Guest image base stays **0x800000000** (the upstream probe maps the eboot there) — that is
  32 GiB, well inside iOS app VA reach.
* FEX's `Personality` / `ABI` layers (Linux syscall surface — mmap, memfd, pipe, how FEX
  dispatches interrupts) are hidden: native PS4 binaries don't do Linux syscalls — every guest
  "syscall" is actually a PS4 libc/library import resolved by `runtime_resolve`. So FEX syscall
  emulation is bypassed; `runtime_resolve` handles everything, `FEXLoader` never installs FEX's
  Linux syscall hook. That makes this an "embedded personality" rather than a Linux personality.
* `FEXCore::Context::Initialize` gets
  `Is64BitMode`, `Personality = embedded` (no Linux syscall hooks — all guest imports are PS4
  NID calls resolved by the C runtime), forward-dynamic recompilation enabled,
  metadata host arch `X86_64` even on the ARM64 host, and one FEXCore context per guest
  thread ("multi-context" mode, matching upstream's TestHarness behavior).

## 2. Loading the boot image

`probe.c` parses `BBPROBE5` and maps `runtime_image_map(size, prot)`. On iOS `FexLoader.cpp`
replaces that C++ main:

* Images: same layout, into the same VA regions using the same relocation lists — the C++ loader
  reuses the code of `src/prepare.py`'s output contracts unchanged.
* `FEXCore::CodeLoader` interface is implemented (`BbFexCodeLoader`), so FEXCore builds each guest
  thread's entry by calling `LoadMemory` for each guest segment and exposing
  `GetEntryPoint() = image entry`. FEX does no ELF parsing of its own because the boot file is
  pre-flat (this is exactly why `scripts/prepare.py` builds `BBPROBE2..5`).
* Entry `argc/argv`: guest main thread enters with `argc=…` exactly like the PC path.

## 3. Import/PLT traps

The boot image contains the table of unresolved guest imports; upstream probe builds a stub in
guest memory that jumps to an unresolved "trap" address. On iOS, each import becomes:

* a **guest-to-host call**: FEX supports function thunks (its "thunks" framework) — the iOS loader
  installs a thunk table where each import's trap address is registered as a FEX thunk pointing to
  the runtime's `runtime_resolve`-produced host pointer. The ABI prefix (`ms_abi` semantics in the
  upstream guest callbacks) becomes irrelevant since args pass through FEX's guest ABI normally.
* data imports (`__stack_chk_guard` etc.) resolve to guest-memory data cells in the image, filled
  by `runtime_resolve(name, is_data=1)` — unchanged.
* The `mov rsi,rdi; mov edi,N` guest stub content is not needed (no C runtime rewriting);
  `patch_tcb_loads` never runs — `guest TLS` is FEX data.

## 4. Faults

* `probe.c`'s SIGSEGV/VEH machinery and `bb_setjmp` recovery don't run on iOS: FEXCore owns
  translation faults and delivers a callback (`Context::SetImporterNotification`-style hooks).
* GPU page faults (the interesting one: shadPS4's page-manager uses guest page protection through
  `runtime_memory_gpu_protect`) go through `bbgpu_handle_fault` as before, but on iOS the fault
  arrives from FEX's memory manager callback rather than a host signal — the shim's
  `Core::Signals` dispatch is the bridge point; the code path is retained, the probe-side
  `fatal_exception` decoder is excluded.

## 5. Threading

Upstream guest pthreads → host pthreads (Linux path). On iOS each `scePthreadCreate` allocates a
**FEX CPU context** and a host pthread that `RunContext`'s it; thread stacks come from
`runtime_low_map` as today. FEX TSO option (x86 store/load ordering) is disabled per-thread after
we measured the games' requirements (Uncharted targets are not race-hungry beyond SIMD fences) —
it will be toggled when data races show up. FEX's `Scheduler` is pinned to heterogeneous cores
with `BbThreads::MakeBackground` (already upstream) for the presenter thread.

## 6. Performance model

* FEX on Apple Silicon class hosts ≈ estimated 60–80% native; on A16/A17 Pro (same µarch family
  as M1/M2) expect the mid-band.
* Costs: MOVI-heavy PPU SIMD? Uncharted is SSE4/AVX — wide coverage in FEX; the AVX-only paths
  (PS4 eboot uses AVX, BMI1, LZCNT, MOVBE…) — FEX handles all of them natively.
* AOT saving: FEX's AOT profile writing is enabled (`BB_FEX_PROFILE`) writing to
  `Documents/fex-cache/`; subsequent launches are warm.

## 7. Files & interfaces specified

* `ios/core/fex/FexLoader.cpp` — context lifecycle, `BbFexCodeLoader` (LoadMemory, GetStackBase,
  GetEntryPoint, FilePointerMap), per-thread `NewContext`/`RunThread`, thunk installer using
  the runtime's `runtime_resolve` directly.
* `ios/core/fex/README.md` — worked notes + build flags (`-DFEX_CORE=true`, `-DFEX_INTERPRET` off).
* CMake option `BB_WITH_FEX=1` in the CI workflow. Fails hard at config time when the submodule
  is missing with the explicit message pointing to `git submodule update --init third_party/fex`.

## 8. No-JIT fallback (AltStore without AltJIT, TestFlight)

`bbi_jit_supported()` (probe mmap PROT_EXEC + MAP_JIT write probe) → false → engine reports
"CPU translation unavailable — this is not playable, install with JIT (see docs)"
and refuses to enter a game; interp fallback is not shipped because a precise x86 interpreter is
not part of the FEX route.
