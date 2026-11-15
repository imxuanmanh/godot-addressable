class_name AddressableHandle
extends RefCounted
## One acquisition token returned by Addressables.load_asset().
## Handles can share an operation; the weak owner does not extend the service lifetime.
## Release explicitly; pre-delete cleanup is a best-effort fallback, not a timing guarantee.

var _owner: WeakRef
var _operation: RefCounted
var _released := false
var _expected_type := "Resource"
## Acquisition key used for diagnostics and scope lookup; do not mutate after acquisition.
var key := ""

## Terminal status includes failure/release; this is not a success flag.
var is_done: bool:
	get:
		return _released or _operation == null or _operation.status != "loading"
## loading, succeeded, failed or released; type mismatch affects this token only.
var status: String:
	get:
		if _released:
			return "released"
		return "failed" if _operation.status == "succeeded" and not _matches_type() else _operation.status
## Operation/type error, or a dedicated message after release.
var error: String:
	get:
		if _released:
			return "Handle has been released."
		if _operation.status == "succeeded" and not _matches_type():
			return "Expected %s, got %s." % [_expected_type, _operation.result.get_class()]
		return _operation.error
## ResourceLoader progress, not download bytes; terminal states always report 1.0.
var progress: float:
	get:
		return 1.0 if is_done else _operation.progress


## Check native engine inheritance; custom script types need an additional caller-side check.
func _matches_type() -> bool:
	return _operation.result != null and _operation.result.is_class(_expected_type)


## Borrow a usable, correctly typed Resource; return null for loading/failed/released tokens.
func get_result() -> Resource:
	if _released or _operation == null or _operation.status != "succeeded":
		return null
	return _operation.result if _matches_type() else null


## Yield by frame and return this handle, including on failure.
## Inspect the result/error and release the token on both success and failure paths.
func wait() -> AddressableHandle:
	while not is_done:
		var owner = _owner.get_ref()
		if owner == null or not owner.is_inside_tree():
			release()
			break
		await owner.get_tree().process_frame
	return self


## Return forgotten ownership when the token is destroyed; prefer deterministic release().
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _released:
		# Avoid calling self methods while its script instance is being destroyed.
		var owner = _owner.get_ref() if _owner != null else null
		if owner != null and _operation != null:
			owner._release(_operation)


## Idempotently release only this token, without canceling other consumers.
## Does not delete disk cache, unmount packs or force-free shared Resources.
func release() -> void:
	if _released:
		return
	_released = true
	var owner = _owner.get_ref() if _owner != null else null
	if owner != null:
		owner._release(_operation)
	_operation = null
