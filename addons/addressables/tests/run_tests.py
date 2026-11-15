"""Isolated Godot integration tests; no third-party Python packages or client changes.

python tests/run_tests.py --godot /path/to/godot_console.exe
"""

from __future__ import annotations
# All generated projects, profiles, caches and reports live below WORK.
# A full-pass report is written only after every required stage succeeds.

import argparse
import functools
import hashlib
import http.server
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path


ADDON = Path(__file__).resolve().parents[1]
WORK = ADDON / ".test_work"
RESULTS: list[dict] = []


# Check logs and markers as well as native exit codes.
def run(godot: Path, project: Path, *args: str, marker: str = "", timeout: int = 90,
        expected_error: str = "", allow_resource_errors: bool = False) -> str:
    command = [str(godot), "--headless", "--disable-crash-handler", "--path", str(project), *args]
    environment = os.environ.copy()
    for variable in ["APPDATA", "LOCALAPPDATA"]:
        directory = WORK / "profile" / variable
        directory.mkdir(parents=True, exist_ok=True)
        environment[variable] = str(directory)
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=timeout, env=environment)
    except subprocess.TimeoutExpired as exception:
        output = (exception.stdout or b"") + (exception.stderr or b"")
        raise RuntimeError(f"Timed out: {' '.join(command)}\n{output.decode('utf-8', errors='replace')}") from exception
    output = result.stdout + result.stderr
    (WORK / "logs").mkdir(exist_ok=True)
    name = args[args.index("--script") + 1].split("/")[-1] if "--script" in args else "editor"
    if "--" in args:
        name += "-" + args[-1].split(":")[0].replace("/", "_")
    sequence = len(RESULTS) + 1
    (WORK / "logs" / f"{sequence:02d}-{project.name}-{name}.log").write_text(output, encoding="utf-8")
    if expected_error:
        if expected_error not in output:
            raise RuntimeError("Expected the export to report stale content:\n" + output)
        print("PASS stale export detection", flush=True)
        RESULTS.append({"stage": "stale export detection", "status": "passed"})
        return output
    if (result.returncode or "SCRIPT ERROR:" in output or ("ERROR:" in output and not allow_resource_errors)
            or "CHECK FAILED:" in output
            or (marker and marker not in output)):
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{output}")
    detail = next((line for line in output.splitlines() if marker and line.startswith(marker)), "")
    print(detail or f"PASS {project.name}: {' '.join(args)}", flush=True)
    RESULTS.append({"stage": detail or " ".join(args), "status": "passed"})
    return output


# Copy the addon into an isolated fixture project; never edit an application project.
def make_project(path: Path, enabled: bool = False, with_dotnet: bool = False) -> None:
    path.mkdir(parents=True)
    target = path / "addons" / ADDON.name
    ignored = [".test_work", ".test_tools", "__pycache__"]
    if not with_dotnet:
        ignored.append("dotnet")
    shutil.copytree(ADDON, target, ignore=shutil.ignore_patterns(*ignored))
    config = ('config_version=5\n[application]\nconfig/name="AddressablesTests"\n'
              'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="AddressablesTests"\n'
              '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    if enabled:
        config += '[editor_plugins]\nenabled=PackedStringArray("res://addons/addressables/plugin.cfg")\n'
    (path / "project.godot").write_text(config, encoding="utf-8")


# Distinct prefabs share one texture and one base script to exercise dependency packing.
def fixtures(project: Path) -> None:
    directory = project / "fixtures"
    directory.mkdir()
    (project / "base_asset.gd").write_text('extends Node2D\nvar asset_tag := "base code"\n', encoding="utf-8")
    for name, color in [("shared", "#00ff00"), ("a", "#ff0000"), ("b", "#0000ff")]:
        (directory / f"{name}.svg").write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
            f'<rect width="8" height="8" fill="{color}"/></svg>', encoding="utf-8")
    for asset in ["a", "b"]:
        (directory / f"{asset}.tscn").write_text(f'''[gd_scene load_steps=4 format=3]
[ext_resource type="Texture2D" path="res://fixtures/{asset}.svg" id="1"]
[ext_resource type="Texture2D" path="res://fixtures/shared.svg" id="2"]
[ext_resource type="Script" path="res://base_asset.gd" id="3"]
[node name="Asset{asset.upper()}" type="Node2D"]
script = ExtResource("3")
[node name="Body" type="Sprite2D" parent="."]
texture = ExtResource("1")
[node name="Shared" type="Sprite2D" parent="."]
texture = ExtResource("2")
''', encoding="utf-8")
    (project / "host.gd").write_text(
        '@tool\nextends Node\n@export var asset: AddressableReference\n', encoding="utf-8")


# Compile/run the bridge independently with the matching Godot.NET SDK and .NET 8.
def test_dotnet(godot: Path, catalog: dict) -> None:
    version = subprocess.run([str(godot), "--version"], capture_output=True,
                             text=True, check=True, timeout=15).stdout.strip().split(".")[:3]
    assert len(version) == 3 and all(part.isdigit() for part in version), "Expected a numeric engine version"
    sdk_version = ".".join(version)
    project = WORK / "bridge"
    make_project(project, enabled=True, with_dotnet=True)
    fixtures(project)
    (project / "catalog.json").write_text(json.dumps(catalog), encoding="utf-8")
    shutil.copyfile(ADDON / "tests" / "BridgeSuite.cs.txt", project / "BridgeSuite.cs")
    (project / "BridgeTests.csproj").write_text(
        f'<Project Sdk="Godot.NET.Sdk/{sdk_version}"><PropertyGroup>'
        '<TargetFramework>net8.0</TargetFramework><Nullable>enable</Nullable>'
        '<EnableDynamicLoading>true</EnableDynamicLoading>'
        '</PropertyGroup></Project>', encoding="utf-8")
    (project / "global.json").write_text(
        '{"sdk":{"version":"8.0.100","rollForward":"latestFeature"}}', encoding="utf-8")
    offline_packages = godot.parent / "GodotSharp" / "Tools" / "nupkgs"
    if offline_packages.is_dir():
        (project / "NuGet.Config").write_text(
            '<?xml version="1.0"?><configuration><packageSources><clear/>'
            f'<add key="GodotOffline" value="{offline_packages.as_posix()}"/>'
            '</packageSources></configuration>', encoding="utf-8")
    config = (project / "project.godot").read_text(encoding="utf-8")
    config = config.replace('[application]\n', '[application]\nrun/main_scene="res://bridge.tscn"\n')
    config += '[dotnet]\nproject/assembly_name="BridgeTests"\n'
    (project / "project.godot").write_text(config, encoding="utf-8")
    (project / "bridge.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://BridgeSuite.cs" id="1"]\n'
        '[node name="BridgeSuite" type="Node"]\nscript = ExtResource("1")\n', encoding="utf-8")
    environment = os.environ.copy()
    environment.update({"DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1", "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
                        "DOTNET_GENERATE_ASPNET_CERTIFICATE": "false", "DOTNET_ADD_GLOBAL_TOOLS_TO_PATH": "false",
                        "DOTNET_CLI_HOME": str(WORK / "profile" / "dotnet"),
                        "NUGET_PACKAGES": str(WORK / "profile" / "nuget"),
                        "APPDATA": str(WORK / "profile" / "APPDATA"),
                        "LOCALAPPDATA": str(WORK / "profile" / "LOCALAPPDATA")})
    result = subprocess.run(["dotnet", "build", str(project / "BridgeTests.csproj"),
                             "--ignore-failed-sources", "-p:NuGetAudit=false", "--nologo"],
                            capture_output=True, text=True, encoding="utf-8", errors="replace",
                            timeout=120, env=environment, cwd=project)
    output = result.stdout + result.stderr
    (WORK / "logs" / "dotnet-build.log").write_text(output, encoding="utf-8")
    if result.returncode:
        raise RuntimeError("C# bridge compilation failed:\n" + output)
    print("PASS C# bridge compilation", flush=True)
    run(godot, project, "--editor", "--import", "--quit", timeout=120)
    run(godot, project, marker="PASS C# bridge suite")


# Build first, test clean clients next, and always stop the loopback server.
def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--stage-engine", action="store_true")
    args = parser.parse_args()
    godot = args.godot.resolve(strict=True)
    if godot.name.endswith("_console.exe"):
        primary = godot.with_name(godot.name.replace("_console.exe", ".exe"))
        if primary.is_file():
            godot = primary
    # Every deletion is restricted to this plugin's generated test directory.
    assert WORK.resolve().parent == ADDON.resolve() and WORK.name == ".test_work"
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir()
    (WORK / ".gdignore").write_text("", encoding="utf-8")
    if args.stage_engine:
        staged = WORK / "engine"
        staged.mkdir()
        shutil.copyfile(godot, staged / godot.name)
        assemblies = godot.parent / "GodotSharp"
        if assemblies.is_dir():
            shutil.copytree(assemblies, staged / "GodotSharp")
        godot = staged / godot.name
    source = WORK / "source"
    make_project(source, enabled=True)
    fixtures(source)
    driver = source / "addons" / ADDON.name / "editor" / "test_driver"
    driver.mkdir()
    (driver / "plugin.cfg").write_text(
        '[plugin]\nname="AddressablesTestDriver"\ndescription="Isolated editor test driver"\n'
        'author="Tests"\nversion="1"\nscript="plugin.gd"\n', encoding="utf-8")
    (driver / "plugin.gd").write_text(
        '@tool\nextends EditorPlugin\n'
        'func _enter_tree() -> void:\n'
        '\tif "--sa-editor-suite" in OS.get_cmdline_user_args():\n\t\t_run.call_deferred()\n'
        'func _run() -> void:\n'
        '\tvar suite = load("res://addons/addressables/tests/editor_suite.gd").new()\n'
        '\tawait suite.run(get_tree())\n', encoding="utf-8")
    config = (source / "project.godot").read_text(encoding="utf-8")
    config = config.replace('"res://addons/addressables/plugin.cfg")',
                            '"res://addons/addressables/plugin.cfg", '
                            '"res://addons/addressables/editor/test_driver/plugin.cfg")')
    (source / "project.godot").write_text(config, encoding="utf-8")
    run(godot, source, "--editor", "--import", "--quit", timeout=120)
    if args.prepare_only:
        return
    run(godot, source, "--editor", "--", "--sa-editor-suite",
        marker="PASS editor/build suite")
    run(godot, source, "--script", "res://addons/addressables/tests/runtime_suite.gd",
        marker="PASS local runtime suite")
    run(godot, source, "--script", "res://addons/addressables/tests/resource_failure_suite.gd",
        marker="PASS failed resource retry suite", allow_resource_errors=True)
    catalog = json.loads((source / "content" / "catalog.json").read_text(encoding="utf-8"))
    remote = WORK / "remote"
    make_project(remote)
    shutil.copyfile(source / "base_asset.gd", remote / "base_asset.gd")
    (remote / "catalog.json").write_text(json.dumps(catalog), encoding="utf-8")
    run(godot, remote, "--editor", "--import", "--quit", timeout=120)

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, _format: str, *values: object) -> None:
            pass

        def do_GET(self) -> None:
            if self.path.startswith("/redirect/"):
                self.send_response(302)
                self.send_header("Location", root + "/" + Path(self.path).name)
                self.end_headers()
                return
            if self.path.startswith("/missing/"):
                self.send_error(404)
                return
            if self.path.startswith("/corrupt/"):
                body = b"damaged content"
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path.startswith("/tampered/"):
                body = bytearray((source / "content" / Path(self.path).name).read_bytes())
                body[-1] ^= 1
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path.startswith("/slow/"):
                time.sleep(0.8)
                self.path = self.path.removeprefix("/slow")
            try:
                super().do_GET()
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass

    handler = functools.partial(QuietHandler, directory=str(source / "content"))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        root = f"http://127.0.0.1:{server.server_port}"
        with urllib.request.urlopen(root + "/catalog.json", timeout=5) as response:
            assert json.load(response) == catalog
        run(godot, remote, "--script", "res://addons/addressables/tests/remote_suite.gd",
            "--", str(source / "content"), "local", marker="PASS remote local suite")
        run(godot, remote, "--script", "res://addons/addressables/tests/remote_suite.gd",
            "--", root, "cold", marker="PASS remote cold suite")
        run(godot, remote, "--script", "res://addons/addressables/tests/remote_suite.gd",
            "--", root, "concurrent", marker="PASS remote concurrent suite")
        run(godot, remote, "--script", "res://addons/addressables/tests/remote_suite.gd",
            "--", root, "repair", marker="PASS remote repair suite")
        run(godot, remote, "--script", "res://addons/addressables/tests/remote_suite.gd",
            "--", root, "warm", marker="PASS remote warm suite")
        run(godot, remote, "--script", "res://addons/addressables/tests/remote_suite.gd",
            "--", "http://127.0.0.1:1", "offline", marker="PASS remote offline suite")
        for mode, url in [("missing", root + "/missing"), ("corrupt", root + "/corrupt"),
                          ("tampered", root + "/tampered"), ("insecure", root),
                          ("redirect", root + "/redirect"),
                          ("timeout", root + "/slow"), ("cancel", root + "/slow"),
                          ("shutdown", root + "/slow"), ("collision", root)]:
            run(godot, remote, "--script", "res://addons/addressables/tests/failure_suite.gd",
                "--", url, mode, marker=f"PASS failure {mode} suite")
        export_probe = source / "export_probe.gd"
        shutil.copyfile(ADDON / "tests" / "export_probe.gd", export_probe)
        (source / "export_probe.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n'
            '[ext_resource type="Script" path="res://export_probe.gd" id="1"]\n'
            '[node name="Probe" type="Node"]\nscript = ExtResource("1")\n', encoding="utf-8")
        config = (source / "project.godot").read_text(encoding="utf-8")
        config = config.replace('[application]\n', '[application]\nrun/main_scene="res://export_probe.tscn"\n')
        (source / "project.godot").write_text(config, encoding="utf-8")
        (source / "export_presets.cfg").write_text(
            '[preset.0]\nname="AddressablesTest"\nplatform="Windows Desktop"\n'
            'runnable=true\nexport_filter="all_resources"\ninclude_filter=""\n'
            'exclude_filter=""\nexport_path=""\nscript_export_mode=0\n'
            '[preset.0.options]\nbinary_format/embed_pck=false\n', encoding="utf-8")
        run(godot, source, "--editor", "--import", "--quit", timeout=120)
        base_pack = WORK / "base.pck"
        run(godot, source, "--editor", "--export-pack", "AddressablesTest", str(base_pack), timeout=120)
        packed = WORK / "packed"
        packed.mkdir()
        run(godot, packed, "--main-pack", str(base_pack), "--", root,
            marker="PASS exported pack suite")
        original = (source / "fixtures" / "a.svg").read_bytes()
        (source / "fixtures" / "a.svg").write_bytes(original + b"\n<!-- changed after content build -->\n")
        try:
            run(godot, source, "--editor", "--export-pack", "AddressablesTest", str(WORK / "stale.pck"),
                expected_error="Content changed after building:", timeout=120)
            environment = os.environ.copy()
            environment["APPDATA"] = str(WORK / "profile" / "APPDATA")
            environment["LOCALAPPDATA"] = str(WORK / "profile" / "LOCALAPPDATA")
            checked = subprocess.run([sys.executable, str(ADDON / "editor" / "export_cli.py"),
                                      "--godot", str(godot), "--project", str(source),
                                      "--preset", "AddressablesTest", "--output", str(WORK / "checked.pck")],
                                     capture_output=True, text=True, encoding="utf-8", errors="replace",
                                     env=environment, timeout=120)
            (WORK / "logs" / "checked-export.log").write_text(checked.stdout + checked.stderr, encoding="utf-8")
            assert checked.returncode != 0 and "Content changed after building:" in checked.stdout
            print("PASS checked export rejects stale content", flush=True)
            RESULTS.append({"stage": "checked export rejects stale content", "status": "passed"})
        finally:
            (source / "fixtures" / "a.svg").write_bytes(original)
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=5)
    if "mono" in godot.name.lower():
        test_dotnet(godot, catalog)
    report = {"status": "passed", "godot": str(godot), "stages": RESULTS,
              "source_sha256": {str(path.relative_to(ADDON)): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in ADDON.rglob("*") if path.is_file()
                                and not any(part.startswith(".") or part == "__pycache__"
                                            for part in path.relative_to(ADDON).parts)}}
    (WORK / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("PASS all Addressables tests", flush=True)


if __name__ == "__main__":
    main()
