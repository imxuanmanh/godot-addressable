# API reference

**0.1.0 experimental.** All Godot-facing calls, including the C# facade, belong on
the main thread. Underscore-prefixed members and scripts without public class
names are implementation details. The addon path is `res://addons/addressables/`.

## AddressableReference : Resource

Lightweight editor/runtime metadata; safe to export in application resources.

| Property | Default | Contract |
| --- | --- | --- |
| `key: String` | `""` | Exact catalog identity: UID, path or semantic key |
| `expected_type: String` | `"Resource"` | Native Resource class, e.g. PackedScene |
| `source_path: String` | `""` | Authoring path/fallback, stored as a string |

`static from_path(path: String) -> AddressableReference` constructs a reference,
using the target UID if available and the path otherwise. It does not itself
reject a missing source; Inspector assignment and the builder validate sources.

`resolve_source() -> String` prefers the UID mapping when `key` starts with
`uid://`; otherwise returns `source_path`. This is a builder/editor utility.
Changing `source_path` alone will not retarget a reference whose UID still resolves.

In the editor, setting `source_path` initializes an empty key if the resource
exists. It does not overwrite an existing semantic/UID key. Use fresh Inspector
assignment to replace a target and reset its metadata.

The reference holds no loaded target Resource. Runtime lookup uses only `key`;
neither `source_path` nor `resolve_source()` bypasses the catalog.

## Addressables : Node

Create the Node, attach it to a live scene tree, configure it once, and retain it
until all consumers and asynchronous cleanup have finished. No singleton exists.

### configure

```gdscript
func configure(catalog: Dictionary, content_root: String = "",
    use_source_assets: bool = false,
    allow_localhost_http: bool = false) -> String
```

Engine metadata admits older/same-minor content on a same-major reader. It
rejects a newer producer minor, different major, malformed version or different
platform. Native PCK/resource formats are still checked while loading.

Returns `""` on success or the first catalog/configuration issue. The catalog is
deep-copied. Reconfiguration is rejected once a pack store or operations exist.
Create a new service instead of reusing a closed one.

`content_root` is a direct HTTPS directory URL, `res://`/`user://` directory, or
absolute local directory. Pack filenames are joined to it. Empty roots suffice
only when no pack delivery is required. `use_source_assets` skips PCK preparation
for development, but still requires catalog entries and source resources.

`allow_localhost_http` permits only HTTP localhost/127.0.0.1 test URLs. It is not
a production HTTP override. The optional C# facade does not expose this switch.
Successful configuration sets `process_mode = Node.PROCESS_MODE_ALWAYS`.

### load_asset

```gdscript
func load_asset(reference: Variant,
    expected_type: String = "Resource") -> AddressableHandle
```

Accepts an `AddressableReference` or a catalog key. Returns a new ownership token
immediately; load completion is asynchronous. Missing keys, closed service and
an owner outside the tree return failed tokens rather than throwing exceptions.
Release tokens on failure as well as success.

Type priority is an explicit non-Resource argument, then a reference's expected
type, then the catalog type if the selected type remains Resource. Checks use
native Godot inheritance. Validate custom script types in the application too.
Two tokens may share a path operation but request different types.

### create_scope

`create_scope() -> AddressableScope` creates an ownership collection with a weak
service reference. It does not load anything. See the scope contract below.

### get_download_size

`get_download_size(keys: Array) -> int` accepts references/keys and sums missing
pack bytes over their deduplicated dependency closure. Returns `-1` for an unknown
key or an unconfigured service. Mounted or valid cached packs contribute zero.
This is neither per-asset RAM usage nor a byte progress stream. Cache hashing is
synchronous, so query during setup/loading rather than every frame.

### download_dependencies

`download_dependencies(keys: Array) -> String` is awaited. It caches and verifies
required packs, returning `""` or the first error. It does not acquire assets,
mount PCKs or hold Resources in memory. Transfers are sequential over the closure
and join in-flight requests within the store. There is no public per-call token
for predownload; closing the service cancels its store.

### Diagnostics

`debug_snapshot() -> Dictionary` returns:

| Field | Meaning |
| --- | --- |
| `operations` | Operations still registered by resource path |
| `owners` | Owner counts on those registered operations |
| `pending_requests` | Registered engine requests awaiting collection |
| `threaded_requests` | Cumulative engine requests started by this service |
| `pending_downloads` | In-flight pack-store entries |

Failed operations can be absent from this snapshot while old failed tokens still
exist. These counters do not measure all tokens, external references, RAM or VRAM.
The public `threaded_requests: int` counter has the same cumulative meaning.

### close and shutdown

`close() -> void` is idempotent, stops acquisitions, invalidates results, cancels
HTTP and discards non-threaded registered operations. It does not await engine
requests, release caller tokens, delete cache, unmount PCKs or free the Node.

`shutdown() -> void` is awaited: closes and drains registered resource and HTTP
work while inside the tree. It does not queue-free the Node. Keep the owner alive
until it completes, then call `queue_free()` yourself. Deleting it directly invokes
a synchronous engine-drain fallback which can stall a frame.

## AddressableHandle : RefCounted

Use tokens returned by the service; do not construct or mutate their internal
state directly. Each token owns one acquisition, even if paths/keys repeat.

| Member | Meaning |
| --- | --- |
| `key: String` | Acquisition key for diagnostics/scope lookup; do not change |
| `is_done: bool` | Terminal, including failed/released; not a success flag |
| `status: String` | `loading`, `succeeded`, `failed`, or `released` |
| `error: String` | Operation/type error; dedicated message after release |
| `progress: float` | ResourceLoader progress; terminal states report 1.0 |

`get_result() -> Resource` returns a borrowed, correctly typed result only after
success. Returns null while loading or after failure/release. Keeping the returned
Resource elsewhere can retain memory independently of this token.

`wait() -> AddressableHandle` yields by scene-tree frames and returns the same
token on completion, including failure. Inspect `get_result()`/`error`; awaiting
does not throw. Loss of a live owner releases the token while waiting.

`release() -> void` is idempotent and releases only this token. Another consumer's
token remains valid. It does not destroy instantiated nodes, unmount packs, delete
cache or cancel another token. Pre-delete cleanup is a fallback for forgotten
tokens, with no promised GC timing or safe worker-thread use.

Progress describes the ResourceLoader phase, not downloaded bytes. A failed or
released handle can show 1.0. Build a separate application loading state instead
of treating `progress == 1.0` as success.

## AddressableScope : RefCounted

Create using `assets.create_scope()` and release explicitly when its feature ends.

| Method | Contract |
| --- | --- |
| `acquire(reference: Variant, expected_type: String = "Resource") -> AddressableHandle` | Retain one new token; null if scope closed or owner lost |
| `load_all(references: Array) -> bool` | Await a newly acquired batch; rollback that batch if a result fails |
| `get_handle(reference: Variant) -> AddressableHandle` | First matching unreleased token, or null |
| `release() -> void` | Idempotently close scope and release all retained tokens |

`load_all()` starts its batch before waiting in input order; it is not fail-fast.
Earlier successful batches stay retained. Duplicate input keys still acquire
duplicate tokens. A closed scope cannot be reopened.

`get_handle()` can return a loading/failed token. Release a failed manual token
before looking up a retry with the same key, otherwise the earlier token can be
found first. A scope does not instantiate or clean up scene nodes.

## Editor resources

### AddressableGroup : Resource

| Property | Default | Meaning |
| --- | --- | --- |
| `group_name: String` | `"default"` | Unique pack bucket; safe filename characters |
| `assets: Array[AddressableReference]` | `[]` | Top-level content targets |

Group names match `^[A-Za-z0-9][A-Za-z0-9_-]*$`. Null references, duplicate group
names and empty groups fail the build. Groups are authoring resources; use a
runtime scope or application-owned reference array for feature ownership.

### AddressablesBuild : Resource

| Property | Default | Meaning |
| --- | --- | --- |
| `groups: Array[AddressableGroup]` | `[]` | Nonempty list of content groups |
| `output_directory: String` | `res://addressable_content` | Dedicated content output directory |
| `target_platform: String` | `OS.get_name()` | Windows, Linux, macOS, Android or iOS metadata |

Select a saved resource, then **Project → Tools → Build selected Addressable
Content**. Set actual import/export settings for the target; changing this string
does not convert imported data to another platform.

### Builder utility

```gdscript
const Builder = preload("res://addons/addressables/editor/content_builder.gd")
var result: Dictionary = Builder.build(settings, output_override)
```

`static build(settings: AddressablesBuild, output_override: String = "") -> Dictionary`
returns `{catalog, catalog_path, excluded}` or `{error}`. It does not throw
application exceptions or upload artifacts. Import the project first. Never call
editor-only scripts from a shipped application. See [Content format](CONTENT_FORMAT.md)
for output and internal export-state details.

### Catalog validator utility

`runtime/catalog.gd` has no global class name. Preload it for tooling:
`validate(data: Dictionary) -> String` returns an empty string or first issue.
`is_resource_path(path: String) -> bool` checks normalized nonempty `res://` paths
without traversal, backslashes or subresource syntax. Validation inspects metadata,
not actual PCK contents or catalog authenticity.

## C# facade: GodotAddressables

Reference `dotnet/AddressablesClient.cs` through the normal Godot .NET project.
No custom csproj/package is installed by this addon. The Inspector-exported type
is `Resource` with the AddressableReference hint, because the target class is GDScript.

```csharp
public static AddressablesClient Create(Node parent,
    Godot.Collections.Dictionary catalog,
    string contentRoot = "", bool useSourceAssets = false);
public AssetHandle<T> Load<T>(Resource reference) where T : Resource;
public AssetHandle<T> Load<T>(string key) where T : Resource;
public Task ShutdownAsync();
public void Dispose();
```

`Create` adds/configures a runtime child and throws `InvalidOperationException`
on a configuration issue. The parent must already be live and outlive consumers.
`Load` returns a new token; loading/type failures surface when awaiting it.
Loading through a disposed client throws `ObjectDisposedException`.

`ShutdownAsync` marks the client disposed, closes, awaits pending work and
queue-frees its Node. A second call returns immediately; it does not join the
first task. Callers still clean instances/tokens. `Dispose` closes and queue-frees
without awaiting and can invoke a blocking fallback; prefer asynchronous shutdown.

```csharp
public sealed class AssetHandle<T> : IDisposable where T : Resource
{
    public bool IsDone { get; }
    public Task<T> GetAsync(CancellationToken cancellationToken = default);
    public void Dispose();
}
```

`GetAsync` returns a borrowed `T`. Native classes are checked by GDScript; custom
C# Resource classes receive an additional C# type check. Failure/cancellation
automatically disposes the token and throws `InvalidOperationException`,
`OperationCanceledException` or `ObjectDisposedException` as appropriate.

Canceling one token does not cancel another `Load` token. Multiple `GetAsync`
calls on the same token share ownership, so they are not independent consumers.
Keep Godot API calls on the main thread; do not use Task.Run or resume on a worker.
Scopes, predownload, diagnostics and byte progress are not exposed by this facade.
Do not assume a raw GDScript coroutine returned by `Call` is a .NET Task.

## Command-line tools

### Content build

```text
godot --headless --editor --path PROJECT --import --quit
godot --headless --path PROJECT --script res://addons/addressables/editor/build_cli.gd -- res://content_build.tres [OUTPUT]
```

Arguments after `--` are settings path and optional output override. Exit 0 means
success, 1 a build failure and 2 invalid arguments/settings. Global classes must
be registered by import before the build script is loaded.

### Checked application export

```text
python addons/addressables/editor/export_cli.py --godot GODOT --project PROJECT --preset PRESET --output OUTPUT --mode pack
```

Run from a checkout/project containing the addon, or use an absolute script path.
Required options are executable, project, preset and output. `--mode` is `pack`
(default), `debug` or `release`. Resolves paths, runs a headless editor export and
returns 1 for engine failure or `ERROR:` logs, otherwise 0. It does not build
content, remove old artifacts, install templates or publish. Prepare the preset,
output directory and target toolchain yourself.

### Integration runner

```text
python addons/addressables/tests/run_tests.py --godot GODOT [--stage-engine] [--prepare-only]
```

See [Testing](TESTING_AND_TROUBLESHOOTING.md) for its platform assumptions and
generated reports. Its API is developer tooling, not a runtime dependency.
