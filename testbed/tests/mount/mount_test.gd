extends TestCase
## Pack delivery: download two packs, verify, mount and load them, then check texture decoding.
## Needs an exported build: with the sources present (editor) the packs would collide.

const HERO := "res://assets/mount/hero.tscn"
const BIG := "res://assets/mount/big.png"

var _stage: Node2D


func _init() -> void:
	test_name = "mount"


func _run_test() -> void:
	_check(not FileAccess.file_exists(HERO) and not FileAccess.file_exists(BIG),
		"Exported build does not contain the optional content (run from an export, not the editor)")
	var catalog := TestContent.load_catalog()
	if not _check(not catalog.is_empty(), "Exported catalog is present"):
		return
	_check(catalog.platform == OS.get_name(), "Catalog platform is %s" % catalog.platform)
	var service := Addressables.new()
	add_child(service)
	var issue := service.configure(catalog, TestContent.root(), false, true)
	if not _check(issue.is_empty(), "configure() %s" % issue):
		service.queue_free()
		return
	var keys := [HERO, BIG]

	var started := Time.get_ticks_msec()
	var missing := await service.get_download_size_async(keys)
	await _lap("get_download_size_async (missing %d bytes)" % missing, started)

	started = Time.get_ticks_msec()
	issue = await service.download_dependencies(keys)
	await _lap("download_dependencies", started, ", downloads started %d" % service._packs.downloads_started)
	if not _check(issue.is_empty(), "download_dependencies() %s" % issue):
		await service.shutdown()
		service.queue_free()
		return

	started = Time.get_ticks_msec()
	var hero := service.load_asset(HERO, "PackedScene")
	await hero.wait()
	await _lap("Mount and load hero scene", started)
	if _check(hero.get_result() != null, "Hero scene loaded %s" % hero.error):
		_stage = Node2D.new()
		_stage.position = Vector2(40, 560)
		add_child(_stage)
		var instance: Sprite2D = (hero.get_result() as PackedScene).instantiate()
		instance.centered = false
		_stage.add_child(instance)
		var texture := instance.texture
		_check(texture != null and texture.get_width() == 256,
			"Hero texture is %s" % (texture.get_class() if texture else "missing"))
		var image := texture.get_image() if texture else null
		if image != null and not image.is_empty():
			if image.is_compressed():
				image.decompress()
			var pixel := image.get_pixel(200, 60)
			_say("Pixel (200,60) = %s, expected about (0.78, 0.23)" % pixel)
			_check(absf(pixel.r - 200.0 / 255.0) < 0.1 and absf(pixel.g - 60.0 / 255.0) < 0.1,
				"Hero pixel colors are not corrupted")
		else:
			_say("Pixel read-back unavailable; the picture should show a smooth gradient.")

	started = Time.get_ticks_msec()
	var big := service.load_asset(BIG, "Texture2D")
	await big.wait()
	await _lap("Mount and load big texture", started)
	var big_texture := big.get_result() as Texture2D
	_check(big_texture != null and big_texture.get_width() == 2048, "Big texture loaded %s" % big.error)
	big_texture = null
	big.release()
	hero.release()
	await service.shutdown()
	service.queue_free()
