@tool
extends RefCounted
## Offline pipeline: resolve references, collect imported dependencies and build PCKs/catalog.
## Does not instantiate scenes, compile application code, upload content or change project.godot.
## Build successfully before exporting the application; see docs/ARCHITECTURE.md.

const Catalog = preload("../runtime/catalog.gd")
## Local export-filter state; never upload this file as a runtime catalog.
const EXPORT_STATE := "res://.godot/addressables/export.json"


## Return {catalog, catalog_path, excluded} on success or {error} on failure.
## Collect dependencies without temporary scene instances; shared files go into __shared.
static func build(settings: AddressablesBuild, output_override: String = "") -> Dictionary:
	if settings == null or settings.groups.is_empty():
		return {"error": "At least one content group is required."}
	var directory := output_override if not output_override.is_empty() else settings.output_directory
	if directory.is_empty() or directory == "res://" or directory == "user://":
		return {"error": "Choose a dedicated output directory."}
	var code := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if code != OK:
		return {"error": "Cannot create output directory: %s" % error_string(code)}
	var assets: Dictionary = {}
	var memberships: Dictionary = {}
	var names: Dictionary = {}
	var base_dependencies: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_-]*$")
	for group in settings.groups:
		if group == null or pattern.search(group.group_name) == null or names.has(group.group_name):
			return {"error": "Group names must be unique safe filenames."}
		names[group.group_name] = true
		if group.assets.is_empty():
			return {"error": "Empty content group: %s" % group.group_name}
		for reference in group.assets:
			if reference == null:
				return {"error": "Null asset reference in %s." % group.group_name}
			var path := reference.resolve_source()
			if reference.key.is_empty() or not Catalog.is_resource_path(path) or not ResourceLoader.exists(path):
				return {"error": "Missing key or source resource: %s" % path}
			if path.get_extension() in ["gd", "gdc", "cs", "gdextension"]:
				return {"error": "Script/code must ship in the base application: %s" % path}
			var resource := ResourceLoader.load(path)
			if resource == null or not resource.is_class(reference.expected_type):
				return {"error": "Reference type does not match: %s" % path}
			if assets.has(reference.key) and assets[reference.key].path != path:
				return {"error": "Duplicate address points to different resources: %s" % reference.key}
			assets[reference.key] = {"path": path, "type": resource.get_class(), "pack": group.group_name}
			var closure: Dictionary = {}
			var issue := _collect(path, closure, base_dependencies)
			if not issue.is_empty():
				return {"error": issue}
			for file in closure:
				if not memberships.has(file):
					memberships[file] = {}
				memberships[file][group.group_name] = true
	var buckets: Dictionary = {}
	var needs_shared: Dictionary = {}
	for file in memberships:
		var members: Dictionary = memberships[file]
		var bucket: String = "__shared" if members.size() > 1 else str(members.keys()[0])
		if not buckets.has(bucket):
			buckets[bucket] = []
		buckets[bucket].append(file)
		if bucket == "__shared":
			for member in members:
				needs_shared[member] = true
	for key in assets:
		if memberships[assets[key].path].size() > 1:
			assets[key].pack = "__shared"
	var packs: Dictionary = {}
	for bucket in buckets:
		var files: Array = buckets[bucket]
		files.sort()
		var temporary := directory.path_join(bucket + ".pck.part")
		var packer := PCKPacker.new()
		code = packer.pck_start(temporary)
		if code != OK:
			return {"error": "Cannot create PCK: %s" % error_string(code)}
		for file in files:
			code = packer.add_file(file, file)
			if code != OK:
				return {"error": "Cannot pack %s: %s" % [file, error_string(code)]}
		code = packer.flush()
		if code != OK:
			return {"error": "Cannot flush PCK: %s" % error_string(code)}
		var hash_value := FileAccess.get_sha256(temporary)
		var filename: String = bucket + "-" + hash_value + ".pck"
		var final_path := directory.path_join(filename)
		if FileAccess.file_exists(final_path):
			DirAccess.remove_absolute(temporary)
		else:
			code = DirAccess.rename_absolute(temporary, final_path)
			if code != OK:
				return {"error": "Cannot commit PCK: %s" % error_string(code)}
		var dependencies: Array = ["__shared"] if bucket != "__shared" and needs_shared.has(bucket) else []
		packs[bucket] = {"file": filename, "sha256": hash_value,
			"size": FileAccess.open(final_path, FileAccess.READ).get_length(),
			"dependencies": dependencies, "files": files}
	var engine := Engine.get_version_info()
	var catalog := {"schema_version": 1, "engine": "%s.%s" % [engine.major, engine.minor],
		"platform": settings.target_platform, "assets": assets, "packs": packs,
		"base_dependencies": base_dependencies.keys()}
	# Validate host-independent structure; the runtime checks the selected target platform.
	var host_validation := catalog.duplicate(true)
	host_validation.platform = OS.get_name()
	var issue := Catalog.validate(host_validation)
	if not issue.is_empty():
		return {"error": issue}
	var catalog_path := directory.path_join("catalog.json")
	issue = _write_json(catalog_path, catalog)
	if not issue.is_empty():
		return {"error": issue}
	var excluded: Array = memberships.keys()
	if not settings.resource_path.is_empty():
		excluded.append(settings.resource_path)
	var hashes: Dictionary = {}
	for source in memberships:
		hashes[source] = FileAccess.get_sha256(source)
	if not settings.resource_path.is_empty():
		hashes[settings.resource_path] = FileAccess.get_sha256(settings.resource_path)
	for group in settings.groups:
		var group_path := group.resource_path.get_slice("::", 0)
		if not group_path.is_empty():
			hashes[group_path] = FileAccess.get_sha256(group_path)
			if not group_path in excluded:
				excluded.append(group_path)
	for id in packs:
		excluded.append(directory.path_join(packs[id].file))
	excluded.append(catalog_path)
	issue = _write_json(EXPORT_STATE, {"excluded": excluded, "catalog_path": catalog_path,
		"catalog_sha256": FileAccess.get_sha256(catalog_path), "source_hashes": hashes,
		"output_directory": directory})
	if not issue.is_empty():
		return {"error": issue}
	return {"catalog": catalog, "catalog_path": catalog_path, "excluded": excluded}


## Collect source/import/remap files while leaving executable scripts in the base application.
static func _collect(path: String, found: Dictionary, base_dependencies: Dictionary) -> String:
	if found.has(path):
		return ""
	if path.begins_with("res://addons/addressables/editor/"):
		return "Editor-only resource cannot be packed: %s" % path
	if path.get_extension() in ["gd", "gdc", "cs", "gdextension"]:
		base_dependencies[path] = true
		return ""
	if not FileAccess.file_exists(path):
		return "Dependency is missing: %s" % path
	found[path] = true
	if FileAccess.file_exists(path + ".import"):
		found[path + ".import"] = true
		var remap := ConfigFile.new()
		if remap.load(path + ".import") != OK:
			return "Cannot read import remap: %s" % path
		for key in remap.get_section_keys("remap"):
			if key == "path" or key.begins_with("path."):
				var imported: String = remap.get_value("remap", key)
				if not FileAccess.file_exists(imported):
					return "Import the resource before building: %s" % path
				found[imported] = true
	for dependency in ResourceLoader.get_dependencies(path):
		var parts := dependency.split("::")
		var dependency_path: String = parts[parts.size() - 1]
		# Prefer UID mappings when a scene still contains a stale fallback path after a rename.
		var uid_text: String = parts[0] if parts[0].begins_with("uid://") else dependency_path
		if uid_text.begins_with("uid://"):
			var uid := ResourceUID.text_to_id(uid_text)
			if ResourceUID.has_id(uid):
				dependency_path = ResourceUID.get_id_path(uid)
			elif dependency_path.begins_with("uid://"):
				return "Unresolved dependency UID: %s" % dependency_path
		var issue := _collect(dependency_path, found, base_dependencies)
		if not issue.is_empty():
			return issue
	return ""


## Commit one metadata file via .part/rename, not a transaction for the whole content build.
static func _write_json(path: String, value: Dictionary) -> String:
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Cannot create metadata directory."
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	if file == null:
		return "Cannot write metadata: %s" % path
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	var code := DirAccess.rename_absolute(path + ".part", path)
	return "" if code == OK else "Cannot commit metadata: %s" % error_string(code)
