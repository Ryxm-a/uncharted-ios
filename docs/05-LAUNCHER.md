# 05 — SwiftUI launcher (the IPA's front door)

One binary, no subprocesses: the SwiftUI app runs both the launcher and the engine (iOS forbids
`exec`). Upstream's `run.py`/`run.sh` contracts are honored exactly:

* engine env (set by the app before launching the engine thread):
  `BB_GAME_DIR`, `BB_GAME_DIR_U1/U2/U3`, `BB_EXE`, `BB_USER_DIR`, `BB_CONFIG`, `BB_INPUT_CONFIG`,
  `BB_RENDER_RES` / `BB_OUTPUT_RES`, `BB_FPS`, `BB_UPSCALER`, `BB_REACTIVE…`, `BB_FRAME_GEN`,
  plus the RGB hook IDs (`BB_VELOCITY_PS=f4b18264`, `BB_UPSCALE_BEFORE_CS=aec539f0`,
  `BB_HUDLESS_PS=484cdbf5`) identical to upstream `run.py`.
* `user/` directory = `Documents/user/`, auto-created.
* In-process `sceSystemServiceLoadExec` — the runtime calls `bbi_request_exec(key)`, suspending the
  current engine thread; the app stops the renderer, tears down FEX contexts, and re-enters the game.

## Screens (mirroring `uncharted_launcher.py`)

| Page | Contents |
|---|---|
| **Library** | three cover cards (U1/U2/U3 bundled, or the dump's `sce_sys/icon0.png`); tap → Play; hero banner uses `collection_banner.jpg` if present, else gradient |
| **Game / Data** | import dump folder (UIDocumentPickerDirectory → copy/validate: eboot.bin ELF magic + `u1data` directory presence), storage check, convert-on-PC instructions, saves size manager |
| **Display** | frame rate (30/60/90/Uncap), present mode, render resolution presets, upscaler (TAA/FSR 3.1 only on iOS), RCAS sharpen, output resolution, FPS counter toggle |
| **Controls** | Multi-Finger touch map + MFi controller remap; writes `input.ini` (same file format as upstream – `key.<action>` / `pad.<action>`) |
| **Advanced** | shader cache clear (`BB_SHADER_CACHE_CLEAR` flag in app Documents), FEX profile clear, log level (`BB_GPU_LOG`), env overrides table |
| **Log** | tails `Documents/user/last_run.log` + `BB_FPS_LOG` summaries |

## Files

* `ios/App/project.yml` — xcodegen project: target `Uncharted`, iOS 16.0, arm64-only,
  bridging header exposing `bbi_*` C API from `ios/core/include/bbi_public.h`.
* `ios/App/Info.plist` — file sharing enabled (import via Files), background modes
  (`audio` for screen-off audio), `UIRequiresFullScreen` off (iPad), supported orientations all.
* `ios/App/Uncharted.entitlements` — `com.apple.security.cs.allow-jit` (AltJIT/TrollStore honor it),
  `com.apple.security.cs.disable-executable-page-protection` + `allow-unsigned-executable-memory`
  for MAP_JIT-class generation, and the extended-memory entitlements
  (`com.apple.developer.kernel.extended-virtual-addressing`, `.increased-memory-limit`).
  AltStore re-signs with the user's identity; TrollStore grants entitlements as installed.
* `Sources/*.swift` — the UI + `EngineBridge.swift` (thread spawn → `bbi_start_game(game, dir,
  user, boot, cb)`; events: `state`, `log`, `exit:<rc>` — surfaced on the Log page and Library).

## Launch flow

1. Model: `LaunchedGame(key: "u1"|"u2"|"u3", env: [String:String])`.
2. `EngineBridge.start(key:)` → engine thread → events `state` (`starting`), then engine logs.
3. Stop action: `EngineBridge.stop()` → `bbi_stop_game()`, engine thread unwinds.
4. Crash handling: any `exit:<rc>` (or STOP log line) surfaces the last 200 lines on the Log page.

## What is intentionally NOT ported from the Tk launcher

* "Add to Steam", desktop shortcuts — meaningless on iOS.
* Self-update checker — AltStore/SideStore handle IPA updates; skipped.
* Language table — the SwiftUI app ships English first; upstream's 11-language tables can be reused in a later pass.
