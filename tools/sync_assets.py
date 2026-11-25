#!/usr/bin/env python3
"""Mirror the repo's exported assets/ into client/assets/ (Godot res://assets/).

The Godot 3 project root is client/, and Godot can only import files under
it, so the exporter output is copied (not committed twice: client/assets is
gitignored). Only changed files are copied; files that disappeared upstream
are removed (their .import side files too).

    python tools/sync_assets.py [--clean]
"""
import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets")
DST = os.path.join(ROOT, "client", "assets")
SKIP_EXT = {".import", ".webp"}  # Godot 3 export doesn't need the webp copies


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clean", action="store_true", help="delete client/assets first")
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
    for base, _dirs, files in os.walk(DST):
        for name in files:
            path = os.path.normpath(os.path.join(base, name))
            source = path[:-7] if path.endswith(".import") else path
            if source not in wanted:
                os.remove(path)
                removed += 1
    print("assets: %d copied, %d unchanged, %d removed -> %s" % (copied, kept, removed, DST))
    return 0


if __name__ == "__main__":
    sys.exit(main())
