@tool
extends EditorInspectorPlugin
## Installs custom editors for reference fields and typed reference arrays.
## ResourceType hints also identify empty C# fields; unrelated properties keep their default editor.

const Property = preload("reference_property.gd")
const ArrayProperty = preload("reference_array_property.gd")


## Inspect any object, replacing only recognized properties in _parse_property().
func _can_handle(_object: Object) -> bool:
	return true


## Return true after installing a custom editor to suppress the default resource picker.
func _parse_property(object: Object, type: Variant.Type, name: String, _hint: PropertyHint,
		hint_string: String, _usage: int, _wide: bool) -> bool:
	if type == TYPE_OBJECT and (hint_string == "AddressableReference" \
			or object.get(name) is AddressableReference):
		add_property_editor(name, Property.new())
		return true
	if type == TYPE_ARRAY and hint_string.contains("AddressableReference"):
		add_property_editor(name, ArrayProperty.new())
		return true
	return false
