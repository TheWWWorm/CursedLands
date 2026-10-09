extends Node
## Optional external retained sources must never ask the GPU for pixels and
## must match cached custom-material readback. Shipped producers retain none.
const SOURCE_IMAGE := &"ei_wound_source"
var checks := 0
var failures := 0

class ReadbackTexture extends Texture2D:
	var pixels: Image
	var reads := 0
	func _get_image() -> Image:
		reads += 1
		return pixels.duplicate()
	func _get_width() -> int:
		return pixels.get_width()
	func _get_height() -> int:
		return pixels.get_height()
	func _has_alpha() -> bool:
		return true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func source_image() -> Image:
	var pixels := PackedByteArray()
	for i in 16:
		pixels.append_array([40 + i * 3, 80 + i, 150 - i * 2, 255])
	return Image.create_from_data(4, 4, false, Image.FORMAT_RGBA8, pixels)

func source_texture(retained: bool) -> ReadbackTexture:
	var texture := ReadbackTexture.new()
	texture.pixels = source_image()
	if retained:
		texture.set_meta(SOURCE_IMAGE, texture.pixels.duplicate())
	return texture

func seed_layers() -> void:
	for code: String in UnitWounds.HUMAN_CODES:
		for level in range(1, 4):
			var data := PackedByteArray()
			data.resize(EIMmp.DATA_OFFSET + 64)
			data.encode_u32(0, EIMmp.MAGIC)
			data.encode_u32(4, 4)
			data.encode_u32(8, 4)
			data.encode_u32(12, 64)
			data.encode_u32(16, 0x33544e50) # PNT3
			data.encode_u32(20, 32)
			for i in 16:
				var offset := EIMmp.DATA_OFFSET + i * 4
				data[offset] = 7 + i
				data[offset + 1] = level * 9
				data[offset + 2] = level * 35
				data[offset + 3] = 40 + level * 45
			UnitWounds._layer_data["test%sw%d" % [code, level]] = data

func composite(texture: Texture2D, levels: PackedByteArray, label: String) -> Image:
	var pending := UnitWounds._wounded(texture, "test", levels, true)
	var key := UnitWounds._key(texture, "test", levels)
	check(pending == null and UnitWounds._jobs.has(key), label + ": work scheduled")
	if not UnitWounds._jobs.has(key):
		return null
	var job: Dictionary = UnitWounds._jobs[key]
	UnitWounds.flush()
	check(job.out != null, label + ": image built")
	check(UnitWounds._composites.has(key), label + ": result published")
	return job.out

func same_image(a: Image, b: Image, label: String) -> void:
	check(a != null and b != null and a.get_size() == b.get_size()
			and a.get_format() == b.get_format() and a.has_mipmaps() == b.has_mipmaps()
			and a.get_data() == b.get_data(), label)

func test_retained_pixels() -> void:
	UnitWounds.shutdown()
	seed_layers()
	var retained := source_texture(true)
	var legacy := source_texture(false)
	var original := (retained.get_meta(SOURCE_IMAGE) as Image).get_data()
	for levels in [PackedByteArray([1, 0, 0, 0, 0, 0]), PackedByteArray([3, 2, 1, 2, 1, 3])]:
		var actual := composite(retained, levels, "retained")
		var expected := composite(legacy, levels, "legacy")
		same_image(actual, expected, "retained/readback results including mipmaps")
	check(retained.reads == 0, "unit source causes no readback")
	check(legacy.reads == 1, "unregistered texture keeps one cached readback")
	check((retained.get_meta(SOURCE_IMAGE) as Image).get_data() == original, "worker leaves source immutable")
	UnitWounds._composites.clear()
	UnitWounds._bases.clear()
	composite(retained, PackedByteArray([2, 0, 0, 0, 0, 0]), "after eviction")
	check(retained.reads == 0, "cache eviction cannot force unit readback")
	check(UnitWounds._wounded(retained, "test", PackedByteArray([0, 0, 0, 0, 0, 0]), true) == retained,
			"healing returns original texture")
	UnitWounds.shutdown()

func test_pending_material_changes() -> void:
	seed_layers()
	var model := EIUnitModel.new()
	model.template = "test"
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	var first := source_texture(true)
	material.albedo_texture = first
	mesh.material_override = material
	model.add_child(mesh)
	add_child(model)
	UnitWounds.apply(model, PackedByteArray([1, 0, 0, 0, 0, 0]), true)
	UnitWounds.apply(model, PackedByteArray([0, 0, 0, 0, 0, 0]), true)
	UnitWounds.flush()
	check(material.albedo_texture == first, "healing wins over an older pending wound job")

	UnitWounds.apply(model, PackedByteArray([2, 0, 0, 0, 0, 0]), true)
	var second := source_texture(true)
	second.pixels.fill(Color(0.1, 0.4, 0.2, 1.0))
	second.set_meta(SOURCE_IMAGE, second.pixels.duplicate())
	material.albedo_texture = second
	model.remove_meta("wound_key") # a rebuilt outfit is admitted again
	UnitWounds.apply(model, PackedByteArray([3, 0, 0, 0, 0, 0]), true)
	UnitWounds.flush()
	var key := UnitWounds._key(second, "test", PackedByteArray([3, 0, 0, 0, 0, 0]))
	check(material.albedo_texture == UnitWounds._composites[key], "new outfit wins over old pending job")
	check(material.get_meta("wound_base") == second, "new outfit owns wound base")
	check(first.reads == 0 and second.reads == 0, "pending outfit changes do not read back")
	model.free()
	UnitWounds.shutdown()

func test_real_producer() -> void:
	var tested := 0
	for file: String in GameData.redress.names_with_suffix(".mmp"):
		if not file.begins_with("unhuma") or file.ends_with("w1.mmp") or file.ends_with("w2.mmp") or file.ends_with("w3.mmp"):
			continue
		var layer := file.trim_prefix("unhuma").trim_suffix(".mmp")
		var texture := EIUnitModel._compose("unhuma", [layer])
		if texture == null:
			continue
		check(not texture.has_meta(SOURCE_IMAGE), "real redress texture retains no CPU source: " + file)
		UnitWounds.shutdown()
		check(EIUnitModel._compose("unhuma", [layer]) == texture and not texture.has_meta(SOURCE_IMAGE),
				"cached outfit lifetime is independent of wound source cache")
		tested += 1
		if tested == 3:
			break
	check(tested == 3, "three real outfit sources covered")

func _ready() -> void:
	test_retained_pixels()
	test_pending_material_changes()
	test_real_producer()
	UnitWounds.shutdown()
	print("WOUND_SOURCE ", JSON.stringify({"checks": checks, "failures": failures, "threads": Portability.threads()}))
	get_tree().quit(1 if failures else 0)
