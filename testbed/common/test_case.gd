class_name TestCase
extends Control
## Base for testbed tests: on-screen report, check counters, frame-stall sampling and autorun.
## Subclasses set test_name in _init() and implement _run_test(); they must not override _ready().
## Autorun (set by the menu) quits the app when the test ends: exit code 0 pass, 1 fail.

var test_name := "test"
var _output: RichTextLabel
var _run_button: Button
var _checks := 0
var _failures := 0
var _measuring := false
var _worst_frame_ms := 0.0


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_run_button = Button.new()
	_run_button.text = "Run %s" % test_name
	_run_button.pressed.connect(_start)
	row.add_child(_run_button)
	var back := Button.new()
	back.text = "Menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://menu/main.tscn"))
	row.add_child(back)
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	column.add_child(_output)
	_say("Ready: %s. Press the run button." % test_name)
	if get_tree().root.has_meta("autorun"):
		await _start()
		get_tree().quit(1 if _failures > 0 else 0)


func _process(delta: float) -> void:
	if _measuring:
		_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)


## Implemented by each test; use _check() and _lap() to report.
func _run_test() -> void:
	pass


func _start() -> void:
	_run_button.disabled = true
	_checks = 0
	_failures = 0
	_say("--- run %s ---" % test_name)
	_say("OS %s, Godot %s, renderer %s" % [OS.get_name(), Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method()])
	_say("GPU: %s" % RenderingServer.get_video_adapter_name())
	# Let startup and scene-change hitches pass so they do not count as the first stage's stall.
	for _frame in 5:
		await get_tree().process_frame
	_worst_frame_ms = 0.0
	_measuring = true
	await _run_test()
	_measuring = false
	_say("TEST RESULT %s: %s (%d checks, %d failed)" % [test_name,
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	_run_button.disabled = false


func _say(text: String) -> void:
	print("[%s] %s" % [test_name, text])
	if _output != null:
		_output.append_text(text + "\n")
	var path := "user://%s.log" % test_name
	var log := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if log != null:
		log.seek_end()
		log.store_line(text)


func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
	_say("%s  %s" % ["OK  " if condition else "FAIL", label])
	return condition


## Report a stage after two frames so a stall inside the stage is already in the frame samples.
func _lap(label: String, started: int, extra: String = "") -> void:
	var elapsed := Time.get_ticks_msec() - started
	await get_tree().process_frame
	await get_tree().process_frame
	_say("%s: %d ms, worst frame %.0f ms%s" % [label, elapsed, _worst_frame_ms, extra])
	_worst_frame_ms = 0.0
