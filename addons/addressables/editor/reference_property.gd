@tool
extends EditorProperty
## Inspector widget for one lightweight reference: drop, choose, clear and inspect.
## emit_changed() delegates assignment, undo and serialization to the Godot Inspector.

const Reference = preload("../runtime/asset_reference.gd")
var _button := Button.new()
var _clear := Button.new()
var _inspect := Button.new()
var _dialog: EditorFileDialog


## Build the reference controls and connect drag/drop, selection, clearing and inspection.
func _init() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_button.text = "Drop asset or choose…"
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.clip_text = true
	_button.set_drag_forwarding(Callable(), _can_drop_asset, _drop_asset)
	_button.pressed.connect(_choose)
	row.add_child(_button)
	_clear.text = "×"
	_clear.tooltip_text = "Clear reference"
	_clear.pressed.connect(func(): emit_changed(get_edited_property(), null))
	row.add_child(_clear)
	_inspect.text = "…"
	_inspect.tooltip_text = "Inspect reference key and expected type"
	_inspect.pressed.connect(func():
		var reference = get_edited_object().get(get_edited_property())
		if reference is Reference:
			EditorInterface.edit_resource(reference))
	row.add_child(_inspect)
	add_focusable(_button)
	add_focusable(_clear)


## Prevent reassignment/clearing while still allowing inspection of the reference metadata.
func _set_read_only(value: bool) -> void:
	_button.disabled = value
	_clear.disabled = value


## Display the UID-resolved target name and expose key/path in the tooltip.
func _update_property() -> void:
	var reference = get_edited_object().get(get_edited_property())
	_button.text = reference.resolve_source().get_file() if reference is Reference else "Drop asset or choose…"
	_button.tooltip_text = (reference.key + "\n" + reference.resolve_source()) if reference is Reference else "Stores a lightweight address, not the target resource."


## Revalidate drag data rather than trusting the editor's drag preview.
func _can_drop_asset(_position: Vector2, data: Variant) -> bool:
	var paths := paths_from_drop(data)
	return not _button.disabled and paths.size() == 1 and is_valid_source(paths[0])


## Revalidate the drop and assign its single target through the Inspector's undo flow.
func _drop_asset(_position: Vector2, data: Variant) -> void:
	if _can_drop_asset(Vector2.ZERO, data):
		_assign(paths_from_drop(data)[0])


## Replacing a target creates a new reference, resetting the old custom key/type.
func _assign(path: String) -> void:
	if is_valid_source(path):
		emit_changed(get_edited_property(), Reference.from_path(path))


## Reject code targets; the content builder performs deeper type/dependency validation.
static func is_valid_source(path: String) -> bool:
	return not path.get_extension() in ["gd", "gdc", "cs", "gdextension"] and ResourceLoader.exists(path)


## Normalize file drags or saved Resource drags; subresources are rejected by the builder.
static func paths_from_drop(data: Variant) -> PackedStringArray:
	if data is Dictionary:
		if data.get("type") == "files" and (data.get("files") is PackedStringArray or data.get("files") is Array):
			var result := PackedStringArray()
			for path in data.files:
				if not path is String:
					return PackedStringArray()
				result.append(path)
			return result
		if data.get("type") == "resource" and data.get("resource") is Resource:
			return PackedStringArray([data.resource.resource_path])
	return PackedStringArray()


## Create the file dialog lazily and parent it to this widget for automatic editor cleanup.
func _choose() -> void:
	if _dialog == null:
		_dialog = EditorFileDialog.new()
		_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_dialog.file_selected.connect(_assign)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.65)
