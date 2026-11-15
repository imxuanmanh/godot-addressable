class_name AddressableScope
extends RefCounted
## Owns handles for a scene, feature or preview; release the scope explicitly.
## A scope does not own instantiated nodes, pools or audio players.
## Create through Addressables.create_scope() so the weak service owner is initialized.

var _owner: WeakRef
var _handles: Array = []
var _closed := false


## Acquire and retain a new token; repeated keys still create separate ownership.
## Returns null after scope closure or loss of the service owner.
func acquire(reference: Variant, expected_type: String = "Resource") -> AddressableHandle:
	if _closed or _owner.get_ref() == null:
		return null
	var handle: AddressableHandle = _owner.get_ref().load_asset(reference, expected_type)
	_handles.append(handle)
	return handle


## Start a batch, then await its tokens in order; roll back only the failing batch.
## Previously successful batches remain owned. This is not a fail-fast API.
func load_all(references: Array) -> bool:
	if _closed:
		return false
	var batch: Array = []
	for reference in references:
		var handle := acquire(reference)
		if handle == null:
			return false
		batch.append(handle)
	for handle in batch:
		await handle.wait()
		if handle.get_result() == null:
			for acquired in batch:
				acquired.release()
				_handles.erase(acquired)
			return false
	return true


## Find the first matching token that has not been released; it may still be loading or failed.
## Release a failed manual acquisition before looking up a retry with the same key.
func get_handle(reference: Variant) -> AddressableHandle:
	var key: String = reference.key if reference is AddressableReference else str(reference)
	for handle in _handles:
		if handle.key == key and handle.status != "released":
			return handle
	return null


## Close this scope and release every retained token once; closed scopes cannot be reused.
func release() -> void:
	if _closed:
		return
	_closed = true
	for handle in _handles:
		handle.release()
	_handles.clear()
