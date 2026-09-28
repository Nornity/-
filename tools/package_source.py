#!/usr/bin/env python3
"""Create an editable Godot project ZIP without engines, caches or local saves."""
import argparse
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOP_FILES = ("project.godot", "export_presets.cfg", "README.md", "LICENSE", "CREDITS.md", ".gitignore")
SOURCE_DIRS = ("scenes", "scripts", "shaders", "assets", "tests", "tools", "docs", "licenses")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "lower-level-godot-source.zip")
    args = parser.parse_args()
    files = [ROOT / name for name in TOP_FILES]
    for directory in SOURCE_DIRS:
        files.extend(sorted(p for p in (ROOT / directory).rglob("*")
                            if p.is_file() and "__pycache__" not in p.parts
                            and p.suffix not in (".pyc", ".log")))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file in files:
            archive.write(file, Path("lower-level-godot") / file.relative_to(ROOT))
    with zipfile.ZipFile(args.output) as archive:
        assert archive.testzip() is None
        assert "lower-level-godot/project.godot" in archive.namelist()
    print(f"{len(files)} source files → {args.output} ({args.output.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
