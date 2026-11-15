extends SceneTree
## Headless content-build entry point; import the project before running this script.
## Arguments after --: SETTINGS.tres [OUTPUT]. Exit 0: success, 1: build error, 2: invalid input.

const Builder = preload("content_builder.gd")


## Load AddressablesBuild and convert the builder's result into logs and an exit code.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --headless --path PROJECT --script res://addons/addressables/editor/build_cli.gd -- res://build.tres [OUTPUT]")
		quit(2)
		return
	var settings = ResourceLoader.load(args[0])
	if not settings is AddressablesBuild:
		push_error("Expected a AddressablesBuild resource.")
		quit(2)
		return
	var result: Dictionary = Builder.build(settings, args[1] if args.size() > 1 else "")
	if result.has("error"):
		push_error(result.error)
		quit(1)
	else:
		print("[Addressables] Built ", result.catalog_path)
		quit(0)
