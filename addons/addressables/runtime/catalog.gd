extends RefCounted
## Schema-v1 metadata validator shared by the builder and runtime.
## This internal script has no global class name; tooling may preload it explicitly.
## Checks metadata without loading assets; hashes do not authenticate an untrusted catalog.


## Accept normalized res:// paths without traversal, backslashes or subresource syntax.
static func is_resource_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("\\") and not path.contains("::") \
		and path == path.simplify_path() and not path.trim_prefix("res://").is_empty()


## Return an empty string or the first metadata issue; do not mutate data or inspect PCK contents.
## Missing engine/platform values default to the host; generated catalogs specify both.
static func validate(data: Dictionary) -> String:
	if data.get("schema_version") != 1 or not data.get("assets") is Dictionary \
			or not data.get("packs") is Dictionary:
		return "Invalid catalog schema."
	var current := Engine.get_version_info()
	var engine: Variant = data.get("engine", "%s.%s" % [current.major, current.minor])
	if not engine is String:
		return "Invalid catalog engine version; expected major.minor."
	var version: PackedStringArray = engine.split(".")
	if version.size() != 2 or not version[0].is_valid_int() or not version[1].is_valid_int() \
			or str(version[0].to_int()) != version[0] or str(version[1].to_int()) != version[1] \
			or version[0].to_int() < 0 or version[1].to_int() < 0:
		return "Invalid catalog engine version; expected major.minor."
	if version[0].to_int() != current.major:
		return "Content was built for a different Godot major version."
	# Newer readers may load older content; the native loader still validates PCK/resource formats.
	if version[1].to_int() > current.minor:
		return "Content requires Godot %s or newer." % engine
	if data.get("platform", OS.get_name()) != OS.get_name():
		return "Content was built for a different platform."
	for key in data.assets:
		var entry = data.assets[key]
		if not (key is String or key is StringName) or key.is_empty() or not entry is Dictionary:
			return "Invalid address entry."
		if not entry.get("path") is String or not is_resource_path(entry.path):
			return "Invalid resource path: %s" % key
		if not entry.get("type", "Resource") is String \
				or not ClassDB.is_parent_class(entry.get("type", "Resource"), "Resource"):
			return "Invalid resource type: %s" % key
		if not entry.get("pack", "") is String or (not entry.get("pack", "").is_empty() \
				and not data.packs.has(entry.pack)):
			return "Unknown asset pack: %s" % key
	for id in data.packs:
		var pack = data.packs[id]
		if not (id is String or id is StringName) or not pack is Dictionary:
			return "Invalid pack entry."
		var hash_value = pack.get("sha256", "")
		if not hash_value is String or hash_value.length() != 64 or not hash_value.is_valid_hex_number():
			return "Invalid pack SHA-256: %s" % id
		var file = pack.get("file", "")
		if not file is String or file != file.get_file() or not file.ends_with(".pck") or file.contains(".."):
			return "Invalid pack filename: %s" % id
		var size = pack.get("size", 0)
		if not (size is int or size is float) or size <= 0 or size != floor(size) or size > 2147483647:
			return "Invalid pack size: %s" % id
		if not pack.get("dependencies", []) is Array or not pack.get("files", []) is Array:
			return "Invalid pack dependencies/files: %s" % id
		for path in pack.get("files", []):
			if not path is String or not is_resource_path(path):
				return "Invalid packed resource path: %s" % id
		for dependency in pack.get("dependencies", []):
			if not dependency is String or not data.packs.has(dependency):
				return "Missing pack dependency: %s" % id
	for key in data.assets:
		var entry: Dictionary = data.assets[key]
		if not entry.get("pack", "").is_empty() and not entry.path in data.packs[entry.pack].get("files", []):
			return "Asset is not declared in its pack: %s" % key
	for id in data.packs:
		var issue := _visit(id, data.packs, {}, {})
		if not issue.is_empty():
			return issue
	return ""


## Reject cycles or excessive dependency depth before any pack download.
static func _visit(id: String, packs: Dictionary, visiting: Dictionary, done: Dictionary) -> String:
	if visiting.size() > 128:
		return "Pack dependency graph is too deep."
	if visiting.has(id):
		return "Cyclic pack dependency: %s" % id
	if done.has(id):
		return ""
	visiting[id] = true
	for dependency in packs[id].get("dependencies", []):
		var issue := _visit(dependency, packs, visiting, done)
		if not issue.is_empty():
			return issue
	visiting.erase(id)
	done[id] = true
	return ""
