# API example

Open `api/main.gd`; fold its regions to see the public API calls in order.
`ItemData` has only `display_name` and `power` fields. The example owns its data,
references and build settings and uses the addon's source from this repository.

## Build and run

1. Open the repository's root `project.godot` and wait for import.
2. Select `api/build.tres`, then **Project > Tools > Build selected Addressable Content**.
3. Press F5, or open `api/main.tscn` and press F6. Read Output; it exits after `PASS API flow`.

The flow is `item.gd` -> `assets/*.tres` -> `references/*.tres` -> `build.tres`
-> generated `content/catalog.json` and PCK -> `main.gd`.

Rebuild after editing data/references/settings. `content/` is generated and ignored
by Git. Source mode reads assets from the project; predownload prepares the local
PCK cache. No visual example, external project or production CDN is required.

## API at a glance

A successful-call outline inside a Node method. `catalog` is parsed JSON;
`reference` is one of the entries in `references`. See [api/main.gd](api/main.gd)
for the runnable version with setup, checks and logs.

```gdscript
var assets := Addressables.new()                         # Create the service.
add_child(assets)                                        # Keep it in the scene tree.
assets.configure(catalog, content_root, use_source_assets) # Configure once.

assets.get_download_size(references)                     # Query missing pack bytes.
await assets.download_dependencies(references)           # Optional: cache packs ahead of use.

var handle := assets.load_asset(reference)               # Acquire one asset.
await handle.wait()                                      # Wait for success or failure.
handle.get_result()                                      # Read the Resource; null on failure.
handle.release()                                         # Return this handle's ownership.

var scope := assets.create_scope()                       # Own a set, e.g. one match.
await scope.load_all(references)                         # Acquire and wait for the set.
scope.get_handle(reference).get_result()                 # Read an asset owned by the set.
scope.release()                                          # Return the whole set's ownership.

await assets.shutdown()                                 # Close and drain pending work.
assets.queue_free()                                      # Remove the service Node.
```

Pack preparation is optional: loading an asset prepares its packs on demand.
In application code, check error/results and clear consumers' Resource references
before releasing ownership. This outline omits asset usage and error handling.
