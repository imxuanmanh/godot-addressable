# Addressables testbed

One project for every on-device and exported-build check of the addon. It is
GDScript only, so any Godot 4.6+ editor works (.NET or standard). The addon is
linked, not copied, so edits to `addons/addressables/` are used immediately.
The repository root project remains the C# development project.

| Test | What it checks |
| --- | --- |
| `mount` | Download (HTTP or local copy), SHA-256 verification, mount, load, texture decoding, warm cache, frame stalls |
| `match` | Match-style load/release of 8 skins: memory returns to baseline; textures stay while instances use them; a shared skin lives until its last owner releases |

Tests need an **exported build**: with sources present (editor) the packs would
collide with the existing files. Each test prints `TEST RESULT <name>: PASS|FAIL` and,
when started unattended, exits with code 0 or 1.

## One-time setup

```text
python tools/testbed.py setup
```

This links `testbed/addons/addressables` to the repository addon (a junction on
Windows, no admin needed) and generates the ignored test textures. Remove the link
itself with `rmdir testbed\addons\addressables`; never delete it recursively.

## Windows

```text
python tools/testbed.py build --platform windows --godot "PATH/TO/Godot_v4.7.1-stable_win64_console.exe"
python tools/testbed.py run --test match
python tools/testbed.py run --test mount
```

The build imports, builds Windows content, exports to `testbed/build/windows/` and
copies `content/` next to the executable. You can also double-click `testbed.exe`
and pick a test in the menu. Use the same editor for the content build and export.

## Android

Requirements: Android SDK, JDK 17 and the export templates of the editor version
you use (Editor > Manage Export Templates), and USB debugging on the phone.

```text
python tools/testbed.py build --platform android --godot "PATH/TO/Godot_v4.7.1-stable_win64_console.exe"
adb install -r testbed/build/android/testbed.apk
adb reverse tcp:8000 tcp:8000
python -m http.server 8000 --directory testbed/content/android
```

Open the app and choose a test, or run one unattended and read its log:

```text
adb shell "run-as com.example.addressablestestbed sh -c 'echo match > files/autorun'"
adb shell monkey -p com.example.addressablestestbed -c android.intent.category.LAUNCHER 1
adb shell "run-as com.example.addressablestestbed cat files/match.log"
```

The marker needs the app to have been started once (so `files/` exists). Delete
`files/addressables` through `run-as` for a cold-cache run. The `127.0.0.1` HTTP
loopback is a test-only override; real content must use HTTPS.

## Reading the results

- `worst frame` is the longest frame in that stage; about 16-17 ms is normal at 60 Hz.
  A value near the pack's hashing time would mean the main thread is blocked.
- `match` lines show static memory, texture memory, resource count and node count per
  step. Static memory drifts by about 0.1 MB per match from the log text itself.
- Sizes are small on purpose; test representative pack sizes and devices before release.

## Adding a test

Extend `TestCase` (`common/test_case.gd`), set `test_name` in `_init()`, implement
`_run_test()` with `_check()`/`_lap()`, and register the scene in `menu/main.gd`.
Assets for it belong in `assets/` with a group and reference under `content_defs/`
and an entry in both `build_*.tres` files.
