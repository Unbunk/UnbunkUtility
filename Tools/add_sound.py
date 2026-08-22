#!/usr/bin/env python3
"""Add new UnbunkUtility sounds: generate the High/Medium/Low/Loud variants
with ffmpeg, then register each sound in Media.lua.

Two ways to use it:

  1. Drop-folder mode (what "Add New Sounds.bat" runs):
         python Tools/add_sound.py --drop-folder Media/NewSounds
     Processes every *.mp3 sitting in that folder — the filename (minus
     extension) becomes the sound's display name, e.g. "Wipe Alert.mp3" ->
     "UnbunkUtility: Wipe Alert (High/Medium/Low/Loud)". Each file is deleted
     from the drop folder once it has been turned into variants and
     registered. Files that fail or are already registered are left in
     place so nothing is silently lost.

  2. Single-file mode:
         python Tools/add_sound.py path/to/source.mp3 --key "Wipe Alert"

Run with --dry-run first to preview the ffmpeg commands and the Media.lua
diff without touching any file.
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
DEFAULT_DROP_FOLDER = REPO_ROOT / "Media" / "NewSounds"
VARIANTS = ["High", "Medium", "Low", "Loud"]

FFMPEG_FALLBACKS = [
    r"C:\Program Files\ShareX\ffmpeg.exe",
]

ENTRY_RE = re.compile(r'\{\s*key\s*=\s*"([^"]*)"\s*,\s*file\s*=\s*"([^"]*)"\s*\}')
BLOCK_RE = re.compile(
    r'(local BASE_SOUNDS = \{\r?\n)(.*?)(\r?\n[ \t]*\}\r?\n)', re.DOTALL
)


class SoundToolError(Exception):
    """A per-sound problem that shouldn't abort the rest of a batch."""


def find_ffmpeg(explicit):
    if explicit:
        return explicit
    found = shutil.which("ffmpeg")
    if found:
        return found
    for candidate in FFMPEG_FALLBACKS:
        if Path(candidate).is_file():
            return candidate
    sys.exit(
        "Could not find ffmpeg. Install it, or pass --ffmpeg <path-to-ffmpeg.exe>."
    )


def run_ffmpeg(ffmpeg, args, dry_run):
    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"] + args
    if dry_run:
        print("[dry-run] " + " ".join(f'"{c}"' if " " in c else c for c in cmd))
        return
    subprocess.run(cmd, check=True)


def detect_max_volume(ffmpeg, source):
    proc = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", str(source), "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    match = re.search(r"max_volume:\s*([-0-9.]+)\s*dB", proc.stderr)
    if not match:
        raise SoundToolError(f"Could not read max_volume from ffmpeg output:\n{proc.stderr}")
    return float(match.group(1))


def build_variants(ffmpeg, source, file_stem, args):
    common = ["-ac", "1", "-ar", str(args.sample_rate), "-codec:a", "libmp3lame", "-b:a", args.bitrate]

    loud_gain = args.loud_ceiling - detect_max_volume(ffmpeg, source)

    plan = {
        "High": None,
        "Medium": f"volume={args.medium_db}dB",
        "Low": f"volume={args.low_db}dB",
        "Loud": f"volume={loud_gain:.2f}dB",
    }

    for variant, af in plan.items():
        out_dir = SOUNDS_DIR / variant
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"{file_stem}{variant}.mp3"
        if out_path.exists() and not args.force and not args.dry_run:
            raise SoundToolError(f"{out_path} already exists. Use --force to overwrite.")
        ffmpeg_args = ["-i", str(source)] + common
        if af:
            ffmpeg_args += ["-af", af]
        ffmpeg_args.append(str(out_path))
        run_ffmpeg(ffmpeg, ffmpeg_args, args.dry_run)
        print(f"  {variant:<7} -> {out_path.relative_to(REPO_ROOT)}"
              + (f"  ({af})" if af else "  (source level)"))


def registered_keys():
    text = MEDIA_LUA.read_text(encoding="utf-8", newline="")
    block_match = BLOCK_RE.search(text)
    if not block_match:
        raise SoundToolError(f"Could not find the BASE_SOUNDS table in {MEDIA_LUA}")
    return {k for k, _ in ENTRY_RE.findall(block_match.group(2))}


def update_media_lua(key, file_stem, dry_run, force):
    text = MEDIA_LUA.read_text(encoding="utf-8", newline="")
    block_match = BLOCK_RE.search(text)
    if not block_match:
        raise SoundToolError(f"Could not find the BASE_SOUNDS table in {MEDIA_LUA}")

    body = block_match.group(2)
    entries = ENTRY_RE.findall(body)  # preserves the file's existing order
    if any(k == key for k, _ in entries):
        if not force:
            raise SoundToolError(f'"{key}" is already registered in BASE_SOUNDS. Use --force to re-add.')
        entries = [(k, f) for k, f in entries if k != key]

    # Insert alphabetically relative to neighbours, but never reorder the
    # existing entries — the table is grouped by sound family (e.g. all the
    # BL/Bloodlust ones together), not strictly alphabetical, and a full
    # re-sort would shuffle unrelated lines on every run.
    insert_at = len(entries)
    for i, (k, _) in enumerate(entries):
        if k.lower() > key.lower():
            insert_at = i
            break
    entries.insert(insert_at, (key, file_stem))

    key_col_width = max(len(f'"{k}",') for k, _ in entries) + 1
    lines = [
        f'            {{ key = {(chr(34) + k + chr(34) + ",").ljust(key_col_width)}file = "{f}" }},'
        for k, f in entries
    ]
    new_body = "\r\n".join(lines)

    new_text = text[: block_match.start(2)] + new_body + text[block_match.end(2):]

    if dry_run:
        print(f"[dry-run] would insert into {MEDIA_LUA.relative_to(REPO_ROOT)}:")
        print(f'            {{ key = "{key}", file = "{file_stem}" }}')
        return

    MEDIA_LUA.write_text(new_text, encoding="utf-8", newline="")
    print(f"Updated {MEDIA_LUA.relative_to(REPO_ROOT)}")


def derive_key_and_file(name_without_ext):
    key = re.sub(r"\s+", " ", name_without_ext).strip()
    file_stem = re.sub(r"\s+", "", key)
    if not re.fullmatch(r"[A-Za-z0-9]+", file_stem):
        raise SoundToolError(
            f'"{name_without_ext}" must reduce to letters/numbers only once spaces are '
            f'stripped (got "{file_stem}"). Rename the file and drop it again.'
        )
    return key, file_stem


def process_one(ffmpeg, source, key, file_stem, args):
    print(f'\nProcessing "{source.name}" -> "{key}" ({file_stem})')
    build_variants(ffmpeg, source, file_stem, args)
    update_media_lua(key, file_stem, args.dry_run, args.force)


def run_drop_folder(args):
    folder = args.drop_folder
    folder.mkdir(parents=True, exist_ok=True)
    mp3s = sorted(folder.glob("*.mp3"))
    if not mp3s:
        print(f"No .mp3 files found in {folder}")
        return

    ffmpeg = find_ffmpeg(args.ffmpeg)
    added, skipped, failed = [], [], []

    for source in mp3s:
        try:
            key, file_stem = derive_key_and_file(source.stem)
            if key in registered_keys() and not args.force:
                print(f'\nSkipping "{source.name}": "{key}" is already registered. '
                      f'Rename the file (or re-run with --force) to replace it.')
                skipped.append(source.name)
                continue
            process_one(ffmpeg, source, key, file_stem, args)
            if not args.dry_run:
                source.unlink()
                print(f"  removed {source.name} from the drop folder")
            added.append(key)
        except SoundToolError as e:
            print(f'\n"{source.name}" FAILED: {e}')
            failed.append(source.name)
        except subprocess.CalledProcessError as e:
            print(f'\n"{source.name}" FAILED: ffmpeg exited with code {e.returncode}')
            failed.append(source.name)

    print(f"\n{len(added)} sound(s) added: {', '.join(added) if added else '-'}")
    if skipped:
        print(f"{len(skipped)} skipped (left in the drop folder): {', '.join(skipped)}")
    if failed:
        print(f"{len(failed)} failed (left in the drop folder): {', '.join(failed)}")
    if args.dry_run:
        print("\nDry run only — nothing was written or deleted.")


def run_single_file(args):
    if not args.source.is_file():
        raise SoundToolError(f"Source file not found: {args.source}")

    file_stem = args.file or re.sub(r"\s+", "", args.key)
    if not re.fullmatch(r"[A-Za-z0-9]+", file_stem):
        raise SoundToolError(f'File stem "{file_stem}" must be alphanumeric only. Pass --file to override.')

    ffmpeg = find_ffmpeg(args.ffmpeg)
    process_one(ffmpeg, args.source, args.key, file_stem, args)

    if args.dry_run:
        print("\nDry run only — nothing was written. Re-run without --dry-run to apply.")
    else:
        print(f'\nDone. /reload in-game and look for "UnbunkUtility: {args.key} (High/Medium/Low/Loud)" in SharedMedia.')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, nargs="?", help="source audio file (single-file mode)")
    parser.add_argument("--key", help='LSM display key, e.g. "Wipe Alert" (single-file mode)')
    parser.add_argument("--file", help="filename stem used on disk (default: --key with spaces stripped)")
    parser.add_argument("--drop-folder", type=Path, nargs="?", const=DEFAULT_DROP_FOLDER,
                         help=f"process every *.mp3 in this folder instead of a single file "
                              f"(default when flag given with no path: {DEFAULT_DROP_FOLDER})")
    parser.add_argument("--medium-db", type=float, default=-3.5, help="gain applied for the Medium tier (default: -3.5)")
    parser.add_argument("--low-db", type=float, default=-8.0, help="gain applied for the Low tier (default: -8.0)")
    parser.add_argument("--loud-ceiling", type=float, default=-0.3, help="target peak dBFS for the Loud tier (default: -0.3)")
    parser.add_argument("--bitrate", default="60k", help="mp3 bitrate for all 4 outputs (default: 60k)")
    parser.add_argument("--sample-rate", type=int, default=24000, help="output sample rate in Hz (default: 24000)")
    parser.add_argument("--ffmpeg", help="path to ffmpeg executable (default: auto-detect)")
    parser.add_argument("--dry-run", action="store_true", help="preview without writing/deleting any file")
    parser.add_argument("--force", action="store_true", help="overwrite existing output files / Media.lua entries")
    args = parser.parse_args()

    try:
        if args.drop_folder:
            run_drop_folder(args)
        else:
            if not args.source or not args.key:
                parser.error("source and --key are required unless --drop-folder is given")
            run_single_file(args)
    except SoundToolError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
