"""Prepare, build and run the Addressables testbed project (see testbed/README.md).

Commands:
  setup                          link the addon into testbed/ and generate the test textures
  build --platform P --godot G   import, build content for P and export (windows or android)
  run --test T                   run one exported Windows test unattended; exit code 0 means pass
"""

from __future__ import annotations

import argparse
import os
import random
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTBED = ROOT / "testbed"
ADDON = ROOT / "addons" / "addressables"
SKIN_COUNT = 8
PRESETS = {"windows": ("Windows", "build/windows/testbed.exe"),
           "android": ("Android", "build/android/testbed.apk")}


def write_png(path: Path, width: int, height: int, row) -> None:
    """Write an RGB PNG; row(y) returns that row's width * 3 bytes."""
    data = bytearray()
    for y in range(height):
        data.append(0)
        data += row(y)

    def chunk(kind: bytes, payload: bytes) -> bytes:
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(bytes(data), 6)) + chunk(b"IEND", b""))


def write_import(path: Path) -> None:
    """Request VRAM compression so packs carry per-GPU texture variants."""
    path.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                    '[params]\n\ncompress/mode=2\nmipmaps/generate=false\n', encoding="utf-8")


def link_addon() -> None:
    """Link testbed/addons/addressables to the repository addon (junction on Windows)."""
    link = TESTBED / "addons" / "addressables"
    if link.exists():
        if not os.path.samefile(link, ADDON):
            raise SystemExit(f"{link} exists and is not a link to {ADDON}")
        print(f"Addon link already present: {link}")
        return
    link.parent.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(ADDON)], check=True,
                       stdout=subprocess.DEVNULL)
    else:
        link.symlink_to(ADDON, target_is_directory=True)
    print(f"Linked {link} -> {ADDON}")


def generate_assets() -> None:
    """Create the ignored test textures: a gradient, one large pack and one texture per skin."""
    mount = TESTBED / "assets" / "mount"
    skins = TESTBED / "assets" / "skins"
    # Gradient: pixel (x, y) is (x, y, 128), so corruption is easy to see and to assert.
    write_png(mount / "hero.png", 256, 256, lambda y: b"".join(bytes((x, y, 128)) for x in range(256)))
    write_import(mount / "hero.png.import")
    # Noise does not compress, so the pack is large enough to expose hashing and copy stalls.
    noise = random.Random(7)
    write_png(mount / "big.png", 2048, 2048, lambda _y: noise.randbytes(2048 * 3))
    write_import(mount / "big.png.import")
    for index in range(SKIN_COUNT):
        noise = random.Random(100 + index)
        write_png(skins / f"skin_{index}.png", 1024, 1024, lambda _y, n=noise: n.randbytes(1024 * 3))
        write_import(skins / f"skin_{index}.png.import")
    deps = TESTBED / "assets" / "deps"
    for name in "abc":
        noise = random.Random(200 + ord(name))
        write_png(deps / f"bullet_{name}.png", 128, 128, lambda _y, n=noise: n.randbytes(128 * 3))
        write_import(deps / f"bullet_{name}.png.import")
    print("Generated test textures")


def setup(_args) -> int:
    link_addon()
    generate_assets()
    return 0


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    print("+", " ".join(str(part) for part in command), flush=True)
    return subprocess.run([str(part) for part in command], **kwargs)


def build(args) -> int:
    godot = args.godot.resolve(strict=True)
    preset, output = PRESETS[args.platform]
    if not (TESTBED / "addons" / "addressables").exists() or not (TESTBED / "assets" / "mount" / "hero.png").exists():
        raise SystemExit("Run 'python tools/testbed.py setup' first.")
    base = [godot, "--headless", "--path", TESTBED]
    run(base + ["--editor", "--import", "--quit"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = run(base + ["--script", "res://addons/addressables/editor/build_cli.gd", "--",
                         f"res://content_defs/build_{args.platform}.tres"])
    if result.returncode != 0:
        return result.returncode
    out_file = TESTBED / output
    out_file.parent.mkdir(parents=True, exist_ok=True)
    result = run([sys.executable, ADDON / "editor" / "export_cli.py", "--godot", godot, "--project", TESTBED,
                  "--preset", preset, "--output", out_file, "--mode", "debug"])
    if result.returncode != 0:
        return result.returncode
    content = TESTBED / "content" / args.platform
    if args.platform == "windows":
        shutil.copytree(content, out_file.parent / "content", dirs_exist_ok=True)
        print(f"Built {out_file} (content copied next to it)")
    else:
        print(f"Built {out_file}\nServe content: python -m http.server 8000 --directory {content}")
    return 0


def run_test(args) -> int:
    exe = TESTBED / "build" / "windows" / "testbed.console.exe"
    if not exe.is_file():
        raise SystemExit("Build the Windows export first: python tools/testbed.py build --platform windows --godot ...")
    result = run([exe, "--", f"--test={args.test}"], cwd=exe.parent)
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup").set_defaults(handler=setup)
    builder = commands.add_parser("build")
    builder.add_argument("--platform", choices=sorted(PRESETS), required=True)
    builder.add_argument("--godot", required=True, type=Path)
    builder.set_defaults(handler=build)
    runner = commands.add_parser("run")
    runner.add_argument("--test", choices=["mount", "match", "deps"], required=True)
    runner.set_defaults(handler=run_test)
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
