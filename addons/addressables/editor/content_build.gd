@tool
class_name AddressablesBuild
extends Resource
## Content-build settings used by the Tools menu and build_cli.gd.
## Save as a .tres resource; the target platform is metadata, not an import conversion step.

## At least one non-empty group with a unique name is required.
@export var groups: Array[AddressableGroup] = []
## Dedicated build output; avoid existing manually maintained files with matching names.
@export_dir var output_directory := "res://addressable_content"
## Prepare target-specific imports first; the runtime checks this platform metadata.
@export_enum("Windows", "Linux", "macOS", "Android", "iOS") var target_platform := OS.get_name()
