# Testing and troubleshooting

The suite tests the addon in generated projects, without an application-specific
model or source project. Full native validation is currently Windows oriented.
Version 0.1.0 remains experimental even when this suite passes.

## Prerequisites and commands

- Python 3.10+; standard library only.
- Godot .NET 4.6.3 distribution with the adjacent GodotSharp directory intact.
- .NET SDK 8 for C# compilation/runtime checks; matching Godot.NET.Sdk packages.
- Permission to start a local HTTP server and connect to loopback.

From the standalone repository root:

```text
python tools/check_repository.py
python addons/addressables/tests/run_tests.py --godot "PATH/TO/Godot_v4.6.3-stable_mono_win64.exe" --stage-engine
```

`--stage-engine` copies the complete engine into ignored test work. This helps
when a sandbox cannot resolve external native/.NET siblings; do not commit it.
`--prepare-only` generates fixtures without claiming test success. Use an explicit
path to your installation; no developer's absolute engine path is required.

The runner derives source locations from itself and creates projects under
`addons/addressables/.test_work/`. It includes separate profiles/cache, generated
content and a clean client. The test C# project uses matching local engine NuGet
packages. Existing application projects and global NuGet settings are not changed.

The suite creates a Windows Desktop export preset and enables its C# branch based
on a `mono` executable name. Running a non-Mono engine can omit C# validation.
Do not report that branch as tested without checking the bridge stage/report.
Native Linux/macOS/mobile coverage is not established by this runner today.

## What the suite exercises

| Area | Checks |
| --- | --- |
| Inspector and authoring | Single/multiple drops, metadata strings, read-only handling, references/UIDs |
| Build | Group validation, imported dependency closure, shared packs, code stays in base |
| Resource runtime | Shared ownership, types, scopes, release, failures/retry, closure and drain |
| Clean client | Target assets absent before pack mount, local/remote load then instantiation |
| HTTP cache | Cold, concurrent, repair, warm and offline runs |
| Failure cases | Invalid metadata/URLs, bad response/content, cancellation/timeout/collision behavior |
| Export | Optional sources excluded, catalog injected, exported base pack can use delivered content |
| Stale state | Changed sources trigger export errors and checked wrapper failure |
| C# | Bridge compilation, generic results, cancellation/disposal and shutdown |

Inspect individual suites for exact assertions; this table is not a claim of
production-scale load or device coverage. Source-mode checks cannot replace
clean-client tests because locally present files hide missing pack entries.

## Reports and expected failures

The runner records stage results/logs under `.test_work`. `report.json` is written
only after every required stage succeeds, ending with `PASS all Addressables
tests`. Check its engine, stages and C# result rather than relying on an old report.
The runner clears/rebuilds its work for a run. These artifacts are ignored by Git.

Some negative tests deliberately invoke malformed resources or stale exports.
The runner recognizes those expected failures. A normal export job should use
`editor/export_cli.py`, which fails on nonzero exit or `ERROR:` output even when
Godot itself returns zero. Never suppress unexpected errors to manufacture a pass.

`tools/check_repository.py` only checks package/docs/license/Python syntax. It does
not launch Godot or compile C#. The included GitHub workflow runs these static
checks; full native CI is a documented follow-up in the root CI.md.

## Diagnostic workflow

1. Read the handle error, not only is_done/progress.
2. Confirm the exact key exists in the configured catalog.
3. Check source mode versus external-pack mode and the selected catalog path.
4. Verify catalog engine/platform and actual imports match the running build.
5. Check direct pack URL, response status, expected size and hash.
6. Compare registry diagnostics before/after consumer release and shutdown.
7. Reproduce with a clean process/client/cache to distinguish memory, mount and disk state.

`debug_snapshot()` describes registered service operations. Failed tokens can
survive outside the registry; zero owners does not account for instantiated
nodes, pools, audio or other native/C# Resource references.

## Common problems

| Symptom | Likely cause and next action |
| --- | --- |
| AddressableReference not recognized | Wait for import/class registration; confirm installed addon path and parse errors |
| Inspector keeps a PackedScene directly | Field is a PackedScene rather than AddressableReference; change field type/hint |
| Wrong target after editing source_path | A UID key still resolves; reassign a fresh reference or update key deliberately |
| Custom key not found | App and group used different metadata; share the same reference/key |
| Dragged reference .tres loads a container | Drop targets are not unwrapped; programmatically share the contained metadata |
| Unknown address | Missing catalog key; source_path is not a runtime fallback |
| Cannot configure again | Service already configured/used; create a fresh service |
| Content engine/platform mismatch | Rebuild for actual engine minor and target; do not rewrite metadata to hide it |
| Source test works, clean client fails | Missing imported payload/base dependency; rebuild and inspect closure |
| Resource missing | Wrong catalog, missing base code/data, or unmounted/incomplete pack |
| HTTP 3xx fails | Redirects are disabled; use direct HTTPS files |
| HTTP rejected | HTTPS required; loopback HTTP is opt-in for tests only |
| Size or SHA mismatch | Corrupt/mismatched release; verify CDN object and immutable catalog pairing |
| Download stalls | No byte progress for configured stall interval; inspect connection/server |
| Large progressing download exceeds 30s | Allowed: timeout measures inactivity, not total duration |
| Pack collision | File exists in base project or another mounted release; test clean client/process |
| Retry still returns failed scope token | Release earlier failed manual token before get_handle lookup |
| is_done true but no result | Terminal also includes failed/released; inspect status/error and type |
| progress 1.0 after failure | Terminal progress is 1.0; it is not a success indicator |
| Loading/shutdown hangs when paused | Preserve configure's Always mode and a live tree; check application continuation logic |
| Closing spawns a late instance | Add a consumer closing/generation check after await, as in Usage |
| Deleting owner causes frame hitch | Await shutdown before removal; _exit_tree has synchronous drain fallback |
| Memory remains after release | Remove instances/streams/pools/closures and inspect native/C# references |
| Cache files remain after release | Expected; disk cache has a separate lifetime and no eviction API |
| New pack does not replace an old path | Hot replacement/unmount is unsupported; start a fresh process |
| Export includes optional content | Plugin disabled or build state missing; import, enable, build, export again |
| Export says stale metadata/content | Rebuild after changes; use checked wrapper and reject old output |
| C# SDK not found | Check .NET 8, matching GodotSharp offline feed and complete Mono distribution |
| C# export requested in GDScript-only project | Omit optional dotnet folder or supply a valid C# project |

## Manual validation before a real release

Test the intended device and import/export profile, not just a desktop catalog
label. Use representative pack sizes to measure synchronous hash/copy stalls,
RAM/VRAM peaks, download concurrency and UI responsiveness. Test real TLS/CDN
behavior, interrupted connectivity, slow-but-progressing transfers and disk-full
conditions in the target environment.

Exercise overlapping consumers, scene changes during load, paused loading,
explicit shutdown, cold/warm cache and invalid cached bytes. Verify no optional
source assets survive in the base export and required scripts do survive.

The suite does not establish mobile compatibility, production TLS policy,
cache-size management, authenticated catalogs, overall user deadlines, automatic
retry/backoff or hot content updates. Those need explicit application policy and
target-environment validation.
