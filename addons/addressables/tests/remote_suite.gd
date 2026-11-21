extends SceneTree
## Clean-client tests for local PCKs, HTTP, persistent cache and offline loading.
## Arguments: CONTENT_ROOT MODE. Pixel values and texture identity verify real imported content.

var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("CHECK FAILED: " + message)
		quit(1)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	check(not FileAccess.file_exists("res://fixtures/a.tscn"), "optional source absent before mount")
	var service := Addressables.new()
	root.add_child(service)
	check(service.configure(catalog, args[0], false, true).is_empty(), "configure remote")
	service._packs.cache_directory = "user://remote_suite_cache"
	if args[1] == "concurrent":
		service._packs.cache_directory = "user://remote_concurrent_cache"
	if args[1] == "local":
		service._packs.cache_directory = "user://local_pack_cache"
	var keys: Array = ["asset/a", "asset/b", "asset/a"]
	if args[1] == "repair":
		var broken := FileAccess.open(service._packs._cache_path("group_a"), FileAccess.WRITE)
		broken.store_string("broken cached pack")
		broken.close()
		check(service.get_download_size(keys) == int(catalog.packs.group_a.size), "invalid cache must be fetched again")
		check(await service.get_download_size_async(keys) == int(catalog.packs.group_a.size), "async size also rejects invalid cache")
	if args[1] == "cold":
		var expected := 0
		for pack in catalog.packs.values():
			expected += int(pack.size)
		check(service.get_download_size(keys) == expected, "deduplicate shared download size")
		check(await service.get_download_size_async(keys) == expected, "async size deduplicates shared downloads")
		check(await service.get_download_size_async(["missing/key"]) == -1, "async size rejects an unknown key")
		var download_error := await service.download_dependencies(keys)
		check(download_error.is_empty(), "predownload: " + download_error)
		if not download_error.is_empty():
			return
		check(not FileAccess.file_exists("res://fixtures/a.tscn"), "predownload does not mount or load")
		check(service._packs.downloads_started == 3, "download each pack once")
	elif not args[1] in ["repair", "concurrent", "local"]:
		check(service.get_download_size(keys) == 0, "valid disk cache requires zero download")
		check(await service.get_download_size_async(keys) == 0, "async size sees a valid disk cache")
	var a := service.load_asset("asset/a", "PackedScene")
	var b := service.load_asset("asset/b", "PackedScene")
	var alias := service.load_asset("asset/a", "PackedScene")
	var canceled_alias := service.load_asset("asset/a", "PackedScene")
	canceled_alias.release()
	await a.wait()
	await b.wait()
	await alias.wait()
	check(a.get_result() is PackedScene, "remote asset A: " + a.error)
	check(b.get_result() is PackedScene, "remote asset B: " + b.error)
	if a.get_result() == null or b.get_result() == null:
		return
	var node_a: Node = a.get_result().instantiate()
	var node_b: Node = b.get_result().instantiate()
	var body_a: Color = node_a.get_node("Body").texture.get_image().get_pixel(1, 1)
	var body_b: Color = node_b.get_node("Body").texture.get_image().get_pixel(1, 1)
	check(body_a.r > 0.9 and body_b.b > 0.9, "two fixtures retain distinct textures")
	check(node_a.get_node("Shared").texture == node_b.get_node("Shared").texture, "native shared texture reused")
	check(service.threaded_requests == 2, "deduplicate concurrent load")
	check(service.get_download_size(keys) == 0, "download size zero after load")
	if args[1] == "concurrent":
		check(service._packs.downloads_started == 3, "concurrent consumers share pack downloads")
	elif args[1] == "repair":
		check(service._packs.downloads_started == 1, "repair downloads only invalid cached pack")
	elif args[1] != "cold":
		check(service._packs.downloads_started == 0, "warm/offline load makes no request")
	node_a.free()
	node_b.free()
	a.release()
	b.release()
	check(alias.get_result() != null, "other owner still valid")
	alias.release()
	check(service.debug_snapshot().operations == 0, "remote resources released")
	check(FileAccess.file_exists("res://fixtures/a.tscn"), "mounted pack remains available")
	await service.shutdown()
	service.free()
	print("PASS remote %s suite (%s checks)" % [args[1], checks])
	quit(0)
