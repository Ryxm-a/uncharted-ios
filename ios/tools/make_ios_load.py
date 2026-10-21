#!/usr/bin/env python3
"""make_ios_load.py — one-time PC-side preparation of a PS4 dump for the iOS port.

Run on Windows/macOS/Linux (no PS4 needed beyond the dump you already own):

    python3 make_ios_load.py /path/to/CUSA02343_folder [-o out_dir] [--exe big2-ps4_Shipping.elf]

It drives the upstream Python pipeline EXACTLY as run.sh does, but produces the three
artifacts the iOS app consumes instead of launching a PC process:

    out_dir/boot-linked.bin     (BBPROBE5)  guest image, relocations resolved
    out_dir/patches.bin         (BBPATCH2)  FPS preset / resolution writes
    out_dir/content.bin         (BBCONT01)  AppContent emulation data
    out_dir/manifest.json       (whatever versions, sizes, hashes for the app to check)

Copy `out_dir` INTO your dump folder (the pipeline only reads the dump dir; the app
expects the three .bin files sitting beside eboot.bin). ~2 minutes; no game files
are added or modified.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT_GUESS = Path(__file__).resolve().parents[2]        # upstream checkout


def run_scripts(game: Path, out: Path, exe: str):
    def run(*cmd):
        print("+", " ".join(cmd))
        proc = subprocess.run(cmd, cwd=str(REPO_ROOT_GUESS) if REPO_ROOT_GUESS.exists() else ".")
        if proc.returncode != 0:
            sys.exit(f"FAILED({proc.returncode}): {' '.join(cmd)}")

    run(sys.executable, "scripts/prepare.py", str(game), "--out", str(out), "--exe", exe)
    run(sys.executable, "scripts/link_libc.py", str(game), "--out", str(out))
    run(sys.executable, "scripts/link_modules.py", str(game), "--out", str(out), "--exe", exe)
    run(sys.executable, "scripts/content_profile.py", str(game), "--out", str(out))
    run(sys.executable, "scripts/patches.py", str(game), "--out", str(out), "--xml")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fd:
        for chunk in iter(lambda: fd.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("game", type=Path, help="decrypted PS4 dump folder")
    p.add_argument("-o", "--out", default=None, help="output dir (default: game dir)")
    p.add_argument("--exe", default="eboot.bin",
                   help="u1 default; u2 = big2-ps4_Shipping.elf; u3 = big3-ps4_Shipping.elf")
    args = p.parse_args()

    game = args.game.resolve()
    if not (game / args.exe).exists():
        sys.exit(f"not found: {game / args.exe}")

    out = (args.out or game).resolve()
    out.mkdir(parents=True, exist_ok=True)
    run_scripts(game, out, args.exe)

    manifest = {}
    for name in ("boot-linked.bin", "patches.bin", "content.bin"):
        f = out / name
        if f.exists():
            manifest[name] = {"bytes": f.stat().st_size, "sha256": sha256(f)}
    manifest["exe"] = args.exe
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print("\nDone. Files ready next to the dump:")
    for name in manifest:
        print("  ", name)
    print("\nCopy this whole folder into the iOS app's Files area (Uncharted folder).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
