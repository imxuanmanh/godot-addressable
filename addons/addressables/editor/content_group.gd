@tool
class_name AddressableGroup
extends Resource
## Editor authoring metadata for a content group, not a runtime ownership scope.
## Shared dependencies may be extracted, so a group need not map to a self-contained PCK.

## Unique per build; use safe alphanumeric/underscore/hyphen names. __shared is reserved.
@export var group_name := "default"
## Explicit roots; Resource dependencies are collected automatically.
@export var assets: Array[AddressableReference] = []
