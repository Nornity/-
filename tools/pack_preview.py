#!/usr/bin/env python3
"""Pack raw resources for a local Godot Web preview (no editor cache required).

The game loads PNG/WAV/TTF data explicitly, so preview and editor use the same
assets. This is a development helper, not a replacement for Godot's official
export workflow; use export_presets.cfg for shipping builds.

Usage: python3 tools/pack_preview.py --template /path/to/web/export
The template directory must contain index.js and index.wasm from Godot 4.5+.
"""
import argparse
import hashlib
import shutil
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build_pack(destination: Path) -> None:
    files = [ROOT / name for name in ("project.godot", "LICENSE", "CREDITS.md")]
    for folder in ("scripts", "scenes", "shaders", "assets", "tests", "licenses"):
        files += sorted(
            p for p in (ROOT / folder).rglob("*")
            if p.is_file() and p.suffix not in (".import", ".uid", ".pyc")
        )
    entries = []
    for p in files:
        name = ("res://" + p.relative_to(ROOT).as_posix()).encode()
        name += b"\0" * (-len(name) % 4)
        data = p.read_bytes()
        entries.append((name, data))
    entries.append((b"res://.godot/global_script_class_cache.cfg", b"list=Array[Dictionary]([])\n"))
    header_size = 100
    directory_size = sum(4 + len(name) + 8 + 8 + 16 + 4 for name, _ in entries)
    base = header_size + directory_size
    base += -base % 16
    header = struct.pack("<IIIIIIQ", 0x43504447, 2, 4, 5, 0, 0, base)
    header += bytes(64) + struct.pack("<I", len(entries))
    directory = bytearray()
    payload = bytearray()
    for name, data in entries:
        directory += struct.pack("<I", len(name)) + name
        directory += struct.pack("<QQ", len(payload), len(data))
        directory += hashlib.md5(data).digest() + struct.pack("<I", 0)
        payload += data
        payload += bytes(-len(payload) % 16)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(header + directory + bytes(base - len(header + directory)) + payload)
    print(f"Packed {len(entries)} resources → {destination} ({destination.stat().st_size:,} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path)
    args = parser.parse_args()
    output = ROOT / ".web"
    output.mkdir(exist_ok=True)
    if args.template:
        for name in ("index.js", "index.wasm", "index.audio.worklet.js", "index.audio.position.worklet.js"):
            source = args.template / name
            if source.exists():
                shutil.copyfile(source, output / name)
    shutil.copyfile(ROOT / "tools" / "web_shell.html", output / "index.html")
    build_pack(output / "index.pck")


if __name__ == "__main__":
    main()
