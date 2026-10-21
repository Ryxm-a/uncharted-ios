#!/usr/bin/env bash
# check_no_game_files.sh — CI gate: refuse to ship anything that looks like Sony game data.
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(dirname "$0")/../..}"
ART="$ROOT/artifacts"
[ -d "$ART" ] || { echo "no artifacts dir; gate skipped (app-only build)"; exit 0; }

PATTERN='(\.psarc$|eboot\.bin$|big[23]-ps4_Shipping\.elf$|u[123]data/|sce_sys/|param\.sfo$|icon0\.png$)'
bad=$(find "$ART" -type f -print0 2>/dev/null | \
      tr '\0' '\n' | grep -Ei "$PATTERN" || true)
if [ -n "$bad" ]; then
  echo "GAME-FILE GATE FAILED. Redistributing copyrighted PlayStation data is forbidden:"
  echo "$bad"
  exit 1
fi
echo "gate passed: artifacts ship no game files."
