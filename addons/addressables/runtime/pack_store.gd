extends Node
## Internal PCK download, verification, cache and mount implementation.
## Transfers are deduplicated by SHA within this store; mounted packs are process-wide.
## Resource ownership, mounted packs and disk cache have independent lifetimes.

## Successful process-wide mounts, not a reference count of assets.
static var _mounted: Dictionary = {}
var _catalog: Dictionary
var _root := ""
var _allow_localhost := false
var _pending: Dictionary = {}
var _closed := false
## Internal setup field; the application facade does not expose cache configuration yet.
var cache_directory := "user://addressables"
## Maximum seconds without new downloaded bytes, not a total transfer deadline.
var request_timeout := 30.0
var downloads_started := 0


## Receive a catalog snapshot already validated by the owning service.
func configure(catalog: Dictionary, content_root: String, allow_localhost: bool) -> void:
	_catalog = catalog
	_root = content_root.trim_suffix("/")
	_allow_localhost = allow_localhost


## Name cache files by content hash so different versions cannot share one cache entry.
func _cache_path(id: String) -> String:
	return cache_directory.path_join(_catalog.packs[id].sha256 + ".pck")


## Use a store-specific suffix to avoid simultaneous writers sharing one .part file.
func _temporary_path(id: String) -> String:
	return _cache_path(id) + ".%s.part" % get_instance_id()


func _valid_file(path: String, pack: Dictionary) -> bool:
	# shortcut: verification hashes synchronously, move to a worker if measured pack sizes stall frames.
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() == int(pack.size) \
		and FileAccess.get_sha256(path) == pack.sha256


## Resolve references/keys to a unique dependency closure before starting I/O.
func _collect(keys: Array) -> Dictionary:
	var required: Dictionary = {}
	for reference in keys:
		var key: String = reference.key if reference is AddressableReference else str(reference)
		if not _catalog.assets.has(key):
			return {"error": "Unknown address: %s" % key}
		var id: String = _catalog.assets[key].get("pack", "")
		if not id.is_empty():
			_add_pack(id, required)
	return {"packs": required}


## Deduplicate dependencies; catalog validation has already rejected cycles.
func _add_pack(id: String, result: Dictionary) -> void:
	if result.has(id):
		return
	result[id] = true
	for dependency in _catalog.packs[id].get("dependencies", []):
		_add_pack(dependency, result)


## Count uncached, unmounted pack bytes, not asset memory usage.
func get_download_size(keys: Array) -> int:
	var required := _collect(keys)
	if required.has("error"):
		return -1
	var size := 0
	for id in required.packs:
		var pack: Dictionary = _catalog.packs[id]
		if not _mounted.has(pack.sha256) and not _valid_file(_cache_path(id), pack):
			size += int(pack.size)
	return size


## Fetch the required packs in sequence without mounting or acquiring asset ownership.
func download_dependencies(keys: Array) -> String:
	var required := _collect(keys)
	if required.has("error"):
		return required.error
	for id in required.packs:
		var issue := await _download(id)
		if not issue.is_empty():
			return issue
	return ""


## Prepare the complete closure before the service checks cancellation and mounts it.
func prepare_pack(id: String) -> String:
	var required: Dictionary = {}
	_add_pack(id, required)
	for dependency in required:
		var issue := await _download(dependency)
		if not issue.is_empty():
			return issue
	return ""


## Join an in-flight transfer with the same SHA within this store.
func _download(id: String) -> String:
	if _closed:
		return "Content store is closed."
	var pack: Dictionary = _catalog.packs[id]
	if _mounted.has(pack.sha256) or _valid_file(_cache_path(id), pack):
		return ""
	var transfer_key: String = pack.sha256
	if _pending.has(transfer_key):
		var pending: Dictionary = _pending[transfer_key]
		while not pending.done and not _closed:
			await get_tree().process_frame
		return "Content store is closed." if _closed else pending.error
	var pending := {"done": false, "error": "", "request": null, "temporary": _temporary_path(id)}
	_pending[transfer_key] = pending
	var issue := await _download_core(id, pending)
	pending.error = issue
	pending.done = true
	_pending.erase(transfer_key)
	return issue


## Copy/download into .part, verify size/SHA, then atomically commit the cache file.
## Require HTTP 200 and a direct URL; close() cancels the request and removes temporary files.
func _download_core(id: String, pending: Dictionary) -> String:
	var pack: Dictionary = _catalog.packs[id]
	var destination := _cache_path(id)
	var code := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))
	if code != OK:
		return "Cannot create content cache: %s" % error_string(code)
	var temporary := _temporary_path(id)
	var issue := ""
	if _root.begins_with("res://") or _root.begins_with("user://") \
			or (not _root.contains("://") and _root.is_absolute_path()):
		code = DirAccess.copy_absolute(_root.path_join(pack.file), temporary)
		if code != OK:
			issue = "Cannot copy local content pack: %s" % error_string(code)
	else:
		var url: String = _root + "/" + pack.file
		var allowed: bool = url.begins_with("https://")
		if _allow_localhost:
			var loopback := RegEx.new()
			loopback.compile("^http://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?/")
			allowed = allowed or loopback.search(url) != null
		if not allowed:
			return "Remote content requires HTTPS (loopback HTTP is opt-in for tests)."
		var request := HTTPRequest.new()
		add_child(request)
		pending.request = request
		# A total request timeout would reject slow but progressing large transfers.
		request.timeout = 0.0
		request.max_redirects = 0
		request.body_size_limit = int(pack.size)
		request.download_file = temporary
		var response := {"done": false, "result": -1, "code": 0}
		request.request_completed.connect(func(result: int, status_code: int, _headers: PackedStringArray, _body: PackedByteArray):
			response.result = result
			response.code = status_code
			response.done = true)
		downloads_started += 1
		code = request.request(url)
		if code != OK:
			issue = "Cannot start pack download: %s" % error_string(code)
		else:
			var stalled := false
			var last_bytes := -1
			var last_progress := Time.get_ticks_msec()
			while not response.done and not _closed:
				await get_tree().process_frame
				var bytes := request.get_downloaded_bytes()
				if bytes != last_bytes:
					last_bytes = bytes
					last_progress = Time.get_ticks_msec()
				elif request_timeout > 0.0 and Time.get_ticks_msec() - last_progress > request_timeout * 1000.0:
					stalled = true
					break
			if _closed:
				issue = "Content store is closed."
			elif stalled:
				issue = "Pack download stalled for %s seconds." % request_timeout
			elif response.result != HTTPRequest.RESULT_SUCCESS or response.code != 200:
				issue = "Pack download failed (HTTP %s, result %s)." % [response.code, response.result]
		request.cancel_request()
		request.queue_free()
		pending.request = null
	if issue.is_empty() and not _valid_file(temporary, pack):
		issue = "Pack size or SHA-256 mismatch: %s" % id
	if issue.is_empty():
		if _valid_file(destination, pack):
			code = DirAccess.remove_absolute(temporary)
		else:
			code = DirAccess.rename_absolute(temporary, destination)
		if code != OK:
			issue = "Cannot commit downloaded pack: %s" % error_string(code)
	if not issue.is_empty() and FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	return issue


## Mount dependencies first, reject collisions and never replace existing resource files.
## Application code should go through the service ownership check instead of calling this directly.
func ensure_pack(id: String) -> String:
	if _closed:
		return "Content store is closed."
	var pack: Dictionary = _catalog.packs[id]
	if _mounted.has(pack.sha256):
		return ""
	for dependency in pack.get("dependencies", []):
		var dependency_issue := await ensure_pack(dependency)
		if not dependency_issue.is_empty():
			return dependency_issue
	var issue := await _download(id)
	if not issue.is_empty():
		return issue
	# Another coroutine may have mounted the same pack while this one downloaded it.
	if _mounted.has(pack.sha256):
		return ""
	if _closed:
		return "Content store is closed."
	for path in pack.get("files", []):
		if FileAccess.file_exists(path):
			return "Pack collides with an existing resource: %s" % path
	if not ProjectSettings.load_resource_pack(_cache_path(id), false):
		return "Cannot mount content pack: %s" % id
	_mounted[pack.sha256] = true
	return ""


## Stop the store, cancel HTTP and remove temporary files; the service waits for coroutine cleanup.
func close() -> void:
	_closed = true
	for pending in _pending.values():
		if is_instance_valid(pending.request):
			pending.request.cancel_request()
		var temporary: String = pending.temporary
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
