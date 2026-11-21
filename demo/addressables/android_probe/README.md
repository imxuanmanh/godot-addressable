# Android probe

A small on-device check of the full addon flow on Android: the APK ships without the
optional content, then downloads two packs (a scene with a VRAM-compressed texture and a
~17 MB texture) from your PC, verifies, mounts and loads them. The screen shows each
step, timings and the worst frame time (the synchronous hash stall).

## Prerequisites (one time)

- Godot 4.7 editor (standard or .NET; the probe is GDScript only) and the **Android
  export templates for that exact version** (Editor > Manage Export Templates).
  Use the same editor to build content and to export the APK.
- JDK 17 and the Android SDK (platform-tools, build-tools, platform, cmdline-tools),
  configured in Editor Settings > Export > Android.
- USB debugging enabled on the phone; `adb devices` lists it.

## Steps

1. Generate the project outside this repository:

   ```text
   python demo/addressables/android_probe/make_project.py --out C:/temp/addressables_probe
   ```

2. Open `C:/temp/addressables_probe` in the Godot editor and wait for import.
   The addon is enabled and ETC2/ASTC import is on, so the editor creates both
   desktop and mobile texture variants.
3. Select `probe/build.tres` in the FileSystem dock, then
   **Project > Tools > Build selected Addressable Content**. This writes
   `probe/content/` (two PCKs and `catalog.json`, platform `Android`).
4. Project > Export > **Android Probe** (a preset is provided) > Export Project
   as `build/addressables_probe.apk`. Install it:

   ```text
   adb install -r build/addressables_probe.apk
   ```

5. Serve the content and tunnel the phone's `127.0.0.1:8000` to your PC:

   ```text
   python -m http.server 8000 --directory C:/temp/addressables_probe/probe/content
   adb reverse tcp:8000 tcp:8000
   ```

6. Open the app and press **Run probe**. Expect `PROBE RESULT: PASS` and a smooth
   colour gradient square. Logs are also in `adb logcat -s godot`.

## What to check and report

- `PROBE RESULT` and any `FAIL` lines.
- `APK does not contain the optional content` must be OK.
- The picture: a smooth gradient means the mobile texture variant decoded correctly;
  noise, pink or black means a texture-format problem.
- `Download and verify` and `worst frame`: on a desktop a 17 MB pack stalls one frame
  for about 150 ms. A phone value over about 100 ms confirms the hashing hitch.
- Press **Run probe** again in the same session, then force-stop and reopen the app and
  run again: the second launch should report `downloads started 0` (warm cache).
- **Clear cache and quit** resets the cache for a cold run.

If the app opens but shows `Exported catalog is present` as FAIL, rebuild the content
(step 3) before exporting; the export filter injects the catalog only when build state
exists. The `127.0.0.1` HTTP loopback is a test-only override; real content must use HTTPS.
