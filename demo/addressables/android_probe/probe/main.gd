extends Control
## On-device probe: loads packed content from a PC-hosted server and reports results on screen.
## Results are also printed to logcat and saved to user://probe.log.
## Automation: create user://autorun (adb run-as ... touch files/autorun) or pass --autorun
## to run once without tapping; the app then quits.

const CONTENT_ROOT := "http://127.0.0.1:8000"
const HERO := "res://probe/assets/hero.tscn"
const BIG := "res://probe/assets/big.png"

var _output: RichTextLabel
var _run_button: Button
var _stage: Node2D
var _checks := 0
var _failures := 0
var _measuring := false
var _worst_frame_ms := 0.0
var _ran_before := false


func _ready() -> void:
	get_window().content_scale_factor = clampf(DisplayServer.screen_get_dpi() / 160.0, 1.0, 4.0)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_run_button = Button.new()
	_run_button.text = "Run probe"
	_run_button.pressed.connect(_run)
	row.add_child(_run_button)
	var clear := Button.new()
	clear.text = "Clear cache and quit"
	clear.pressed.connect(_clear_cache_and_quit)
	row.add_child(clear)
	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	column.add_child(_output)
	_stage = Node2D.new()
	add_child(_stage)
	_say("Ready. Start the PC server, run 'adb reverse tcp:8000 tcp:8000', then press Run probe.")
	var marker := FileAccess.file_exists("user://autorun")
	if marker:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://autorun"))
	if marker or "--autorun" in OS.get_cmdline_user_args():
		await _run()
		get_tree().quit(1 if _failures > 0 else 0)


func _process(delta: float) -> void:
	if _measuring:
		_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)


func _say(text: String) -> void:
	print("[probe] ", text)
	_output.append_text(text + "\n")
	var log := FileAccess.open("user://probe.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://probe.log") else FileAccess.WRITE)
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


func _clear_cache_and_quit() -> void:
	var directory := DirAccess.open("user://addressables")
	if directory != null:
		for file in directory.get_files():
			directory.remove(file)
	get_tree().quit()


func _finish() -> void:
	_measuring = false
	var verdict := "PASS" if _failures == 0 else "FAIL"
	_say("PROBE RESULT: %s (%d checks, %d failed)" % [verdict, _checks, _failures])
	_run_button.disabled = false
	_ran_before = true


func _run() -> void:
	_run_button.disabled = true
	_checks = 0
	_failures = 0
	_say("--- run ---")
	_say("OS %s, Godot %s, renderer %s" % [OS.get_name(), Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method()])
	_say("GPU: %s" % RenderingServer.get_video_adapter_name())
	if not _ran_before:
		_check(not FileAccess.file_exists(HERO) and not FileAccess.file_exists(BIG),
			"APK does not contain the optional content")
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://addressables/catalog.json"))
	if not _check(catalog is Dictionary, "Exported catalog is present in the APK"):
		_finish()
		return
	_check(catalog.platform == OS.get_name(), "Catalog platform is %s" % catalog.platform)
	var service := Addressables.new()
	add_child(service)
	var issue := service.configure(catalog, CONTENT_ROOT, false, true)
	if not _check(issue.is_empty(), "configure() %s" % issue):
		service.queue_free()
		_finish()
		return
	var keys := [HERO, BIG]
	# Let startup and UI-building hitches pass so they do not count as stalls of the first stage.
	for _frame in 5:
		await get_tree().process_frame
	_worst_frame_ms = 0.0
	_measuring = true
	var started := Time.get_ticks_msec()
	var missing: int
	var size_call := "get_download_size_async" if service.has_method("get_download_size_async") else "get_download_size"
	if size_call == "get_download_size_async":
		missing = await service.get_download_size_async(keys)
	else:
		missing = service.get_download_size(keys)
	await _lap("%s (missing %d bytes)" % [size_call, missing], started)

	started = Time.get_ticks_msec()
	issue = await service.download_dependencies(keys)
	await _lap("download_dependencies", started, ", downloads started %d" % service._packs.downloads_started)
	if not _check(issue.is_empty(), "download_dependencies() %s" % issue):
		_measuring = false
		await service.shutdown()
		service.queue_free()
		_finish()
		return

	started = Time.get_ticks_msec()
	var hero := service.load_asset(HERO, "PackedScene")
	await hero.wait()
	await _lap("Mount and load hero scene", started)
	if _check(hero.get_result() != null, "Hero scene loaded %s" % hero.error):
		var instance: Sprite2D = (hero.get_result() as PackedScene).instantiate()
		_stage.position = Vector2(40, 40)
		_stage.add_child(instance)
		instance.centered = false
		instance.scale = Vector2(0.5, 0.5)
		var texture := instance.texture
		_check(texture != null and texture.get_width() == 256, "Hero texture is %s" % (texture.get_class() if texture else "missing"))
		var image := texture.get_image() if texture else null
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			var pixel := image.get_pixel(200, 60)
			_say("Pixel (200,60) = %s, expected about (0.78, 0.23)" % pixel)
			_check(absf(pixel.r - 200.0 / 255.0) < 0.1 and absf(pixel.g - 60.0 / 255.0) < 0.1,
				"Hero pixel colors are not corrupted")
		else:
			_say("Pixel read-back unavailable; confirm the picture on screen shows a smooth gradient.")

	started = Time.get_ticks_msec()
	var big := service.load_asset(BIG, "Texture2D")
	await big.wait()
	await _lap("Mount and load big texture", started)
	var big_texture := big.get_result() as Texture2D
	_check(big_texture != null and big_texture.get_width() == 2048, "Big texture loaded %s" % big.error)
	big_texture = null
	big.release()
	hero.release()
	_measuring = false
	await service.shutdown()
	service.queue_free()
	_finish()
