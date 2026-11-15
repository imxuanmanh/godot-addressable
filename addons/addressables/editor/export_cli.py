"""Checked Godot export: Godot 4.6 can return zero even after an export error."""

# Tooling only: does not build content, upload files or remove old output.
import argparse
import subprocess
import sys
from pathlib import Path


# Fail CI on an engine error or ERROR log even when native export returns zero.
def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--preset", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mode", choices=["pack", "debug", "release"], default="pack")
    args = parser.parse_args()
    godot = args.godot.resolve(strict=True)
    if godot.name.endswith("_console.exe"):
        primary = godot.with_name(godot.name.replace("_console.exe", ".exe"))
        if primary.is_file():
            godot = primary
    result = subprocess.run(
        [str(godot), "--headless", "--disable-crash-handler", "--path", str(args.project.resolve()),
         "--editor", "--export-" + args.mode, args.preset, str(args.output.resolve())],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = result.stdout + result.stderr
    print(output, end="")
    return 1 if result.returncode != 0 or "ERROR:" in output else 0


if __name__ == "__main__":
    sys.exit(main())
