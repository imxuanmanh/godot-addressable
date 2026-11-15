@tool
extends EditorProperty
## Inspector widget for AddressableGroup.assets, including multi-file selection.
## Emits a replacement typed array instead of mutating the Inspector-owned collection.

const Reference = preload("../runtime/asset_reference.gd")
const Single = preload("reference_property.gd")
var _list := ItemList.new()
var _add := Button.new()
var _remove := Button.new()
var _dialog: EditorFileDialog


func _init() -> void:
	var column := VBoxContainer.new()
	add_child(column)
	_list.custom_minimum_size.y = 96
	_list.set_drag_forwarding(Callable(), _can_drop_assets, _drop_assets)
	column.add_child(_list)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add.text = "Add / drop assets"
	_add.pressed.connect(_choose)
	row.add_child(_add)
	_remove.text = "Remove selected"
	_remove.pressed.connect(_remove_selected)
	row.add_child(_remove)
	add_focusable(_list)
	add_focusable(_add)
	add_focusable(_remove)


func _set_read_only(value: bool) -> void:
	_add.disabled = value
	_remove.disabled = value


## Render the owner's collection, including null entries that can be selected and removed.
func _update_property() -> void:
	_list.clear()
	for reference in get_edited_object().get(get_edited_property()):
		var index := _list.add_item(reference.resolve_source().get_file() if reference != null else "<Missing reference>")
		if reference != null:
			_list.set_item_tooltip(index, reference.key + "\n" + reference.resolve_source())


## Accept a drop only when every target is supported and the property is writable.
func _can_drop_assets(_position: Vector2, data: Variant) -> bool:
	var paths := Single.paths_from_drop(data)
	return not _add.disabled and not paths.is_empty() and Array(paths).all(Single.is_valid_source)


func _drop_assets(_position: Vector2, data: Variant) -> void:
	if _can_drop_assets(Vector2.ZERO, data):
		_add_paths(Single.paths_from_drop(data))


## Deduplicate by key, not by path; distinct aliases of one target may coexist.
func _add_paths(paths: PackedStringArray) -> void:
	var references: Array[AddressableReference] = []
	references.assign(get_edited_object().get(get_edited_property()))
	for path in paths:
		if not Single.is_valid_source(path):
			continue
		var reference := Reference.from_path(path)
		if not references.any(func(existing): return existing != null and existing.key == reference.key):
			references.append(reference)
	emit_changed(get_edited_property(), references)


## Remove a reference from the group without deleting its target or cache file.
func _remove_selected() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	var references: Array[AddressableReference] = []
	references.assign(get_edited_object().get(get_edited_property()))
	references.remove_at(selected[0])
	emit_changed(get_edited_property(), references)


## Route multi-file selection through the same path as drag/drop.
func _choose() -> void:
	if _dialog == null:
		_dialog = EditorFileDialog.new()
		_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
		_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_dialog.files_selected.connect(_add_paths)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.65)
