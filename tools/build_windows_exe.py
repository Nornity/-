#!/usr/bin/env python3
"""Build a self-contained, offline Windows .exe launcher for the real Godot Web game.

The executable is an auto-opening browser launcher for the already-tested
Godot WebAssembly runtime, not a native Windows Godot export. It uses Node SEA,
keeps all payloads in the one .exe, and needs an installed WebGL2 browser.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
NODE_VERSION = "22.22.3"  # Also matches the host Node version used for SEA blob creation.
NODE_PACKAGE_INTEGRITY = "sha512-Ld8tHv/A+A+t6WU7yINvd32xQ/5uU8aOWK8qjzaKSSDWQxCVqegCOXjszs5JU/DnJZObDcuMkOE99SwRQbRX0g=="
POSTJECT_VERSION = "1.0.0-alpha.6"
SEA_FUSE = "NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"
ASSETS = {
    "index.html": ".web/index.html",
    "index.js": ".web/index.js",
    "index.wasm": ".web/index.wasm",
    "index.pck": ".web/index.pck",
    "index.audio.worklet.js": ".web/index.audio.worklet.js",
    "index.audio.position.worklet.js": ".web/index.audio.position.worklet.js",
    "LICENSE": "LICENSE",
    "CREDITS.md": "CREDITS.md",
    "assets/icon.svg": "assets/icon.svg",
    "assets/fonts/IBMPlexMono-OFL.txt": "assets/fonts/IBMPlexMono-OFL.txt",
    "assets/fonts/Oswald-OFL.txt": "assets/fonts/Oswald-OFL.txt",
    "licenses/Godot-MIT.txt": "licenses/Godot-MIT.txt",
    "licenses/Godot-COPYRIGHT.txt": "licenses/Godot-COPYRIGHT.txt",
    "licenses/Node-MIT.txt": "licenses/Node-MIT.txt",
    "licenses/Preview-package-MIT.txt": "licenses/Preview-package-MIT.txt",
}


def run(args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "windows" / "Нижний уровень.exe")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    missing = [path for path in ASSETS.values() if not (ROOT / path).is_file()]
    if missing:
        parser.error("Missing bundled runtime files; build the Godot Web preview first: " + ", ".join(missing))
    host_node = shutil.which("node")
    if not host_node:
        parser.error("Node.js 22.22.3 is needed to generate the SEA resource blob.")
    host_version = subprocess.check_output([host_node, "--version"], text=True).strip()
    if host_version != "v" + NODE_VERSION:
        parser.error(f"Use Node.js v{NODE_VERSION} to generate a matching SEA blob (found {host_version}).")
    npm = shutil.which("npm")
    if not npm:
        parser.error("npm is needed to retrieve the pinned Node.js Windows runtime and postject.")

    with tempfile.TemporaryDirectory(prefix="lower-level-win-exe-") as temp_name:
        temp = Path(temp_name)
        package_dir = temp / "npm"
        package_dir.mkdir()
        run([npm, "pack", f"node-win-x64@{NODE_VERSION}", "--pack-destination", str(package_dir)])
        tarball = next(package_dir.glob("node-win-x64-*.tgz"))
        with tarfile.open(tarball, "r:gz") as bundle:
            package = json.loads(bundle.extractfile("package/package.json").read())
            integrity = package.get("_integrity", "")
            exe_member = bundle.getmember("package/bin/node.exe")
            original_exe = temp / "node-win64.exe"
            with bundle.extractfile(exe_member) as source, original_exe.open("wb") as dest:
                shutil.copyfileobj(source, dest)
        if package.get("version") != NODE_VERSION:
            raise RuntimeError("Unexpected node-win-x64 package version.")
        digest = base64.b64decode(NODE_PACKAGE_INTEGRITY.split("-", 1)[1])
        actual = hashlib.sha512(tarball.read_bytes()).digest()
        if actual != digest:
            raise RuntimeError("The pinned node-win-x64 npm package failed its SHA-512 integrity check.")
        del integrity

        postject_dir = temp / "postject"
        run([npm, "install", "--prefix", str(postject_dir), "--no-save", "--ignore-scripts",
             f"postject@{POSTJECT_VERSION}"])
        config_path = temp / "sea-config.json"
        blob_path = temp / "sea-prep.blob"
        config = {
            "main": str((ROOT / "tools/windows_launcher.js").resolve()),
            "output": str(blob_path),
            "disableExperimentalSEAWarning": True,
            "useSnapshot": False,
            "useCodeCache": False,
            "assets": {name: str((ROOT / source).resolve()) for name, source in ASSETS.items()},
        }
        config_path.write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")
        run([host_node, "--experimental-sea-config", str(config_path)])
        postject = postject_dir / "node_modules/postject/dist/cli.js"
        run([host_node, str(postject), str(original_exe), "NODE_SEA_BLOB", str(blob_path),
             "--sentinel-fuse", SEA_FUSE])

        # Suppress the otherwise empty console window when the user double-clicks.
        # This changes only the PE subsystem field; Node still launches Edge normally.
        with original_exe.open("r+b") as executable:
            executable.seek(0x3C)
            pe_offset = struct.unpack("<I", executable.read(4))[0]
            executable.seek(pe_offset)
            if executable.read(4) != b"PE\0\0":
                raise RuntimeError("The Windows runtime does not have a valid PE header.")
            executable.seek(pe_offset + 24)
            optional_magic = struct.unpack("<H", executable.read(2))[0]
            if optional_magic != 0x20B:
                raise RuntimeError("Expected a 64-bit Windows PE executable.")
            executable.seek(pe_offset + 24 + 68)
            subsystem = struct.unpack("<H", executable.read(2))[0]
            if subsystem not in (2, 3):
                raise RuntimeError(f"Unexpected PE subsystem: {subsystem}.")
            executable.seek(pe_offset + 24 + 68)
            executable.write(struct.pack("<H", 2))  # IMAGE_SUBSYSTEM_WINDOWS_GUI

        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original_exe, output)
        print(f"Windows launcher: {output} ({output.stat().st_size:,} bytes)", flush=True)
        print("Contains the actual Godot 4.6 WebAssembly game; double-click opens the default WebGL2 browser.", flush=True)


if __name__ == "__main__":
    main()
