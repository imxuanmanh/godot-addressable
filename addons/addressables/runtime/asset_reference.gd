@tool
class_name AddressableReference
extends Resource
## Lightweight reference shared by the Inspector, content builder and runtime.
## Only key/path/type strings are serialized; the target Resource is not retained.
## Runtime lookup always uses the catalog key; see docs/API.md and CONTENT_FORMAT.md.

## Catalog identity: UID, path, or an application-defined key.
@export var key: String = ""
## Expected native Resource class, such as PackedScene, Texture2D or AudioStream.
@export var expected_type: String = "Resource"
## Authoring path/fallback only; it does not create a heavy Resource dependency.
@export_file var source_path: String = "":
	set(value):
		source_path = value
		if Engine.is_editor_hint() and key.is_empty() and ResourceLoader.exists(value):
			var uid := ResourceLoader.get_resource_uid(value)
			key = ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else value


## Create a new reference, using an existing UID or the path as its key.
## This factory does not reject missing paths; editor callers validate the target first.
static func from_path(path: String) -> AddressableReference:
	var reference := AddressableReference.new()
	reference.source_path = path
	var uid := ResourceLoader.get_resource_uid(path)
	reference.key = ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else path
	return reference


## Prefer the current UID mapping so editor renames are followed.
## Changing source_path alone does not retarget a reference whose UID still resolves.
func resolve_source() -> String:
	if key.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(key)
		if ResourceUID.has_id(uid):
			return ResourceUID.get_id_path(uid)
	return source_path
