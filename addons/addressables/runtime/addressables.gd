class_name Addressables
extends Node
## General-purpose load/release service attached to an application-owned Node.
## All registry and Godot-facing calls run on the main thread; no autoload is installed.
## Each path has one operation per service, while each acquisition owns a separate handle.
## configure() enables PROCESS_MODE_ALWAYS so resource polling continues while paused.

const Reference = preload("asset_reference.gd")
const Handle = preload("asset_handle.gd")
const Scope = preload("asset_scope.gd")
const Catalog = preload("catalog.gd")
const PackStore = preload("pack_store.gd")

## Internal state shared by the registry and handles; not a public API object.
class Operation extends RefCounted:
	## Resource path used to deduplicate acquisitions within this service.
	var path := ""
	## Shared loading, succeeded or failed state; release and type checks belong to each handle.
	var status := "loading"
	## Shared failure message; empty until the operation fails or its service closes.
	var error := ""
	## Latest ResourceLoader progress sample, excluding pack delivery.
	var progress := 0.0
	## Strong resource reference retained while the operation has owners and the service is open.
	var result: Resource
	## Number of unreleased handles sharing this operation, including failed handles.
	var owners := 0
	## Whether an engine request has started and still needs to be collected.
	var threaded := false

var _catalog: Dictionary = {}
var _operations: Dictionary = {}
var _closed := false
var _use_source_assets := false
var _packs: Node
## Count of engine requests actually started, not the number of handles.
var threaded_requests := 0


## Validate and snapshot the catalog once; return an empty string or the first issue.
## Source mode skips PCK preparation but still requires a catalog key.
## content_root is a local directory or HTTPS URL; HTTP loopback is an explicit test override.
func configure(catalog: Dictionary, content_root: String = "", use_source_assets: bool = false,
		allow_localhost_http: bool = false) -> String:
	if not _operations.is_empty() or _packs != null:
		return "Configure once before acquiring assets."
	var issue: String = Catalog.validate(catalog)
	if not issue.is_empty():
		return issue
	_catalog = catalog.duplicate(true)
	_use_source_assets = use_source_assets
	# Keep engine polling and child HTTPRequest processing alive while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_packs = PackStore.new()
	add_child(_packs)
	_packs.configure(_catalog, content_root, allow_localhost_http)
	return ""


## Create an ownership group; release it before shutting down the service.
func create_scope() -> AddressableScope:
	var scope := Scope.new()
	scope._owner = weakref(self)
	return scope


## Return a token immediately for an AddressableReference or catalog key.
## Type priority: explicit native type, reference type, then catalog location type.
## Missing keys/closed owners produce failed tokens that should still be released.
func load_asset(reference: Variant, expected_type: String = "Resource") -> AddressableHandle:
	var key: String = reference.key if reference is Reference else str(reference)
	if reference is Reference and expected_type == "Resource":
		expected_type = reference.expected_type
	var handle := Handle.new()
	handle.key = key
	handle._owner = weakref(self)
	handle._expected_type = expected_type
	var location: Dictionary = _catalog.get("assets", {}).get(key, {})
	if handle._expected_type == "Resource":
		handle._expected_type = location.get("type", "Resource")
	var path: String = location.get("path", "")
	var operation: Operation
	if not path.is_empty() and _operations.has(path) and not _closed:
		operation = _operations[path]
	else:
		operation = Operation.new()
		operation.path = path
		if _closed or not is_inside_tree():
			_fail(operation, "Addressables owner is closed or outside the scene tree.")
		elif location.is_empty():
			_fail(operation, "Unknown address: %s" % key)
		else:
			_operations[path] = operation
			_start.call_deferred(operation, location)
	operation.owners += 1
	handle._operation = operation
	return handle


## Prepare content, recheck ownership, then mount and request the Resource.
## Identity checks prevent a late old operation from removing its replacement.
func _start(operation: Operation, location: Dictionary) -> void:
	if _closed or operation.owners == 0:
		if _operations.get(operation.path) == operation:
			_operations.erase(operation.path)
		return
	if not _use_source_assets and not location.get("pack", "").is_empty():
		var issue: String = await _packs.prepare_pack(location.pack)
		if _closed:
			return
		if not issue.is_empty():
			_fail(operation, issue)
			return
		if operation.owners == 0:
			if _operations.get(operation.path) == operation:
				_operations.erase(operation.path)
			return
		issue = await _packs.ensure_pack(location.pack)
		if not issue.is_empty():
			_fail(operation, issue)
			return
	if _closed or operation.owners == 0:
		if _operations.get(operation.path) == operation:
			_operations.erase(operation.path)
		return
	if not ResourceLoader.exists(operation.path):
		_fail(operation, "Resource is missing: %s" % operation.path)
		return
	var code := ResourceLoader.load_threaded_request(operation.path)
	if code != OK:
		_fail(operation, "Threaded request failed: %s" % error_string(code))
		return
	threaded_requests += 1
	operation.threaded = true


## Collect both successful and failed engine requests; abandoned jobs must drain before retry.
func _process(_delta: float) -> void:
	for operation in _operations.values():
		if not operation.threaded:
			continue
		var values: Array = []
		var state := ResourceLoader.load_threaded_get_status(operation.path, values)
		operation.progress = values[0] if not values.is_empty() else 0.0
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			var result := ResourceLoader.load_threaded_get(operation.path)
			operation.threaded = false
			if operation.owners == 0 or _closed:
				_operations.erase(operation.path)
			elif result == null:
				_fail(operation, "ResourceLoader returned null: %s" % operation.path)
			else:
				operation.result = result
				operation.status = "succeeded"
		elif state != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if state == ResourceLoader.THREAD_LOAD_FAILED:
				ResourceLoader.load_threaded_get(operation.path)
			operation.threaded = false
			_fail(operation, "Threaded loading failed: %s" % operation.path)


## Remove failed entries so a later acquisition can create a fresh operation.
func _fail(operation: Operation, issue: String) -> void:
	operation.status = "failed"
	operation.error = issue
	operation.result = null
	if _operations.get(operation.path) == operation:
		_operations.erase(operation.path)


## Drop the last owner's strong result; retain running engine requests only to drain or join.
func _release(operation: Operation) -> void:
	operation.owners -= 1
	if operation.owners == 0:
		operation.result = null
		if not operation.threaded and _operations.get(operation.path) == operation:
			_operations.erase(operation.path)


## Return missing pack bytes, or -1 for an unknown key/unconfigured service.
## Hashes unverified cache files on the calling thread, which can stall frames for large packs;
## prefer get_download_size_async(). Files verified earlier in this process are not hashed again.
func get_download_size(keys: Array) -> int:
	return _packs.get_download_size(keys) if _packs != null else -1


## Return missing pack bytes like get_download_size(), but hash cache files on a worker thread.
## Returns -1 for an unknown key, an unconfigured/closed service, or a close during the check.
func get_download_size_async(keys: Array) -> int:
	if _packs == null or _closed:
		return -1
	return await _packs.get_download_size_async(keys)


## Cache and verify dependencies without mounting or loading Resources.
## Returns an empty string on success; close()/shutdown() cancel the shared store.
func download_dependencies(keys: Array) -> String:
	if _packs == null or _closed:
		return "Addressables is not configured."
	return await _packs.download_dependencies(keys)


## Describe this registry, not external Resource references, RAM, VRAM or all surviving tokens.
func debug_snapshot() -> Dictionary:
	var owners := 0
	var pending := 0
	for operation in _operations.values():
		owners += operation.owners
		pending += int(operation.threaded)
	return {"operations": _operations.size(), "owners": owners,
		"pending_requests": pending, "threaded_requests": threaded_requests,
		"pending_downloads": _packs._pending.size() if _packs != null else 0}


## Stop acquisitions, invalidate results and cancel HTTP without awaiting engine completion.
## Use shutdown() before deleting the Node when asynchronous draining is required.
func close() -> void:
	if _closed:
		return
	_closed = true
	if _packs != null:
		_packs.close()
	for operation in _operations.values():
		operation.result = null
		operation.status = "failed"
		operation.error = "Addressables owner was closed."
	# Drain threaded jobs in _process before freeing this node (see shutdown()).
	for path in _operations.keys():
		if not _operations[path].threaded:
			_operations.erase(path)


## Close and wait for pending resource/HTTP work; does not queue-free this Node or unmount packs.
func shutdown() -> void:
	close()
	while (not _operations.is_empty() or (_packs != null and (not _packs._pending.is_empty() \
			or _packs.active_hashes > 0))) and is_inside_tree():
		await get_tree().process_frame


## Last-resort synchronous collection can block if the owner is deleted before shutdown.
func _exit_tree() -> void:
	close()
	# ResourceLoader has no cancel API; collect any remaining request before destruction.
	for operation in _operations.values():
		if operation.threaded:
			ResourceLoader.load_threaded_get(operation.path)
	_operations.clear()
