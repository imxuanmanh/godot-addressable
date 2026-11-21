extends Control
## Test launcher. Pass --test=NAME (or put NAME in user://autorun) to run one test unattended.

const TESTS := {
	"mount": ["Mount packs (download, verify, mount, load)", "res://tests/mount/mount_test.tscn"],
	"match": ["Match load/release (memory returns to baseline)", "res://tests/match/match_test.tscn"],
}


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var title := Label.new()
	title.text = "Addressables testbed"
	column.add_child(title)
	for test_id in TESTS:
		var button := Button.new()
		button.text = TESTS[test_id][0]
		button.pressed.connect(_open.bind(test_id, false))
		column.add_child(button)
	var requested := _requested_test()
	if requested != "":
		if TESTS.has(requested):
			_open.call_deferred(requested, true)
		else:
			title.text = "Unknown test: %s" % requested


func _open(test_id: String, autorun: bool) -> void:
	if autorun:
		get_tree().root.set_meta("autorun", true)
	get_tree().change_scene_to_file(TESTS[test_id][1])


## Test requested through --test=NAME or the user://autorun marker; the marker is consumed.
func _requested_test() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			return arg.trim_prefix("--test=")
	if FileAccess.file_exists("user://autorun"):
		var requested := FileAccess.get_file_as_string("user://autorun").strip_edges()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://autorun"))
		return requested
	return ""
