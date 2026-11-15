# Usage: editor to on-demand content

This tutorial authors a scene reference, builds external content and loads the
same identity from either source assets or verified PCKs. All APIs are
experimental in 0.1.0. The addon is independent of application models/services.

## 1. Install and prepare

Copy `addons/addressables/` to your Godot project's `addons/` directory. Keep that
installed path: scripts and the C# facade preload it. Godot .NET 4.6.3 on Windows
with .NET SDK 8 is the currently validated environment. Python 3.10+ is needed
only for checked exports/repository tests; tooling uses the standard library.

Enable **Project → Project Settings → Plugins → Addressables**. Wait for script
import/global-class registration before creating resources or running build CLI.
No autoload is created. In a GDScript-only project, omit optional `dotnet/` if
using a .NET editor without a matching C# solution; otherwise it can trigger C#
export expectations. C# applications compile the facade through their own project.

## 2. Create and assign a reference

Create `res://demo/crate.tscn`, for example a Node2D with a Sprite2D and texture.
Attach a controller with one of these fields:

```gdscript
@export var prefab: AddressableReference
```

```csharp
[Export(PropertyHint.ResourceType, "AddressableReference")]
public Resource? Prefab { get; set; }
```

Build C# scripts if applicable, select the controller and drag the target scene
into the field. The widget displays its name and key/path tooltip. Click the main
button to choose a target, `×` to clear, or `…` to inspect reference metadata.
Read-only fields cannot be reassigned/cleared.

Assignment creates new string metadata: UID key if available, path key otherwise.
It does not retain the target PackedScene. Dropping a new target replaces custom
key/type metadata with a fresh reference. A `.tres` reference container dropped
as a target is treated as the container Resource itself, not automatically unwrapped.

### Custom keys

Keeping the default UID in both application and group is easiest. To use
`prefabs/crate`, edit the key and share the exact metadata with the build group.
Dragging the target into the group again creates a default UID key, not an alias.
The array widget does not provide per-entry metadata editing.

For shared custom metadata, save the reference as `crate_reference.tres` and use
an EditorScript method to build settings from it:

```gdscript
var reference := load("res://demo/crate_reference.tres") as AddressableReference
if reference == null:
    push_error("Invalid reference container.")
    return
var group := AddressableGroup.new()
group.group_name = "props"
group.assets.assign([reference])
var settings := AddressablesBuild.new()
settings.groups.assign([group])
var code := ResourceSaver.save(settings, "res://content_build.tres")
if code != OK:
    push_error(error_string(code))
```

This snippet belongs inside a tool method after the target/reference exists.

## 3. Build groups and content

Create a saved `AddressablesBuild` resource, for example
`res://content_build.tres`. Add one AddressableGroup with a safe unique name such
as `props`, then drag targets into its assets array. Multiple selection/drop is
supported; selected entries can be removed. Groups must be nonempty.

Select the saved build resource and run **Project → Tools → Build selected
Addressable Content**. Default output is `res://addressable_content/`. Inspect
`catalog.json`, hashed PCKs and any `__shared` pack. Choose target platform metadata
and actual import/export settings together; the string alone does not reimport data.

The builder leaves scripts/extensions in the base app. Content may reference
already-shipped scripts, but cannot deploy newly compiled application code.
Rebuild after changing sources, groups, settings, imports or pipeline configuration.

## 4. Configure development and exported modes

| Mode | Catalog path | Content root | Source mode |
| --- | --- | --- | --- |
| Source development | `res://addressable_content/catalog.json` | Can be empty | true |
| Clean local PCK client | Catalog supplied to clean client | Absolute directory containing PCKs | false |
| Exported application | `res://addressables/catalog.json` | Direct HTTPS release directory | false |

Source mode still needs catalog keys. It does not prove that external packs
contain all required files: source assets can hide missing dependencies. Run a
clean-client/export test before publishing. Do not mount optional packs over
existing source paths; collisions are intentionally rejected.

## 5. Complete GDScript controller

Save as `AddressablesDemo.gd`, attach to a sufficiently long-lived Node and assign
Prefab. In source development change Catalog Path to the output catalog and set
Use Source Assets=true. For remote content replace the `.invalid` host with your
real direct HTTPS directory. Keep the controller alive during `close_demo()`.

<!-- example:gdscript-controller -->
```gdscript
extends Node

@export var prefab: AddressableReference
@export_file("*.json") var catalog_path := "res://addressables/catalog.json"
@export var content_root := "https://cdn.example.invalid/releases/demo"
@export var use_source_assets := false

var _assets: Addressables
var _handle: AddressableHandle
var _instance: Node
var _closing := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if prefab == null:
        push_error("Assign the Prefab reference first.")
        return
    var file := FileAccess.open(catalog_path, FileAccess.READ)
    if file == null:
        push_error("Cannot open catalog: " + catalog_path)
        return
    var data = JSON.parse_string(file.get_as_text())
    file.close()
    if not data is Dictionary:
        push_error("Invalid catalog JSON.")
        return

    _assets = Addressables.new()
    _assets.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(_assets)
    var issue := _assets.configure(data, content_root, use_source_assets)
    if not issue.is_empty():
        push_error(issue)
        await close_demo()
        return

    _handle = _assets.load_asset(prefab, "PackedScene")
    await _handle.wait()
    if _closing:
        return
    var scene := _handle.get_result() as PackedScene
    if scene == null:
        push_error(_handle.error)
        await close_demo()
        return
    _instance = scene.instantiate()
    add_child(_instance)

func close_demo() -> void:
    if _closing:
        return
    _closing = true
    if is_instance_valid(_instance):
        _instance.queue_free()
        await get_tree().process_frame
    _instance = null
    if _handle != null:
        _handle.release()
        _handle = null
    if _assets != null:
        await _assets.shutdown()
        _assets.queue_free()
        _assets = null
```

The owning application closes it before deleting it:

```gdscript
await demo.close_demo()
demo.queue_free()
```

The closing flag prevents a late load completion from spawning a new instance.
Do not start asynchronous cleanup only in `_exit_tree()`: its scene tree is
already being dismantled. `configure()` makes the service process during pause;
the explicit mode in this example also keeps application lifecycle work active.

## 6. Complete C# controller

Save as `AddressablesDemo.cs`, attach, compile and assign Prefab. Settings are
the same as above. Calls and continuations must remain on the Godot main thread.

<!-- example:csharp-controller -->
```csharp
using System;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using GodotAddressables;

public partial class AddressablesDemo : Node
{
    [Export(PropertyHint.ResourceType, "AddressableReference")]
    public Resource? Prefab { get; set; }

    [Export(PropertyHint.File, "*.json")]
    public string CatalogPath { get; set; } = "res://addressables/catalog.json";

    [Export]
    public string ContentRoot { get; set; } = "https://cdn.example.invalid/releases/demo";

    [Export]
    public bool UseSourceAssets { get; set; }

    private AddressablesClient? _assets;
    private AssetHandle<PackedScene>? _handle;
    private Node? _instance;
    private readonly CancellationTokenSource _loading = new();
    private bool _closing;

    public override async void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        try
        {
            if (Prefab is null)
                throw new InvalidOperationException("Assign the Prefab reference first.");
            using var file = FileAccess.Open(CatalogPath, FileAccess.ModeFlags.Read)
                ?? throw new InvalidOperationException("Cannot open catalog.");
            var parsed = Json.ParseString(file.GetAsText());
            if (parsed.VariantType != Variant.Type.Dictionary)
                throw new InvalidOperationException("Invalid catalog JSON.");

            _assets = AddressablesClient.Create(this, parsed.AsGodotDictionary(),
                ContentRoot, UseSourceAssets);
            _handle = _assets.Load<PackedScene>(Prefab);
            var scene = await _handle.GetAsync(_loading.Token);
            if (_closing) return;
            _instance = scene.Instantiate();
            AddChild(_instance);
        }
        catch (OperationCanceledException)
        {
            // CloseAsync releases this token and shuts down its owner.
        }
        catch (Exception exception)
        {
            GD.PushError(exception.Message);
            await CloseAsync();
        }
    }

    public async Task CloseAsync()
    {
        if (_closing) return;
        _closing = true;
        _loading.Cancel();
        if (GodotObject.IsInstanceValid(_instance))
        {
            _instance!.QueueFree();
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        }
        _instance = null;
        _handle?.Dispose();
        _handle = null;
        if (_assets is not null)
        {
            await _assets.ShutdownAsync();
            _assets = null;
        }
        _loading.Dispose();
    }
}
```

Call `await demo.CloseAsync(); demo.QueueFree();` before removing it. Independent
consumers each call `Load`; they must not share one token then cancel each other.
Do not move facade calls into Task.Run or continue Godot calls on a worker thread.
Failed/canceled `GetAsync` disposes that token automatically; successful tokens
remain owned until explicitly disposed.

## 7. Own a set of assets with a scope

Application config can export an `Array[AddressableReference]`. Keep build groups
as editor resources; they do not represent runtime feature ownership.

```gdscript
var scope := assets.create_scope()
if not await scope.load_all(required_references):
    push_error("Cannot prepare content set.")
    scope.release()
    return
var handle := scope.get_handle(prefab_reference)
var scene := handle.get_result() as PackedScene if handle != null else null
if scene == null:
    scope.release()
    return
# Keep scope while this feature uses its assets.
# Remove instances and other external references before scope.release().
```

This is an async-method fragment using application-provided references/service.
Every acquire creates a token even for duplicate keys; the operation is still
shared. Deduplicate inputs if desired. A failed batch releases only its new
tokens and retains earlier successful batches. Scopes do not clean up instances.

## 8. Textures and audio

```gdscript
var handle := assets.load_asset(icon_reference, "Texture2D")
await handle.wait()
if handle.get_result() != null:
    icon.texture = handle.get_result()
else:
    push_error(handle.error)
# On feature closure:
icon.texture = null
handle.release()
```

For audio use expected type `AudioStream`, assign the result to `player.stream`,
and later call `player.stop(); player.stream = null` before releasing its handle.
These fragments assume application-owned controls/players. Pools, static fields,
signal closures and C# wrappers can retain a Resource after ownership reaches zero.

## 9. Predownload before opening a feature

```gdscript
var needed := assets.get_download_size(required_references)
if needed < 0:
    push_error("Unknown catalog key.")
    return
var issue := await assets.download_dependencies(required_references)
if not issue.is_empty():
    push_error(issue)
    return
# Acquire handles only when the feature actually needs Resources.
```

Predownload verifies disk cache without mounting or keeping asset RAM. Size/hash
queries are synchronous and should not run every frame. Handle.progress is not
download-byte progress. This API is currently GDScript-only; the C# facade does
not wrap predownload or scopes.

## 10. Build and checked export from the command line

Run against your application project, not the standalone addon checkout (which
has no `project.godot`). Example PowerShell from the application project root:

```powershell
$godot = 'PATH/TO/Godot.exe'
& $godot --headless --editor --path . --import --quit
& $godot --headless --path . --script res://addons/addressables/editor/build_cli.gd -- res://content_build.tres
if ($LASTEXITCODE -ne 0) { throw 'Content build failed' }
python addons/addressables/editor/export_cli.py --godot $godot --project . --preset 'Windows Desktop' --output 'build/application.pck' --mode pack
if ($LASTEXITCODE -ne 0) { throw 'Application export failed' }
```

Prepare the preset and output directory. For `--mode debug`/`release`, install
matching export templates and target SDKs. The current suite verifies a base PCK
export, not a deployed Android/iOS application. Never upload old output after a
failed export; the wrapper does not remove existing files.

## 11. Publish an immutable content release

1. Import and build for the intended engine/platform, then check success.
2. Keep all generated files for that release together.
3. Upload catalog-referenced PCK filenames unchanged to one HTTPS directory.
4. Export the app with the matching injected catalog and configure that directory.
5. Test a clean client with cold cache, warm cache and offline behavior.

Use direct file responses, not redirect links. Catalog hashes check expected
bytes; trust/authentication of the catalog is your application's responsibility.
For local testing, an absolute pack directory uses copy/verify/cache/mount without
HTTP. The native runner manages a loopback server itself; production needs no
localhost override.

## 12. Application policy and limits

The application decides which references a feature needs, access/unlock policy,
fallback UI, overall deadline, retry/backoff and cache eviction. The addon has a
default inactivity timeout, no automatic catalog activation, no hot replacement
or unmount, and no tracked-instance API. Release handles explicitly; pre-delete
cleanup is only a fallback.

See [API](API.md), [Architecture](ARCHITECTURE.md), and
[Testing and troubleshooting](TESTING_AND_TROUBLESHOOTING.md) for lifecycle details.
