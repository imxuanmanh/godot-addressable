# Recipes

Minimal, copy-paste cases. Every case assumes the service from recipe 1 (`assets`).
Vietnamese version: [RECIPES.vi.md](RECIPES.vi.md). Full guide: [USAGE.md](USAGE.md);
every call: [API.md](API.md). The cases are exercised by the `testbed/` tests.

## 1. Set up the service once

```gdscript
var assets := Addressables.new()
add_child(assets)                                   # Must be in the scene tree.
var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://addressables/catalog.json"))
var issue := assets.configure(catalog, content_root) # Local directory or https:// directory.
assert(issue.is_empty(), issue)
```

`res://addressables/catalog.json` is injected into the export after you build content.
In the editor pass `true` as the third argument to read sources directly (no packs).
Configure once; keep one service for the whole game.

## 2. Load one asset, then release it

```gdscript
var handle := assets.load_asset("res://skins/knight.tscn", "PackedScene") # Key or AddressableReference.
await handle.wait()
var scene := handle.get_result() as PackedScene     # null on failure, see handle.error.
if scene:
	add_child(scene.instantiate())
handle.release()                                    # Always release, failed handles too.
```

## 3. One match: load a set, use it, release it

```gdscript
# Enter the match.
var scope := assets.create_scope()
if not await scope.load_all(skin_keys):             # On failure this batch is rolled back.
	scope.release()
	return
for key in skin_keys:
	holder.add_child((scope.get_handle(key).get_result() as PackedScene).instantiate())

# Leave the match.
holder.queue_free()                                 # Free instances and drop your own references.
scope.release()                                     # Return the tokens.
```

Memory drops only after both steps, in either order. Releasing the scope while
instances are alive does not free their textures.

## 4. Shared assets

```gdscript
var a := assets.create_scope()
var b := assets.create_scope()
await a.load_all([key])
await b.load_all([key])                             # Same key: one copy in memory.
a.release()                                         # Still loaded: b owns it.
b.release()                                         # Freed now (once nothing else references it).
```

## 5. Download before a feature opens

```gdscript
var bytes := await assets.get_download_size_async(keys)   # 0 when cached, -1 for an unknown key.
if bytes > 0:
	show_download_prompt(bytes)
var issue := await assets.download_dependencies(keys)     # Cache and verify; nothing is mounted or loaded.
```

Prefer `get_download_size_async`: the synchronous version hashes on the calling thread.

## 6. Handle a failed load

```gdscript
var handle := assets.load_asset(key)
await handle.wait()
if handle.get_result() == null:
	push_error("%s: %s" % [handle.status, handle.error])  # Unknown address, bad hash, missing pack...
handle.release()
```

`is_done` and `progress == 1.0` are also true after a failure; check `get_result()`.

## 7. A skin with a direct dependency (bundled with it)

```text
skin_direct.tscn --instances--> bullet.tscn      # Nothing else to declare.
Group "skin_direct": roots = [skin_direct.tscn]
```

The bullet travels in the skin's pack, loads with it and is freed with it.
Load only the skin: `assets.load_asset("res://skins/skin_direct.tscn")`.

## 8. A skin that names its bullet by reference (loaded on demand)

```gdscript
# skin.gd (part of the base app)
@export var bullet: AddressableReference            # Drag the bullet scene into this Inspector field.

# At runtime
var shot := assets.load_asset(skin_node.bullet)     # The bullet loads only now.
await shot.wait()
# ...use shot.get_result()...
shot.release()
```

```text
Group "skin":   roots = [skin.tscn]
Group "bullet": roots = [bullet.tscn]            # Required. Without it: "Unknown address" at runtime.
```

A reference is only a string, so the builder does not follow it. An unlisted target
stays in the base export and the build does not warn about it.

## 9. Build and export

Editor: select the build resource, then **Project > Tools > Build selected Addressable Content**.
Command line:

```text
godot --headless --path . --script res://addons/addressables/editor/build_cli.gd -- res://build.tres
python addons/addressables/editor/export_cli.py --godot GODOT --project . --preset "Windows" --output build/game.exe --mode debug
```

Rebuild content before every export. The build's `target_platform` must match the export
platform (one build resource per platform). Ship the generated packs to your content root.

## 10. Shut down

```gdscript
scope.release()                                     # Release your own tokens first.
await assets.shutdown()                             # Close and wait for pending loads/downloads.
assets.queue_free()
```

## Rules of thumb

- Release every handle and scope, including failed ones.
- Free instances and clear variables, or memory stays.
- Give each file one owner: the base app or a group, never both.
- Scripts (`.gd`, `.cs`) stay in the app; packs carry data only.
- Test pack delivery with an exported build, not the editor.
