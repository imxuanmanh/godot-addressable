extends SceneTree
## Intentionally writes a malformed .tres, repairs it and retries the same path.
## Expected native resource errors are allowed; script/assertion errors and missing PASS markers fail.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://transient.tres"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" format=3]\n[resource]\nresource_name = "unterminated')
	file.close()
	var service := Addressables.new()
	root.add_child(service)
	var catalog := {"schema_version": 1, "assets": {"transient": {"path": path, "type": "Resource"}}, "packs": {}}
	if not service.configure(catalog).is_empty():
		push_error("CHECK FAILED: configure failure fixture")
		quit(1)
		return
	var first := service.load_asset("transient")
	await first.wait()
	if first.status != "failed":
		push_error("CHECK FAILED: malformed resource should fail")
		quit(1)
		return
	first.release()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" format=3]\n[resource]\nresource_name = "Recovered"\n')
	file.close()
	var retried := service.load_asset("transient")
	await retried.wait()
	if retried.get_result() == null or retried.get_result().resource_name != "Recovered":
		push_error("CHECK FAILED: failed engine request was not drained before retry")
		quit(1)
		return
	retried.release()
	await service.shutdown()
	service.free()
	print("PASS failed resource retry suite")
	quit(0)
