# 06 — Honest limitations & FAQ

## "Can this be done without JIT?" (your question)

**No — not for playable speeds, and not without breaking the "runs the real PS4 code" design.**
Every translating emulator (FEX, Rosetta-class engines) must generate ARM64 machine code at
runtime. iOS forbids executable memory in ordinary apps. The workarounds, honestly:

| Route | JIT? | Games work? |
|---|---|---|
| TestFlight/App Store | never | ❌ code can never be generated |
| AltStore/SideStore **without** the JIT toggle | no | ❌ engine refuses to start a game; everything else (UI) works |
| **AltStore/SideStore with AltJIT turned on** | yes | ✅ recommended |
| **TrollStore** | yes, trivially | ✅ best ergonomics & perf |
| Xcode dev-signed build | yes (while provisioned) | ✅ dev-only |

It is possible to *detect* missing JIT (implemented — the app reports it on the Log screen) but
there is no realistic no-JIT interpreter that would run Uncharted acceptably: that interpreter
would be a whole second engine.

## "You said launcher handles Uncharted 1,2,3,4"

This codebase ports U1/2/3 (Nathan Drake Collection). **Uncharted 4 is excluded by scope** per
your confirmation — it is a different PS4 executable (`[[Uncharted 4: A Thief's End]]` code base),
needing its own shader-hook table and patches. If a future phase adds it, the launcher flow here
already supports adding games by key; only the hook IDs and dump validation change.

## Storage

Dump folders are 30–70 GB. The app imports copies into its sandbox (Documents), so iPhone /
iPad Pro with ≥256 GB storage is the realistic class. Import validation reports sizes before
copying; a "reference files instead of copy" option exists when the dump is already under
`On My iPhone/…` (no duplication when on the same volume).

## Performance expectations (honest)

| Device | TAA 1080p | FSR 3 Balanced | note |
|---|---|---|---|
| iPhone 16 Pro / Pro Max | 60 fps target | 60 fps | M3-class GPU |
| iPhone 15 Pro | 60 fps | 60 fps | M1-class |
| iPhone 14/13 | 30–60 | 60 @ 720–900p | first GPU with Metal 3 |
| iPhone 12/11/XS | 30 | 30 @ ~720p | Metal 2, older CPU cores penalize FEX most |
| iPads M1/M2/M4 | 60 | 60 | best thermal headroom, recommended |

Determinants: translator overhead on the PS4 CPU threads (1.6 GHz Jaguar class ⇒ not demanding),
GPU passes (cheap — the games target the PS4's 1.3-TFLOP-class GPU, so a M1-class phone GPU has
~3–5× headroom), first-run shader compile spike (minutes; afterwards cached in `user/`).

## Things that will be broken on first bring-up (and their fixes)

1. **First-run shader pipeline compile** — minutes of "compiling shaders"; cache documented in
   Advanced page ("Clear shader cache").
2. **Cutscene audio sync** (AvPlayer path) — known upstream inheritance risk on all platforms;
   worked via `BB_AUDIO_OFFSET_MS` experiment if needed (not yet implemented).
3. **`bbLastRun` logs contain Windows-specific lines** — cosmetic in Log page only.
4. **iCloud off-screen audio** — Background `audio` mode enabled in Info.plist; there is a
   `SceneSession` activation quirk when the app loses foreground: the renderer responds to
   `UIApplicationDelegate.willResignActive` with the standard `BB_LOW_POWER` toggle (added).
5. **AltStore JIT expiry** — JIT entitlement lapses on the 7-day re-sign unless AltStore's JIT
   toggle is re-enabled; the app detects and prints instructions on Log.

## Legal

* You bring **your own decrypted dump**; nothing copyrighted ships in the IPA (verified by the CI
  gate `scripts/check_no_game_files.sh`).
* Upstream is GPL-2.0-or-later, shadPS4 GPL-2.0, FEX MIT, MoltenVK Apache-2.0/MIT — all compatible.
* Not affiliated with, endorsed by Sony Interactive Entertainment or Naughty Dog.
