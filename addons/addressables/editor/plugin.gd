@tool
extends EditorPlugin
## Editor-only entry point loaded from plugin.cfg when the addon is enabled.
## Registers Inspector widgets, the export filter and a Tools menu; creates no runtime service.

const Inspector = preload("inspector.gd")
const Builder = preload("content_builder.gd")
const ExportFilter = preload("export_filter.gd")
var _inspector: EditorInspectorPlugin
var _export_filter: EditorExportPlugin


## Retain hook instances so disabling/reloading can unregister the exact same objects.
func _enter_tree() -> void:
	_inspector = Inspector.new()
	add_inspector_plugin(_inspector)
	_export_filter = ExportFilter.new()
	add_export_plugin(_export_filter)
	add_tool_menu_item("Build selected Addressable Content", _build_selected)


## Remove menus and hooks to avoid duplicate registrations after re-enabling the addon.
func _exit_tree() -> void:
	remove_tool_menu_item("Build selected Addressable Content")
	remove_inspector_plugin(_inspector)
	remove_export_plugin(_export_filter)


## Save/build the inspected settings resource and refresh the FileSystem after success.
## Unsaved settings can build, but have no stable settings file for stale-build detection.
func _build_selected() -> void:
	var settings = EditorInterface.get_inspector().get_edited_object()
	if not settings is AddressablesBuild:
		push_error("Select a AddressablesBuild resource in the Inspector first.")
		return
	if not settings.resource_path.is_empty() and ResourceSaver.save(settings) != OK:
		push_error("Save the build settings before building content.")
		return
	var result: Dictionary = Builder.build(settings)
	if result.has("error"):
		push_error(result.error)
	else:
		print("[Addressables] Built catalog: ", result.catalog_path)
		EditorInterface.get_resource_filesystem().scan()
