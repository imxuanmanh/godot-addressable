extends Node
## Copied to the fixture root so the export filter does not exclude the probe itself.
## Runs from a clean --main-pack client and loads optional resources from an external PCK.
## Arguments: CONTENT_ROOT. Uses a separate disk cache and exits with a test result.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Export probe requires the content URL.")
		get_tree().quit(1)
		return
	var has_source := FileAccess.file_exists("res://fixtures/a.tscn")
	var has_texture := FileAccess.file_exists("res://fixtures/a.svg")
	var has_editor := FileAccess.file_exists("res://addons/addressables/editor/plugin.gd")
	if has_source or has_texture or has_editor:
		push_error("CHECK FAILED: exported base contains optional content or editor code.")
		get_tree().quit(1)
		return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://addressables/catalog.json"))
	var service := Addressables.new()
	add_child(service)
	var issue := service.configure(catalog, args[0], false, true)
	if not issue.is_empty():
		push_error("CHECK FAILED: exported catalog: " + issue)
		get_tree().quit(1)
		return
	service._packs.cache_directory = "user://export_probe_cache"
	var host: Node = load("res://host.tscn").instantiate()
	var handle := service.load_asset(host.asset, "PackedScene")
	await handle.wait()
	var scene: Resource = handle.get_result()
	if not scene is PackedScene:
		push_error("CHECK FAILED: exported reference load: " + handle.error)
		get_tree().quit(1)
		return
	var asset: Node = scene.instantiate()
	if not asset.get_node("Body").texture is Texture2D:
		push_error("CHECK FAILED: imported texture from external PCK.")
		get_tree().quit(1)
		return
	asset.free()
	host.free()
	handle.release()
	await service.shutdown()
	print("PASS exported pack suite")
	get_tree().quit(0)
