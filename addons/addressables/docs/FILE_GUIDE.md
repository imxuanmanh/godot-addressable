# File guide

This guide maps every distributed source/test file to its role. All source files
also include English comments describing their responsibility and lifecycle.
Read [Architecture](ARCHITECTURE.md) first for the complete flow, then [API](API.md)
for public contracts. Version 0.1.0 is experimental.

## Package files

| File | Responsibility |
| --- | --- |
| `plugin.cfg` | Plugin name, version, author and editor entry script |
| `.gitignore` | Exclude staged engines, test work and Python bytecode from the addon |
| `README.md` | Installation summary and links that work after copying only the addon |
| `LICENSE` | MIT notice preserved by standalone folder installation |

The repository root additionally contains README, LICENSE, CHANGELOG, CI.md,
Git ignore/line-ending rules, `.github/workflows/ci.yml` and
`tools/check_repository.py`. They package/check the standalone repository rather
than participating in runtime loading. The root `project.godot` is a
development host; `demo/addressables/api/` contains one log-only Resource-data
example. It uses the same addon source in this repository. Neither the root
project nor the example needs to be copied when installing the addon elsewhere.
`GodotAddressable.csproj`/`.sln` compile the C# facade with Godot.NET.Sdk 4.6.3;
`global.json` selects .NET SDK 8. Generated fixture sources are excluded from this
root build. These files configure development, not the installed addon.

## Runtime files

### runtime/asset_reference.gd

Public `@tool` Resource `AddressableReference`. Owns string key/type/path metadata,
factory creation and UID-aware source resolution. Used by Inspector widgets,
the content builder, scopes and application exports. It does not load or retain
the heavy target as a serialized dependency. Runtime lookup uses the catalog key.

### runtime/asset_handle.gd

Public `AddressableHandle` RefCounted. Holds one acquisition of an internal
operation and a weak service owner. Computes status/type errors/progress, waits
by frame, exposes the result and releases idempotently. Pre-delete cleanup is a
fallback for forgotten ownership. Construct through Addressables, not directly.

### runtime/asset_scope.gd

Public `AddressableScope` RefCounted. Retains tokens for one feature, acquires
individual assets, loads a batch with rollback and releases the collection.
Does not instantiate nodes or destroy pools. Created by the service so its weak
owner exists. Duplicate keys still mean separate tokens.

### runtime/addressables.gd

Public `Addressables` Node and its internal Operation class. Validates/snapshots
catalogs, enables Always processing, registers operations by path and connects
pack preparation to ResourceLoader. Owns frame polling, failure/retry identity
checks, release accounting, diagnostics, close and drain. Existing engine
requests must be collected even after abandonment. No autoload/global app state.

### runtime/catalog.gd

Internal RefCounted utility with static schema/path validation. Shared by builder
and service. Accepts same-major older-minor content; rejects newer producers,
different majors/platforms, malformed engine versions/locations, invalid
pack hashes/sizes/files and cyclic/deep dependencies. It does not verify actual
PCK contents or authenticate metadata.

### runtime/pack_store.gd

Internal child Node of the service. Resolves pack closures, computes missing
bytes, joins same-store transfers by SHA, copies/downloads to store-specific
partials, checks size/hash, commits cache and mounts dependencies first. Implements
direct HTTPS/opt-in loopback, stalled-transfer timeout and close cleanup.
Mounted SHA state is static/process-wide; resource ownership and disk cache are
independent. Hashing/copying are synchronous and need real-size profiling.

## Editor and build files

### editor/plugin.gd

EditorPlugin entry point. Registers Inspector/export plugins and the build menu,
then removes them on exit. The menu builds the selected AddressablesBuild and
reports errors. Does not change game resources or install an autoload.

### editor/inspector.gd

EditorInspectorPlugin dispatches eligible single reference and typed reference
array properties to their widgets. Other properties use Godot's default editor.
C# Resource fields use the AddressableReference resource-type hint.

### editor/reference_property.gd

Single reference EditorProperty. Displays target name/tooltip, file chooser,
clear and metadata inspection; validates native file drops and read-only state.
Assignment makes fresh reference metadata rather than retaining the dropped
target. Static helpers are reused by the array widget/tests.

### editor/reference_array_property.gd

Array EditorProperty. Supports multiple drops/selection, file chooser additions
and selected-entry removal. Emits a new array when edited. Uses the single
widget's target validation and creates references per target; it does not unwrap
reference containers or edit individual custom-key metadata.

### editor/content_group.gd

Public `@tool` AddressableGroup Resource. Contains pack group name and target
reference array. Authoring only; runtime feature ownership belongs in scopes.

### editor/content_build.gd

Public `@tool` AddressablesBuild Resource. Contains groups, output directory and
target-platform metadata. The selected saved resource drives the menu/CLI build.
It does not perform platform imports or application exports itself.

### editor/content_builder.gd

Internal offline builder utility. Validates authoring inputs and source types,
resolves UID dependencies, traverses imports, separates base code and shared
content, builds hashed PCKs, writes catalog and export state. Returns an error
dictionary on failure. Does not instantiate scenes, compile code or upload files.

### editor/export_filter.gd

EditorExportPlugin consumes the local build state, checks staleness, injects the
catalog and skips optional content/editor/tests/output files. Skipping changes
that export only. Without state it cannot infer optional targets. Godot export
errors must be checked through the Python wrapper in automation.

### editor/build_cli.gd

SceneTree CLI entry point. Reads settings and optional output after `--`, invokes
the builder and translates results to logs/exit status. Requires project import
first so typed global resources are available.

### editor/export_cli.py

Standard-library checked export wrapper. Resolves engine/project/output paths,
runs a headless export mode and rejects nonzero exit or `ERROR:` output. Does
not build content, delete old outputs, install templates or publish artifacts.

## Optional .NET facade

### dotnet/AddressablesClient.cs

Namespace GodotAddressables. AddressablesClient creates/owns a runtime child and
offers typed Load, async shutdown and disposal. AssetHandle<T> adapts frame waits,
cancellation and result casts to Task<T>. Failed/canceled waits dispose the token.
All calls remain main-thread operations. The application owns returned Resource
use, instances and token lifetimes; shared results must not be manually disposed
as an ownership mechanism.

## Test files

| File | Responsibility |
| --- | --- |
| `tests/run_tests.py` | Orchestrate generated fixtures, imports, builds, clean clients, loopback HTTP, exports, logs and final report |
| `tests/editor_suite.gd` | Editor property/reference/build/dependency/shared-pack assertions and test content creation |
| `tests/runtime_suite.gd` | Source-runtime ownership, typed results, scopes, release and service lifecycle |
| `tests/resource_failure_suite.gd` | Intentionally broken threaded Resource loads, collection and later retry |
| `tests/remote_suite.gd` | Clean-client local/cold/concurrent/repair/warm/offline PCK paths and actual instantiation |
| `tests/failure_suite.gd` | Invalid content/HTTP/cancellation/timeout/mount and metadata negative cases |
| `tests/export_probe.gd` | Verify exported base PCK filtering/catalog and external pack use |
| `tests/compatibility_probe.gd` | Load unchanged older-minor catalog/PCKs in a clean newer-minor client; reject a probe that already contains source assets |
| `tests/BridgeSuite.cs.txt` | C# suite fixture copied to a generated .cs project; .txt avoids compiling test code in host applications |

Generated `.test_work/`, `.test_tools/` and Python caches are not distributed.
The native runner currently assumes Windows Desktop export and detects .NET
coverage through a Mono executable name. Static repository CI does not establish
native engine or C# coverage. The C# fixture selects Godot.NET.Sdk from
the executable's numeric version instead of pinning one engine version for all runs.

## Documentation files

| File | Read for |
| --- | --- |
| `docs/USAGE.md` | Setup, target/reference authoring, complete controllers and publication workflow |
| `docs/ARCHITECTURE.md` | Pipeline, ownership, cancellation, lifetimes, shutdown and trust |
| `docs/API.md` | Public signatures, defaults, results, exceptions and CLI arguments |
| `docs/CONTENT_FORMAT.md` | Reference identity, catalog schema, PCKs, export state and cache |
| `docs/TESTING_AND_TROUBLESHOOTING.md` | Reproducible test setup, coverage, diagnosis and known limits |
| `docs/FILE_GUIDE.md` | This source-to-responsibility map |
