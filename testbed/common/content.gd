class_name TestContent
extends RefCounted
## Locates the exported catalog and the delivered content for testbed tests.


## Content root: --content=DIR/URL, the adb-reversed PC server on Android, else ./content by the executable.
static func root() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--content="):
			return arg.trim_prefix("--content=")
	if OS.get_name() == "Android":
		return "http://127.0.0.1:8000"
	return OS.get_executable_path().get_base_dir().path_join("content")


## Parse the catalog injected into the export; empty when the build state was missing.
static func load_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://addressables/catalog.json"))
	return parsed if parsed is Dictionary else {}
