#!/usr/bin/env python3
"""Re-derive Medium/High/Loud for every existing UnbunkUtility sound from its
current Low file, so the whole library follows one loudness ladder: each
tier applies --step-db more gain than the one below it (Low -> Medium ->
High -> Loud), through a limiter that keeps every tier's peak at --ceiling
dBFS. Low itself is never touched — it's the anchor, and it already has the
most headroom before clipping.

Reads the sound list straight from BASE_SOUNDS / RACIAL_SOUNDS in Media.lua,
so it stays in sync automatically as sounds are added. Does not touch
Media.lua — no keys are added or removed, only the audio content of
existing Medium/High/Loud files.

Usage:
    python Tools/restandardize_sounds.py --dry-run   # preview first
    python Tools/restandardize_sounds.py
    python Tools/restandardize_sounds.py --only "Died" --only "BL"
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MEDIA_LUA = REPO_ROOT / "Media" / "Media.lua"
SOUNDS_DIR = REPO_ROOT / "Media" / "Sounds"

FFMPEG_FALLBACKS = [
    r"C:\Program Files\ShareX\ffmpeg.exe",
]

BASE_ENTRY_RE = re.compile(r'\{\s*key\s*=\s*"([^"]*)"\s*,\s*file\s*=\s*"([^"]*)"\s*\}')
RACIAL_ENTRY_RE = re.compile(r'\{\s*key\s*=\s*"([^"]*)"\s*,\s*base\s*=\s*"([^"]*)"\s*\}')
STREAM_INFO_RE = re.compile(r"Audio:.*?(\d+) Hz, (mono|stereo).*?(\d+) kb/s")
MEAN_VOLUME_RE = re.compile(r"mean_volume:\s*([-0-9.]+)\s*dB")
MAX_VOLUME_RE = re.compile(r"max_volume:\s*([-0-9.]+)\s*dB")


class SoundToolError(Exception):
    """A per-sound problem that shouldn't abort the rest of the batch."""


def find_ffmpeg(explicit):
    if explicit:
        return explicit
    found = shutil.which("ffmpeg")
    if found:
        return found
    for candidate in FFMPEG_FALLBACKS:
        if Path(candidate).is_file():
            return candidate
    sys.exit("Could not find ffmpeg. Install it, or pass --ffmpeg <path-to-ffmpeg.exe>.")


def load_sound_list():
    text = MEDIA_LUA.read_text(encoding="utf-8", newline="")

    base_match = re.search(r"local BASE_SOUNDS = \{(.*?)\r?\n[ \t]*\}", text, re.DOTALL)
    racial_match = re.search(r"local RACIAL_SOUNDS = \{(.*?)\r?\n[ \t]*\}", text, re.DOTALL)
    if not base_match or not racial_match:
        sys.exit(f"Could not find BASE_SOUNDS/RACIAL_SOUNDS in {MEDIA_LUA}")

    sounds = []
    for key, file in BASE_ENTRY_RE.findall(base_match.group(1)):
        sounds.append({"key": key, "name_for": (lambda v, file=file: f"{file}{v}.mp3")})
    for key, base in RACIAL_ENTRY_RE.findall(racial_match.group(1)):
        sounds.append({"key": key, "name_for": (lambda v, base=base: f"{base} {v}.mp3")})
    return sounds


def probe(ffmpeg, path):
    proc = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    stream = STREAM_INFO_RE.search(proc.stderr)
    mean_vol = MEAN_VOLUME_RE.search(proc.stderr)
    max_vol = MAX_VOLUME_RE.search(proc.stderr)
    if not stream or not mean_vol or not max_vol:
        raise SoundToolError(f"Could not probe {path}:\n{proc.stderr}")
    sample_rate, layout, bitrate = stream.groups()
    return {
        "sample_rate": sample_rate,
        "channels": "1" if layout == "mono" else "2",
        "bitrate": f"{bitrate}k",
        "mean_volume": float(mean_vol.group(1)),
        "max_volume": float(max_vol.group(1)),
    }


def run_ffmpeg(ffmpeg, args, dry_run):
    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"] + args
    if dry_run:
        print("  [dry-run] " + " ".join(f'"{c}"' if " " in c else c for c in cmd))
        return
    subprocess.run(cmd, check=True)


def restandardize_one(ffmpeg, sound, args):
    key, name_for = sound["key"], sound["name_for"]
    low_path = SOUNDS_DIR / "Low" / name_for("Low")
    if not low_path.is_file():
        raise SoundToolError(f"missing Low file: {low_path.relative_to(REPO_ROOT)}")

    info = probe(ffmpeg, low_path)
    ceiling_linear = 10 ** (args.ceiling / 20)
    print(f'\n"{key}" (anchor: {low_path.name}, {info["mean_volume"]:.1f}dB mean / {info["max_volume"]:.1f}dB peak)')

    for n, variant in enumerate(("Medium", "High", "Loud"), start=1):
        gain = n * args.step_db
        out_path = SOUNDS_DIR / variant / name_for(variant)
        # volume applies the nominal step, then alimiter shaves only what
        # would exceed the ceiling — so even a Low anchor with almost no
        # peak headroom still gets progressively louder (more of the clip
        # sits at the ceiling) instead of the gain being wasted or clipping.
        # level=disabled turns off alimiter's auto makeup gain, which would
        # otherwise silently undo the ceiling.
        af = f"volume={gain}dB,alimiter=limit={ceiling_linear:.4f}:attack=5:release=50:level=disabled"
        ffmpeg_args = [
            "-i", str(low_path),
            "-ar", info["sample_rate"], "-ac", info["channels"],
            "-codec:a", "libmp3lame", "-b:a", info["bitrate"],
            "-af", af,
            str(out_path),
        ]
        run_ffmpeg(ffmpeg, ffmpeg_args, args.dry_run)
        result = "" if args.dry_run else _describe_result(ffmpeg, out_path)
        print(f"  {variant:<7} -> {out_path.relative_to(REPO_ROOT)}  (+{gain}dB nominal){result}")


def _describe_result(ffmpeg, path):
    info = probe(ffmpeg, path)
    return f'  -> {info["mean_volume"]:.1f}dB mean / {info["max_volume"]:.1f}dB peak'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--step-db", type=float, default=4.0, help="dB added per tier, Low -> Medium -> High -> Loud (default: 4.0)")
    parser.add_argument("--ceiling", type=float, default=-0.3, help="never boost a tier past this peak dBFS (default: -0.3)")
    parser.add_argument("--only", action="append", help="restrict to these sound keys (repeatable), e.g. --only Died --only BL")
    parser.add_argument("--ffmpeg", help="path to ffmpeg executable (default: auto-detect)")
    parser.add_argument("--dry-run", action="store_true", help="preview without writing any file")
    args = parser.parse_args()

    ffmpeg = find_ffmpeg(args.ffmpeg)
    sounds = load_sound_list()
    if args.only:
        wanted = set(args.only)
        sounds = [s for s in sounds if s["key"] in wanted]
        missing = wanted - {s["key"] for s in sounds}
        if missing:
            sys.exit(f"Unknown --only key(s): {', '.join(sorted(missing))}")

    print(f"Restandardizing {len(sounds)} sound(s), +{args.step_db}dB per tier, ceiling {args.ceiling}dBFS")

    done, failed = [], []
    for sound in sounds:
        try:
            restandardize_one(ffmpeg, sound, args)
            done.append(sound["key"])
        except SoundToolError as e:
            print(f'\n"{sound["key"]}" FAILED: {e}')
            failed.append(sound["key"])
        except subprocess.CalledProcessError as e:
            print(f'\n"{sound["key"]}" FAILED: ffmpeg exited with code {e.returncode}')
            failed.append(sound["key"])

    print(f"\n{len(done)} sound(s) restandardized.")
    if failed:
        print(f"{len(failed)} failed: {', '.join(failed)}")
    if args.dry_run:
        print("\nDry run only — nothing was written.")
    else:
        print('\n/reload in-game to hear the new levels.')


if __name__ == "__main__":
    main()
