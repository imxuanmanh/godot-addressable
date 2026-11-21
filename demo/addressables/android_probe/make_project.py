"""Generate a standalone Android probe project that uses this repository's addon."""

from __future__ import annotations

import argparse
import random
import shutil
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parents[2] / "addons" / "addressables"


def png(path: Path, width: int, height: int, pixel) -> None:
    """Write an RGB PNG; pixel(x, y) returns three bytes for one row via a callback per row."""
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        rows += pixel(y)
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b""))


def vram_import(path: Path) -> None:
    """Request VRAM compression so the PCK must carry per-GPU texture variants."""
    path.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                    '[params]\n\ncompress/mode=2\nmipmaps/generate=false\n', encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path, help="Empty or new project directory")
    args = parser.parse_args()
    out: Path = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        raise SystemExit(f"Refusing to use a non-empty directory: {out}")
    shutil.copytree(ADDON, out / "addons" / "addressables",
                    ignore=shutil.ignore_patterns(".test_work", "tests", "docs", "__pycache__", ".godot"))
    shutil.copytree(HERE / "probe", out / "probe")
    assets = out / "probe" / "assets"
    # Gradient: the pixel at (x, y) is (x, y, 128), so any texture corruption is easy to see.
    png(assets / "hero.png", 256, 256,
        lambda y: b"".join(bytes((x, y, 128)) for x in range(256)))
    vram_import(assets / "hero.png.import")
    # Incompressible noise makes the pack large enough to expose hashing/copy stalls.
    generator = random.Random(7)
    png(assets / "big.png", 2048, 2048, lambda _y: generator.randbytes(2048 * 3))
    vram_import(assets / "big.png.import")
    (out / "project.godot").write_text(
        'config_version=5\n\n[application]\n\nconfig/name="Addressables Probe"\n'
        'run/main_scene="res://probe/main.tscn"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n\n'
        '[display]\n\nwindow/handheld/orientation=1\n\n'
        '[editor_plugins]\n\nenabled=PackedStringArray("res://addons/addressables/plugin.cfg")\n\n'
        '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n'
        'renderer/rendering_method.mobile="gl_compatibility"\n'
        'textures/vram_compression/import_etc2_astc=true\n', encoding="utf-8")
    (out / "export_presets.cfg").write_text(
        '[preset.0]\n\nname="Android Probe"\nplatform="Android"\nrunnable=true\n'
        'export_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\n'
        'export_path="build/addressables_probe.apk"\n\n'
        '[preset.0.options]\n\ngradle_build/use_gradle_build=false\n'
        'architectures/arm64-v8a=true\narchitectures/armeabi-v7a=false\n'
        'package/unique_name="com.example.addressablesprobe"\npackage/name="Addressables Probe"\n'
        'permissions/internet=true\n', encoding="utf-8")
    print(f"Generated {out}")


if __name__ == "__main__":
    main()
