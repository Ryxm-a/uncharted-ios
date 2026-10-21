#!/usr/bin/env bash
# fetch_moltenvk.sh OUTDIR — MoltenVK iOS prebuilt from Khronos release assets.
# Pinned tag keeps CI reproducible; upgrade deliberately (docs/04 security matrix).
set -euo pipefail
OUT="$1"; mkdir -p "$OUT"
TAG="v1.2.10"
if [ ! -f "$OUT/MoltenVK/fetched" ]; then
  URL="https://github.com/KhronosGroup/MoltenVK/releases/download/$TAG/MoltenVK-ios.tar.gz"
  curl -fL --retry 3 "$URL" -o "$OUT/mv.tgz"
  mkdir -p "$OUT/MoltenVK"
  tar -xzf "$OUT/mv.tgz" -C "$OUT/MoltenVK"
  touch "$OUT/MoltenVK/fetched"
fi
# locate ICD + framework:
ICD=$(find "$OUT/MoltenVK" -name "MoltenVK_icd.json" -o -name "MoltenVK.icd" | head -n1)
FW=$(find "$OUT/MoltenVK" -name "MoltenVK.framework" -o -name "libMoltenVK.dylib" | head -n1)
[ -f "$OUT/MoltenVK_icd.json" ] || cp "$ICD" "$OUT/MoltenVK_icd.json"
[ -z "$FW" ] || cp -R "$FW" "$OUT/" 2>/dev/null || cp "$FW" "$OUT/" 2>/dev/null || true
echo "MoltenVK ready in $OUT (icd: $OUT/MoltenVK_icd.json)"
