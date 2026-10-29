extends Node
## The build-ahead preparation (EIUnitModel.prewarm) composes the map's unit
## atlases on worker lanes. Every body and surface atlas must equal the one
## the per-model path composes serially, pixel for pixel; shared layers are
## decoded once per preparation and never mutated by a neighbour's resize.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func snapshot() -> Dictionary:
	var out := {}
	for key in EIUnitModel._textures:
		var t: Texture2D = EIUnitModel._textures[key]
		out["body|" + key] = t.get_image().get_data() if t else PackedByteArray()
	for key in EIUnitModel._surface_textures:
		var t: Texture2D = EIUnitModel._surface_textures[key]
		out["surface|" + key] = t.get_image().get_data() if t else PackedByteArray()
	return out
func clear_caches() -> void:
	EIUnitModel._textures.clear(); EIUnitModel._surface_textures.clear()
func _ready() -> void:
	var map := EIMapScene.load_map("zone1", "", false, false)
	var records: Array = map.unit_records
	check(records.size() > 40, "zone1 supplies unit records (%d)" % records.size())
	# Serial reference: the per-model path composes each record's atlases.
	clear_caches()
	var t0 := Time.get_ticks_usec()
	var serial_models := 0
	for r in records:
		var m := EIUnitModel.create(r)
		if m: serial_models += 1; m.free()
	var serial_us := Time.get_ticks_usec() - t0
	var reference := snapshot()
	check(reference.size() >= 20, "the serial path composed atlases (%d)" % reference.size())
	# The preparation on a cleared cache.
	clear_caches()
	t0 = Time.get_ticks_usec()
	var made := EIUnitModel.prewarm(records)
	var prepared_us := Time.get_ticks_usec() - t0
	var prepared := snapshot()
	check(made.textures == prepared.size(), "the preparation counts the textures it added (%d of %d)" % [made.textures, prepared.size()])
	check(prepared.keys().size() == reference.keys().size() and prepared.keys().all(func(k): return reference.has(k)),
		"the preparation fills the same atlas keys (%d / %d)" % [prepared.size(), reference.size()])
	var same := 0
	for key in prepared:
		if reference.has(key) and reference[key] == prepared[key]: same += 1
	check(same == prepared.size(), "every prepared atlas equals the serial one pixel for pixel (%d of %d)" % [same, prepared.size()])
	# Models made after the preparation add nothing and reuse the textures.
	var before := prepared.size()
	var reused := 0
	for r in records:
		var m := EIUnitModel.create(r)
		if m: reused += 1; m.free()
	check(snapshot().size() == before and reused == serial_models, "models after the preparation add no atlas (%d models)" % reused)
	# A second preparation on a warm cache adds nothing.
	check(EIUnitModel.prewarm(records).textures == 0, "a warm preparation composes nothing")
	# Pure composition: the layers given are not mutated (a resize works on a copy).
	var small := Image.create(8, 8, false, Image.FORMAT_RGBA8); small.fill(Color.RED)
	var big := Image.create(16, 16, false, Image.FORMAT_RGBA8); big.fill(Color8(0, 255, 0, 128))
	var given: Array[Image] = [small, big]
	var composed := EIUnitModel._compose_image(given)
	check(composed != null and composed.get_size() == Vector2i(16, 16) and composed.has_mipmaps()
		and small.get_size() == Vector2i(8, 8) and small.get_pixel(0, 0) == Color.RED and big.get_pixel(0, 0).is_equal_approx(Color8(0, 255, 0, 128)),
		"composing copies the layers it resizes or blends into")
	print("PREWARM_ATLASES serial_us=", serial_us, " prepared_us=", prepared_us, " records=", records.size(), " atlases=", prepared.size())
	print("UNIT_PREWARM_ATLASES checks=", checks, " failures=", failures)
	map.free()
	get_tree().quit(1 if failures else 0)
