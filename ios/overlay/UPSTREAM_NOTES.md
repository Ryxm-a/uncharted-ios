# iOS overlay — what is dropped over the upstream checkout at build time

The CI workflow `rsync`s the contents of `ios/overlay/` over `upstream/` after the clone.
Files land by their own path (e.g.`ios/overlay/gpu/shim/x` rewrites `upstream/gpu/shim/x`).

Currently staged files (applied as-is, path-preserving):

| overlay file | replaces / adds | why |
|---|---|---|
| `ios/overlay/UPSTREAM_NOTES.md` | `upstream/ios/UPSTREAM_NOTES.md` | marker file; keeps overlay self-documented in the build tree |

**Phase-1 patch list (applied in later bring-up, not yet written):**
* `gpu/shim/window.cpp` — add `VK_EXT_metal_surface` surface creation branch and SDL iOS
  window properties (Phase 3, see `docs/04-GPU_MOLTENVK.md`).
* `gpu/shim/bbport_threads.h` — route `sched_getaffinity` CPU-set math through
  `compat_ios.h`'s shims (automatic via `-include platform_ios.h`, no edit needed).
* `gpu/shim/core/emulator_settings.h` — expose `BB_PLATFORM=ios` string (sanity logging).
* CMake site list — the engine's authoritative build is `ios/core/CMakeLists.txt`.
