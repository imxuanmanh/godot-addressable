extends TestCase
## Simulated matches: load a set of skins, show them, release, and verify memory returns to baseline.
## Also shows two limits: textures stay while instances use them, and shared assets live until the last owner.

const SKIN_COUNT := 8
const MB := 1048576.0
const RESOURCE_SLACK := 3
const TEXTURE_SLACK_MB := 0.5
## A 1024x1024 VRAM-compressed texture takes at least this much.
const MIN_GROWTH_MB := 0.25


func _init() -> void:
	test_name = "match"


func _key(index: int) -> String:
	return "res://assets/skins/skin_%d.tscn" % index


## Sample after letting deferred frees run, so a queue_free() is already reflected.
func _sample(label: String) -> Dictionary:
	for _frame in 3:
		await get_tree().process_frame
	var sample := {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / MB,
		"texture_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / MB,
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
	_say("%s | static %.1f MB | textures %.1f MB | resources %d | nodes %d" % [label,
		sample.static_mb, sample.texture_mb, sample.resources, sample.nodes])
	return sample


## One match: load skins, instantiate them, release the scope, then free the instances.
func _play(service: Addressables, indices: Array, base: Dictionary, label: String) -> void:
	var keys: Array = []
	for index in indices:
		keys.append(_key(index))
	var scope := service.create_scope()
	if not _check(await scope.load_all(keys), "%s: load_all succeeds" % label):
		scope.release()
		return
	var loaded := await _sample("%s: skins loaded" % label)
	_check(loaded.resources >= base.resources + indices.size(), "%s: resource count grows" % label)
	_check(loaded.texture_mb >= base.texture_mb + indices.size() * MIN_GROWTH_MB, "%s: texture memory grows" % label)
	var holder := Node2D.new()
	add_child(holder)
	for key in keys:
		holder.add_child((scope.get_handle(key).get_result() as PackedScene).instantiate())
	await _sample("%s: skins instantiated" % label)
	scope.release()
	var kept := await _sample("%s: scope released, instances alive" % label)
	_check(kept.texture_mb >= loaded.texture_mb - TEXTURE_SLACK_MB,
		"%s: textures stay while instances use them" % label)
	holder.queue_free()
	var freed := await _sample("%s: instances freed" % label)
	_check(freed.resources <= base.resources + RESOURCE_SLACK,
		"%s: resource count back to baseline (%d vs %d)" % [label, freed.resources, base.resources])
	_check(freed.texture_mb <= base.texture_mb + TEXTURE_SLACK_MB,
		"%s: texture memory back to baseline (%.1f vs %.1f MB)" % [label, freed.texture_mb, base.texture_mb])


func _run_test() -> void:
	var catalog := TestContent.load_catalog()
	if not _check(not catalog.is_empty(), "Exported catalog is present"):
		return
	var service := Addressables.new()
	add_child(service)
	var issue := service.configure(catalog, TestContent.root(), false, true)
	if not _check(issue.is_empty(), "configure() %s" % issue):
		service.queue_free()
		return
	var all_keys: Array = []
	for index in SKIN_COUNT:
		all_keys.append(_key(index))
	issue = await service.download_dependencies(all_keys)
	if not _check(issue.is_empty(), "download all skin packs %s" % issue):
		await service.shutdown()
		service.queue_free()
		return
	# Warm-up mounts every pack and runs one full cycle, so the baseline excludes first-use costs.
	var warm := service.create_scope()
	await warm.load_all(all_keys)
	warm.release()
	var base := await _sample("baseline (packs mounted, nothing loaded)")

	await _play(service, [0, 1, 2], base, "match 1")
	await _play(service, [3, 4, 5], base, "match 2")

	var scope_a := service.create_scope()
	var scope_b := service.create_scope()
	await scope_a.load_all([_key(6)])
	await scope_b.load_all([_key(6)])
	var shared := await _sample("skin 6 held by two scopes")
	scope_a.release()
	var after_a := await _sample("first scope released")
	_check(after_a.resources == shared.resources and after_a.texture_mb >= shared.texture_mb - TEXTURE_SLACK_MB,
		"shared skin stays loaded while another scope holds it")
	scope_b.release()
	var after_b := await _sample("second scope released")
	_check(after_b.resources <= base.resources + RESOURCE_SLACK and after_b.texture_mb <= base.texture_mb + TEXTURE_SLACK_MB,
		"shared skin is freed after the last owner releases")
	var snapshot := service.debug_snapshot()
	_check(snapshot.owners == 0 and snapshot.operations == 0, "service has no owners or operations left")
	await service.shutdown()
	service.queue_free()
