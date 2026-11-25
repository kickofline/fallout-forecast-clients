#!/usr/bin/env python3
"""Mirror the repo's exported assets/ into clients/car/assets/ (Godot res://assets/).

The Godot 3 project root is clients/car/, and Godot can only import files under
it, so the exporter output is copied (not committed twice: clients/car/assets is
gitignored). Only changed files are copied; files that disappeared upstream
are removed (their .import side files too).

    python tools/sync_assets.py [--clean]

Short Ogg Vorbis SFX are also decoded to 16-bit PCM WAV next to the copy
(<name>.wav, only under clients/car/assets) when the optional `soundfile`
package is installed (pip install soundfile). Godot 3 mixes WAV samples
without a per-voice Vorbis decoder, which matters on the car's 2-core CPU;
core/sound.gd prefers the .wav and falls back to the .ogg.
"""
import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets")
DST = os.path.join(ROOT, "clients", "car", "assets")
SKIP_EXT = {".import", ".webp"}  # Godot 3 export doesn't need the webp copies
# Only files of these types are ever deleted from clients/car/assets; anything
# Godot generates next to them (.import, extracted materials) is left alone.
DECODE_OGG_DIRS = {os.path.join("audio", "sfx")}
OWNED_EXT = {".glb", ".gltf", ".json", ".png", ".jpg", ".wav", ".ogg", ".ttf", ".otf", ".txt", ".md"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clean", action="store_true", help="delete clients/car/assets first")
    args = ap.parse_args()
    if not os.path.isdir(SRC):
        print("no assets/ directory; the client will use placeholders")
        return 0
    if args.clean and os.path.isdir(DST):
        shutil.rmtree(DST)
    copied = kept = removed = 0
    wanted = set()
    for base, _dirs, files in os.walk(SRC):
        rel = os.path.relpath(base, SRC)
        for name in files:
            if os.path.splitext(name)[1].lower() in SKIP_EXT:
                continue
            src = os.path.join(base, name)
            dst = os.path.normpath(os.path.join(DST, rel, name))
            wanted.add(dst)
            st = os.stat(src)
            if os.path.exists(dst):
                dt = os.stat(dst)
                if dt.st_size == st.st_size and int(dt.st_mtime) >= int(st.st_mtime):
                    kept += 1
                    continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            copied += 1
    decoded = _decode_oggs(wanted)
    for base, _dirs, files in os.walk(DST):
        for name in files:
            path = os.path.normpath(os.path.join(base, name))
            if path.endswith(".import"):
                if not os.path.exists(path[:-7]):
                    os.remove(path)
                    removed += 1
                continue
            if os.path.splitext(name)[1].lower() in OWNED_EXT and path not in wanted:
                os.remove(path)
                removed += 1
    print("assets: %d copied, %d unchanged, %d removed, %s -> %s" % (copied, kept, removed, decoded, DST))
    return 0


def _decode_oggs(wanted):
    """Write <name>.wav beside each synced SFX .ogg (adds them to `wanted`)."""
    try:
        import soundfile
    except ImportError:
        return "ogg->wav skipped (pip install soundfile)"
    n = 0
    for rel_dir in DECODE_OGG_DIRS:
        base = os.path.join(DST, rel_dir)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if not name.lower().endswith(".ogg"):
                continue
            src = os.path.join(base, name)
            dst = os.path.normpath(os.path.join(base, name[:-4] + ".wav"))
            if os.path.exists(os.path.join(SRC, rel_dir, name[:-4] + ".wav")):
                continue  # a real WAV with that name exists upstream; never shadow it
            wanted.add(dst)
            if os.path.exists(dst) and os.stat(dst).st_mtime >= os.stat(src).st_mtime:
                continue
            data, rate = soundfile.read(src, dtype="int16")
            soundfile.write(dst, data, rate, subtype="PCM_16")
            n += 1
    return "%d ogg->wav decoded" % n


if __name__ == "__main__":
    sys.exit(main())
