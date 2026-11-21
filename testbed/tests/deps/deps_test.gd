extends TestCase
## What the builder bundles and what the runtime loads, by kind of reference:
## A) a direct dependency (scene instances bullet A), B) an AddressableReference whose target is
## a catalog root, C) an AddressableReference whose target is not in any group.

const DIR := "res://assets/deps/"
const DIRECT := DIR + "skin_direct.tscn"
const REF_LISTED := DIR + "skin_ref_listed.tscn"
const REF_UNLISTED := DIR + "skin_ref_unlisted.tscn"
const BULLET_A := DIR + "bullet_a.tscn"
const BULLET_B := DIR + "bullet_b.tscn"
const BULLET_C := DIR + "bullet_c.tscn"


func _init() -> void:
	test_name = "deps"


## Wait until deferred frees and cache cleanup have run.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


## Load a skin scene through the service and return its handle after completion.
func _load(service: Addressables, key: String) -> AddressableHandle:
	var handle := service.load_asset(key, "PackedScene")
	await handle.wait()
	return handle


func _check_catalog(catalog: Dictionary) -> void:
	var assets: Dictionary = catalog.assets
	var packs: Dictionary = catalog.packs
	for key in [DIRECT, REF_LISTED, BULLET_B, REF_UNLISTED]:
		_check(assets.has(key), "catalog has root %s" % key.get_file())
	_check(not assets.has(BULLET_A), "a direct dependency is not a catalog address")
	_check(not assets.has(BULLET_C), "an unlisted reference target is not a catalog address")
	var direct_files: Array = packs[assets[DIRECT].pack].files
	_check(BULLET_A in direct_files, "direct dependency travels in its parent's pack")
	var listed_files: Array = packs[assets[REF_LISTED].pack].files
	_check(not BULLET_B in listed_files, "reference target is not pulled into the referencing pack")
	_check(assets[BULLET_B].pack != assets[REF_LISTED].pack, "listed reference target has its own pack")
	var in_any_pack := false
	for pack in packs.values():
		in_any_pack = in_any_pack or BULLET_C in pack.files
	_check(not in_any_pack, "unlisted reference target is in no pack")
	# Nothing was mounted yet, so existence reflects exactly what the base export contains.
	_check(not ResourceLoader.exists(BULLET_A), "direct dependency is absent from the base export")
	_check(not ResourceLoader.exists(BULLET_B), "listed target is absent from the base export")
	_check(ResourceLoader.exists(BULLET_C), "unlisted target stayed in the base export")


func _run_test() -> void:
	var catalog := TestContent.load_catalog()
	if not _check(not catalog.is_empty(), "Exported catalog is present"):
		return
	_check_catalog(catalog)
	var service := Addressables.new()
	add_child(service)
	var issue := service.configure(catalog, TestContent.root(), false, true)
	if not _check(issue.is_empty(), "configure() %s" % issue):
		service.queue_free()
		return

	# A) Direct dependency: loaded with its parent, freed with it.
	var direct := await _load(service, DIRECT)
	if _check(direct.get_result() != null, "A: skin with a direct dependency loads %s" % direct.error):
		_check(ResourceLoader.has_cached(BULLET_A), "A: direct dependency is loaded together with the skin")
	direct.release()
	await _settle()
	_check(not ResourceLoader.has_cached(BULLET_A), "A: direct dependency is freed with the skin")

	# B) Listed reference: the skin loads without its bullet; the bullet loads on demand.
	var listed := await _load(service, REF_LISTED)
	if _check(listed.get_result() != null, "B: skin with a reference loads %s" % listed.error):
		var node: Node = (listed.get_result() as PackedScene).instantiate()
		var reference := node.get("bullet") as AddressableReference
		_check(reference != null and reference.key == BULLET_B, "B: the skin carries a reference to its bullet")
		_check(not ResourceLoader.has_cached(BULLET_B), "B: the bullet is not loaded with the skin")
		var bullet := service.load_asset(reference)
		await bullet.wait()
		_check(bullet.get_result() != null and ResourceLoader.has_cached(BULLET_B),
			"B: the bullet loads on demand %s" % bullet.error)
		bullet.release()
		node.free()
	listed.release()
	await _settle()
	_check(not ResourceLoader.has_cached(BULLET_B), "B: the bullet is freed after its handle is released")

	# C) Unlisted reference: the key is unknown to the catalog, so the addon cannot load it.
	var unlisted := await _load(service, REF_UNLISTED)
	if _check(unlisted.get_result() != null, "C: skin with an unlisted reference loads %s" % unlisted.error):
		var node: Node = (unlisted.get_result() as PackedScene).instantiate()
		var reference := node.get("bullet") as AddressableReference
		var missing := service.load_asset(reference)
		await missing.wait()
		_check(missing.status == "failed" and missing.error.begins_with("Unknown address"),
			"C: loading the unlisted target by key fails (%s)" % missing.error)
		missing.release()
		node.free()
	unlisted.release()
	await _settle()
	var snapshot := service.debug_snapshot()
	_check(snapshot.owners == 0 and snapshot.operations == 0, "service has no owners or operations left")
	await service.shutdown()
	service.queue_free()
