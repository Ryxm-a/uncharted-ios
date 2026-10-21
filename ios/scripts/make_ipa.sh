#!/usr/bin/env bash
# make_ipa.sh — assemble the built .app into an ipa with adhoc + JIT entitlements,
# suitable for AltStore/SideStore re-signing, or direct install via TrollStore.
set -euo pipefail
DD="${1:-}"
UP="${GITHUB_WORKSPACE:-.}"
ART="$UP/artifacts"
mkdir -p "$ART"

APP=""
if [ -n "$DD" ]; then
  APP=$(find "$DD/Build/Products" -name "Uncharted.app" -maxdepth 3 -type d | head -n1)
fi
if [ -z "$APP" ]; then
  APP=$(find "$UP/ios/App" "$DD" -name "Uncharted.app" -maxdepth 6 -type d 2>/dev/null | head -n1)
fi
if [ ! -d "$APP" ]; then echo "ERROR: Uncharted.app not found"; exit 1; fi

# Optional: bundle the MoltenVK dylib + ICD when engine is embedded (full engine mode):
if [ -d "$UP/moltenvk" ]; then
  mkdir -p "$APP/Frameworks"
  cp -R "$UP/moltenvk/MoltenVK.framework" "$APP/Frameworks/" 2>/dev/null || true
  cp    "$UP/moltenvk/MoltenVK_icd.json" "$APP/" 2>/dev/null || true
  [ -f "$APP/Frameworks/MoltenVK.framework/MoltenVK" ] && \
    ldid -S "$APP/Frameworks/MoltenVK.framework/MoltenVK" || true
fi

# Ad-hoc entitlement signing (AltStore re-signs with the user's identity and keeps keys):
( cd "$APP" && [ -f "Uncharted" ] && ldid -S "$UP/ios/App/Uncharted.entitlements" "Uncharted" )

PYLD="$ART/Payload"
rm -rf "$PYLD"; mkdir -p "$PYLD"
cp -R "$APP" "$PYLD/"
SHORT=$(git -C "$UP" rev-parse --short HEAD 2>/dev/null || echo "local")
IPA="$ART/uncharted-ios-$SHORT.ipa"
rm -f "$IPA"
( cd "$ART" && zip -qry "$IPA" Payload )
rm -rf "$PYLD"
echo "IPA ready: $IPA"
