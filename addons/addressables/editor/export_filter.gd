@tool
extends EditorExportPlugin
## Excludes optional content/editor/tests and injects the catalog into application exports.
## Without build state, optional assets are not inferred or excluded.
## Use export_cli.py in CI: Godot may return exit code zero after logging an export error.

const Builder = preload("content_builder.gd")
var _excluded: Dictionary = {}
var _output_directory := ""


## Identify this export hook independently of content group names.
func _get_name() -> String:
	return "AddressablesExport"


## Read build state, inject the catalog and report stale source/config hashes.
## An export error does not guarantee native CLI failure; publishing must check the wrapper exit code.
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_excluded.clear()
	_output_directory = ""
	if not FileAccess.file_exists(Builder.EXPORT_STATE):
		return
	var state = JSON.parse_string(FileAccess.get_file_as_string(Builder.EXPORT_STATE))
	if not state is Dictionary or not FileAccess.file_exists(state.get("catalog_path", "")) \
			or FileAccess.get_sha256(state.catalog_path) != state.get("catalog_sha256", ""):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR,
			"Addressables", "Build metadata is stale. Rebuild addressable content before exporting.")
		return
	for path in state.excluded:
		_excluded[path] = true
	_output_directory = state.output_directory
	add_file("res://addressables/catalog.json", FileAccess.get_file_as_bytes(state.catalog_path), false)
	for source in state.get("source_hashes", {}):
		if FileAccess.get_sha256(source) != state.source_hashes[source]:
			# shortcut: Godot 4.6 may exit 0 after export errors, CI must use export_cli.py.
			get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR,
				"Addressables", "Content changed after building: %s. Rebuild content before exporting." % source)
			return


## Exclude files from this export only; skip() never deletes source or PCK files.
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _excluded.has(path) or path.begins_with("res://addons/addressables/editor/") \
			or path.begins_with("res://addons/addressables/tests/") \
			or (not _output_directory.is_empty() and path.begins_with(_output_directory.trim_suffix("/") + "/")):
		skip()
