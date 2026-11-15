extends SceneTree
## Run in a clean client on a newer engine with untouched older-engine catalog/PCKs.
## Arguments after --: CATALOG_JSON CONTENT_ROOT. See docs/TESTING_AND_TROUBLESHOOTING.md.

const Catalog = preload("../runtime/catalog.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Usage: compatibility_probe.gd -- CATALOG_JSON CONTENT_ROOT")
		quit(2)
		return
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not catalog is Dictionary or not catalog.get("engine") is String:
		push_error("Expected a generated older-engine catalog.")
		quit(1)
		return
	var issue := Catalog.validate(catalog)
	if not issue.is_empty() or catalog.assets.is_empty() or catalog.packs.is_empty():
		push_error("Expected valid packed content: " + issue)
		quit(1)
		return
	var current := Engine.get_version_info()
	var version: PackedStringArray = catalog.engine.split(".")
	if version.size() != 2 or version[0].to_int() != current.major or version[1].to_int() >= current.minor:
		push_error("Probe requires content from an older minor of the same major.")
		quit(1)
		return
	for location in catalog.assets.values():
		if FileAccess.file_exists(location.path):
			push_error("Probe client already contains optional source: " + location.path)
			quit(1)
			return
	var assets := Addressables.new()
	root.add_child(assets)
	issue = assets.configure(catalog, args[1])
	if not issue.is_empty():
		push_error(issue)
		quit(1)
		return
	for key in catalog.assets:
		var handle := assets.load_asset(key)
		await handle.wait()
		var result := handle.get_result()
		if result == null:
			push_error("Compatibility load failed: " + handle.error)
			quit(1)
			return
		if result is PackedScene:
			var instance: Node = result.instantiate()
			root.add_child(instance)
			instance.free()
		handle.release()
	await assets.shutdown()
	assets.free()
	print("PASS content compatibility %s -> %s.%s (%s assets)" % [catalog.engine, current.major, current.minor, catalog.assets.size()])
	quit(0)
