extends SceneTree
## Fault injection for transport, integrity, policy, timeout, cancellation and path collisions.
## Failures must not mount corrupt content or leave unwanted owners/temporary files.
## The protected collision fixture is created only inside the generated test project.

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
	var service := Addressables.new()
	root.add_child(service)
	check(service.configure(catalog, args[0], false, args[1] != "insecure").is_empty(), "configure failures")
	service._packs.cache_directory = "user://failure_" + args[1]
	service._packs.request_timeout = 0.4
	var mode: String = args[1]
	if mode == "cancel" or mode == "shutdown":
		service._packs.request_timeout = 2.0
	if mode == "collision":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://fixtures"))
		var file := FileAccess.open("res://fixtures/a.tscn", FileAccess.WRITE)
		file.store_string("protected existing content")
		file.close()
	if mode == "cancel":
		var handle := service.load_asset("asset/a")
		await create_timer(0.05).timeout
		handle.release()
		while not service._packs._pending.is_empty():
			await process_frame
		check(handle.status == "released", "consumer canceled")
		check(not FileAccess.file_exists("res://fixtures/a.tscn"), "canceled consumer cannot mount late pack")
		check(service.debug_snapshot().operations == 0, "canceled load not republished")
	elif mode == "shutdown":
		var handle := service.load_asset("asset/a")
		await create_timer(0.05).timeout
		await service.shutdown()
		check(handle.get_result() == null, "shutdown during download has no result")
		handle.release()
		await create_timer(0.1).timeout
		check(service.debug_snapshot().operations == 0, "shutdown clears pending operations")
	else:
		var handle := service.load_asset("asset/a", "PackedScene")
		await handle.wait()
		check(handle.get_result() == null and handle.status == "failed", "download failure is reported")
		check(not handle.error.is_empty(), "failure includes reason")
		if mode == "collision":
			check(FileAccess.get_file_as_string("res://fixtures/a.tscn") == "protected existing content", "collision cannot overwrite base")
		else:
			check(not FileAccess.file_exists("res://fixtures/a.tscn"), "failed content never mounted")
		handle.release()
		check(service.debug_snapshot().owners == 0, "failure leaves no owners")
	var dir := DirAccess.open(service._packs.cache_directory)
	if dir != null:
		for filename in dir.get_files():
			check(not filename.ends_with(".part"), "temporary download removed")
	await service.shutdown()
	service.free()
	print("PASS failure %s suite (%s checks)" % [mode, checks])
	quit(0)
