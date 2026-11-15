extends SceneTree
## Source-local tests for aliases, typed results, ownership, scopes, cancellation and shutdown.
## Repeated instantiate/release cycles check registry cleanup, not exact operating-system RSS.

var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("CHECK FAILED: " + message)
		quit(1)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/catalog.json"))
	catalog.assets.alias = catalog.assets["asset/a"].duplicate()
	var service := Addressables.new()
	root.add_child(service)
	var configuration_error := service.configure(catalog, "", true)
	check(configuration_error.is_empty(), "configure local: " + configuration_error)
	if not configuration_error.is_empty():
		return
	var first := service.load_asset("asset/a", "PackedScene")
	var second := service.load_asset("alias", "PackedScene")
	await first.wait()
	await second.wait()
	check(first.get_result() is PackedScene, "load scene")
	check(first.get_result() == second.get_result(), "aliases share resource")
	check(service.threaded_requests == 1, "one threaded request")
	check(service.debug_snapshot().owners == 2, "two independent owners")
	first.release()
	first.release()
	check(first.get_result() == null and first.status == "released", "released handle invalidated")
	check(second.get_result() != null and service.debug_snapshot().owners == 1, "other owner survives release")
	second.release()
	check(service.debug_snapshot().operations == 0, "last owner evicts operation")
	var failed := service.load_asset("unknown")
	await failed.wait()
	check(failed.status == "failed" and failed.get_result() == null, "unknown address fails")
	failed.release()
	var wrong := service.load_asset("asset/a", "AudioStream")
	await wrong.wait()
	check(wrong.status == "failed" and wrong.get_result() == null and not wrong.error.is_empty(), "typed result rejects mismatch")
	wrong.release()
	var scope := service.create_scope()
	check(await scope.load_all(["asset/a", "asset/b"]), "scope loads asset assets")
	check(scope.get_handle("asset/a").get_result() is PackedScene, "group result available by reference key")
	check(service.debug_snapshot().owners == 2, "scope holds ownership")
	scope.release()
	scope.release()
	check(service.debug_snapshot().operations == 0, "scope release is idempotent")
	check(scope.acquire("asset/a") == null, "closed scope cannot acquire")
	var batch := service.create_scope()
	check(not await batch.load_all(["asset/a", "unknown"]), "partial failure rolls back")
	await process_frame
	check(service.debug_snapshot().owners == 0, "failed batch holds no owners")
	batch.release()
	var canceled := service.load_asset("asset/a")
	canceled.release()
	var replacement := service.load_asset("asset/a")
	await replacement.wait()
	check(replacement.get_result() is PackedScene, "cancel before start does not erase replacement")
	replacement.release()
	for iteration in range(20):
		var handle := service.load_asset("asset/a" if iteration % 2 == 0 else "asset/b")
		await handle.wait()
		var instance: Node = handle.get_result().instantiate()
		check(instance.get_node("Body").texture is Texture2D, "instantiate imported texture")
		instance.free()
		handle.release()
		check(service.debug_snapshot().owners == 0 and service.debug_snapshot().operations == 0, "cycle leaves no operation")
	var closing := service.load_asset("asset/b")
	service.close()
	await closing.wait()
	check(closing.get_result() == null, "close rejects late publication")
	closing.release()
	await service.shutdown()
	check(service.debug_snapshot().operations == 0, "shutdown drains")
	var after_close := service.load_asset("asset/a")
	check(after_close.status == "failed", "closed service rejects load")
	after_close.release()
	service.free()
	print("PASS local runtime suite (%s checks)" % checks)
	quit(0)
