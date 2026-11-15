extends Node
## Fold the regions to read only the public API calls, top to bottom.

@export var sword: AddressableReference
@export var shield: AddressableReference
@export var use_source_assets := true
@export_dir var content_root := "res://demo/addressables/api/content"


func _ready() -> void:
	var assets := Addressables.new()
	add_child(assets)
	#region Read the generated catalog
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://demo/addressables/api/content/catalog.json"))
	assert(catalog is Dictionary, "Build api/build.tres first.")
	#endregion
	var issue := assets.configure(catalog, content_root, use_source_assets)
	#region Check setup
	assert(issue.is_empty(), issue)
	print("[API] Configured: ", "source" if use_source_assets else "PCK")
	#endregion

	var bytes := assets.get_download_size([sword, shield])
	issue = await assets.download_dependencies([sword, shield])
	#region Log optional predownload
	assert(bytes >= 0 and issue.is_empty(), issue)
	print("[API] Dependencies ready; missing bytes before preparation: ", bytes)
	#endregion

	var handle := assets.load_asset(sword)
	await handle.wait()
	var item := handle.get_result() as ItemData
	#region Use the data, then drop the borrowed Resource reference
	assert(item != null, handle.error)
	print("[API] Single item: ", item.display_name, " / power=", item.power)
	item = null
	#endregion
	handle.release()
	#region Check single release
	assert(handle.status == "released" and assets.debug_snapshot().owners == 0)
	print("[API] Single handle released")
	#endregion

	var scope := assets.create_scope()
	var loaded := await scope.load_all([sword, shield])
	#region Check the batch
	assert(loaded and assets.debug_snapshot().owners == 2, "Batch load failed.")
	#endregion
	item = scope.get_handle(shield).get_result() as ItemData
	#region Use the scoped data, then drop the borrowed Resource reference
	assert(item != null)
	print("[API] Scoped item: ", item.display_name, " / power=", item.power)
	item = null
	#endregion
	scope.release()
	#region Check that the whole set was released
	var state := assets.debug_snapshot()
	assert(state.owners == 0 and state.operations == 0)
	print("[API] Scope released: owners=", state.owners, ", operations=", state.operations)
	#endregion

	await assets.shutdown()
	assets.queue_free()
	#region Finish the log-only example
	print("PASS API flow")
	get_tree().quit()
	#endregion
