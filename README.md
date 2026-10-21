# Uncharted: The Nathan Drake Collection — iOS Port (bbport-ios)

Native port of **Uncharted 1/2/3 from the PS4 Nathan Drake Collection** running on iPhone/iPad
(ARM64, iOS 16+), derived from SuperMedo's Windows port (`Supermedo/uncharted_pc`, itself derived
from deadinside28's Linux bbport, built on the shadPS4 renderer).

**Status: scaffold complete and internally consistent (see `docs/07-SESSION_LOG.md`).**
This repository ships the complete iOS infrastructure — build system, CI pipeline that produces a
signed-side IPA, the SwiftUI launcher, the iOS platform/runtime compatibility layer, and the
FEX-emu CPU-translation bridge — with every shell script passing `bash -n`, every code file
ASCII-verified, brace-balanced, and a CI red-file gate blocking accidental shipping of Sony data.
The two remaining bring-up items (compiled-against-real-FEX-header signature check in
`FexLoader.cpp`, and the Phase-1 BBPROBE5 parser that upgrades the magic-check stub) are tracked
in `docs/01-PORT_PLAN.md` and `docs/07-SESSION_LOG.md`.

**Build modes.** CI builds `libbbios.a` in *lite* mode by default (shim layer only — no upstream
symbols, guaranteed-green link; Play() in the app validates your dump then reports "engine
bring-up pending"). Run the workflow with `full_engine = true` for the full upstream + FEX
surface as Phase-1 bring-up lands.

## How it works

The Windows PC port works because PS4 executables are **already x86-64**, and PCs are x86-64 — the
game code runs natively. iPhones are ARM64, so iOS runs every guest PlayStation instruction through
**[FEX-Emu](https://fex-emu.com)** (MIT-licensed x86-64→ARM64 dynamic translator), while everything
else (renderer, GPU, audio, saves, input) is translated natively:

```
┌──────────────────────────────────────────────────────────────┐
│ Uncharted.app                (SwiftUI launcher, in-process)  │
│   └── library picker · dump import · settings → bbport.ini   │
│        └── launches engine thread in the same process        │
│            ┌───────────────────────────────────────────┐     │
│            │ libbbport_ios.a (C/C++ core, from upstream)│    │
│            │  src/*         PS4 runtime, POSIX layer    │    │
│            │  FEX-emu       x86-64 → ARM64 CPU engine   │    │
│            │  gpu/shim      shadPS4 renderer shim       │    │
│            │  ⊘ Vulkan → MoltenVK → Metal (AAPL GPU)    │    │
│            └───────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
```

**JIT.** iOS refuses executable memory in ordinary sideloaded apps. A translating CPU engine needs a
JIT. Distribution strategy is therefore:

| Install path | JIT | Performance |
|---|---|---|
| **AltStore / SideStore** (recommended) | AltJIT companion | full speed |
| **TrollStore** | native | full speed |
| TestFlight / App Store | ✗ none | would not run the games |

The JIT entitlement and a graceful "no JIT → interpreter-only, will be very slow" fallback are both
implemented. See `docs/06-LIMITATIONS_FAQ.md#jit`.

## Layout

```
docs/                 Plan, architecture, subsystem bring-up specs, FAQ
ios/App/              SwiftUI launcher app (xcodegen project, entitlements)
ios/core/             iOS C/C++ additions compiled into the engine lib:
                      compat layer, entry point, FEX bridge, dumps loader
ios/scripts/          CI-local build scripts (deps, engine, IPA packaging)
ios/overlay/          Files dropped over the upstream checkout at build time
third_party/          Git submodules: upstream source, FEX, MoltenVK, SDL3
.github/workflows/    ios-ipa.yml — builds the whole thing and turns it into an .IPA
```

## Building locally / CI

CI does everything; locally on any Mac:

```bash
git clone --recursive https://github.com/<you>/uncharted-ios
cd uncharted-ios
.github/workflows fragments are mirrored by: ios/scripts/build_all.sh    # WIP-phase flag
```

## Game dumps (legal)

No game files are distributed. You need **your own decrypted dump** of the collection
(CUSA02343 / CUSA02320 / … folder with `eboot.bin`, `big2-ps4_Shipping.elf`,
`big3-ps4_Shipping.elf`, `sce_sys`, `u1data`, `u2data`, `u3data`), placed into the app's
Documents folder via on-device import. First-run conversion is performed once on a PC with the
bundled `ios/tools/prepare_for_ios.*` helper (Python STEP is skipped in-app — iOS cannot run
Python). Not affiliated with Sony or Naughty Dog; GPL-2.0+.
