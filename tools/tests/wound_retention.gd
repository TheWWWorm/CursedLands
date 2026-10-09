extends Node
## Explicit CPU image ownership, not RSS: a bounded authored figure corpus is
## cached once and reused by world, preview, selection and recreated models.
## --expect-retained runs the same census against the pre-removal pack.
var checks := 0
var failures := 0
var retained := false
var rows := []
var samples := []
var legacy_rows := []
var uploads := []
var DAMAGE := PackedByteArray([3, 1, 2, 0, 1, 3])
var HEALED := PackedByteArray([0, 0, 0, 0, 0, 0])

class ReadbackTexture extends Texture2D:
	var backing: Texture2D
	var reads := 0
	func _get_rid() -> RID: return backing.get_rid()
	func _get_image() -> Image:
		reads += 1
		return backing.get_image()
	func _get_width() -> int: return backing.get_width()
	func _get_height() -> int: return backing.get_height()
	func _has_alpha() -> bool: return true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func digest(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func cache_sample(label: String) -> Dictionary:
	var textures := {}
	var images := {}
	var bytes := 0
	var texture_bytes := 0
	for key: String in EIUnitModel._textures:
		var texture: Texture2D = EIUnitModel._textures[key]
		if texture == null or textures.has(texture.get_instance_id()): continue
		textures[texture.get_instance_id()] = true
		# The fixture never reads GPU pixels while measuring retained sources.
		texture_bytes += texture.get_width() * texture.get_height() * 4
		var image: Image = texture.get_meta(UnitWounds.SOURCE_IMAGE) if texture.has_meta(UnitWounds.SOURCE_IMAGE) else null
		if image == null or images.has(image.get_instance_id()): continue
		images[image.get_instance_id()] = true
		bytes += image.get_data_size()
		check(not image.has_mipmaps() and image.get_format() == Image.FORMAT_RGBA8,
			label + ": retained source is mip-free RGBA8")
	var row := {"label": label, "texture_count": textures.size(),
		"base_level_rgba_bytes": texture_bytes, "retained_image_count": images.size(),
		"retained_image_bytes": bytes}
	samples.append(row)
	check(images.size() == (textures.size() if retained else 0), label + ": expected source ownership")
	return row

func material_bases(model: EIUnitModel) -> Dictionary:
	var out := {}
	for material: Material in UnitWounds._materials(model):
		check(material is EIUnitModel.LitMaterial or material is EIUnitModel.PreviewMaterial,
			"authored figure uses a shipped shader material")
		if material.albedo_texture: out[material.albedo_texture.get_instance_id()] = material.albedo_texture
	return out

func corpus() -> void:
	var chosen := {}
	var counts := [0, 0]
	var first_record := {}
	var first_sources := {}
	for proto: Dictionary in GameData.db.table("monster_prototypes"):
		var race := GameData.db.find("race_models", String(proto.get("base_race", "")))
		var human := int(race.get("type_id", 0)) == 0x32
		var kind := 0 if human else 1
		if counts[kind] >= (16 if human else 8): continue
		var mask := String(race.get("mask", "")).to_lower()
		if mask.is_empty() or (human and mask != "unhuma"): continue
		var signature := JSON.stringify([mask, proto.get("skin", 0),
			proto.get("wears", []), proto.get("weapon", "")]) if human else mask
		if chosen.has(signature) or EIFigure.get_model(mask).is_empty(): continue
		chosen[signature] = true
		var record := {"prototype": proto.get("name", ""), "template": mask}
		var world := EIUnitModel.create(record, false, false)
		var preview := EIUnitModel.create(record, true, false)
		check(world != null and preview != null, "authored world/preview pair " + String(record.prototype))
		if world == null or preview == null: continue
		add_child(world); add_child(preview)
		var world_bases := material_bases(world)
		var preview_bases := material_bases(preview)
		check(not world_bases.is_empty() and world_bases == preview_bases,
			"world and preview share cached outfit textures " + String(record.prototype))
		UnitWounds.apply(world, DAMAGE, human)
		UnitWounds.apply(preview, DAMAGE, human)
		var marks := OrderMarks.new()
		marks._lighten(world, true)
		UnitWounds.flush()
		marks._lighten(world, true)
		check(material_bases(world) == world_bases and material_bases(preview) == preview_bases,
			"wounding/selection preserves outfit identity " + String(record.prototype))
		check(UnitWounds._bases.is_empty() and UnitWounds._composites.is_empty(),
			"shipped request never creates a CPU source or replacement albedo")
		check(not marks._bright.is_empty(), "authored world figure installs selection copies")
		for material: Material in marks._bright:
			var selected: Material = marks._bright[material]
			check(selected.albedo_texture == material.albedo_texture
				and selected.wound_texture == material.wound_texture,
				"selection shares base and asynchronously published wound")
		marks._lighten(world, false)
		UnitWounds.apply(world, HEALED, human)
		UnitWounds.apply(preview, HEALED, human)
		check(material_bases(world) == world_bases and material_bases(preview) == preview_bases,
			"healing preserves outfit identity " + String(record.prototype))
		rows.append({"prototype": record.prototype, "mask": mask, "human": human,
			"layers": world.get_meta("layers"), "unique_outfit_textures": world_bases.size()})
		if human and first_record.is_empty():
			first_record = record.duplicate()
			first_sources = world_bases.duplicate()
		world.free(); preview.free(); marks.free()
		counts[kind] += 1
		if counts == [16, 8]: break
	check(counts == [16, 8], "bounded corpus includes 16 authored human outfits and 8 creature masks")
	var loaded := cache_sample("after_model_disposal")
	UnitWounds.shutdown()
	check(cache_sample("after_wound_shutdown").retained_image_bytes == loaded.retained_image_bytes,
		"wound shutdown does not change outfit-cache source ownership")
	var recreated := EIUnitModel.create(first_record, true, false)
	check(recreated != null and material_bases(recreated) == first_sources,
		"recreated preview reuses the original outfit cache")
	if recreated: recreated.free()
	var redress := first_record.duplicate()
	redress.armors = PackedStringArray()
	redress.weapons = PackedStringArray()
	var dressed := EIUnitModel.create(redress, false, false)
	check(dressed != null, "authored hero can rebuild without equipment")
	if dressed:
		add_child(dressed)
		var original := material_bases(dressed)
		UnitWounds.apply(dressed, DAMAGE, true)
		UnitWounds.flush()
		check(material_bases(dressed) == original and UnitWounds._bases.is_empty(),
			"redress and renewed damage require no retained CPU source")
		dressed.free()
	cache_sample("after_recreate_and_redress")
	UnitWounds.shutdown()

func archive_source(key: String) -> Image:
	var parts := key.split("|")
	var source: Image
	for layer: String in parts.slice(1):
		var decoded := EIUnitModel._load_layer(parts[0], layer)
		if decoded == null: continue
		if source == null: source = decoded; continue
		if decoded.get_size() != source.get_size():
			decoded.resize(source.get_width(), source.get_height(), Image.INTERPOLATE_BILINEAR)
		source.blend_rect(decoded, Rect2i(Vector2i.ZERO, decoded.get_size()), Vector2i.ZERO)
	return source

func uploaded_bytes() -> void:
	# Deliberate verification readbacks happen after the normal-path census.
	# Every cached base, including its complete mip chain, must still match the
	# authored archive composition exactly. No production readback is added.
	for key: String in EIUnitModel._textures:
		var texture: Texture2D = EIUnitModel._textures[key]
		if texture == null: continue
		var expected := archive_source(key)
		expected.generate_mipmaps()
		var actual := texture.get_image()
		check(actual != null and actual.get_size() == expected.get_size()
			and actual.get_format() == expected.get_format()
			and actual.has_mipmaps() == expected.has_mipmaps(), "uploaded base dimensions/format/mips " + key)
		if actual == null: continue
		check(actual.get_data() == expected.get_data(), "uploaded base and all mip bytes remain exact " + key)
		uploads.append({"key": key, "bytes": actual.get_data_size(),
			"sha256": digest(actual.get_data())})

func legacy_job(base: Texture2D, levels: PackedByteArray) -> Dictionary:
	UnitWounds._wounded(base, "unhuma", levels, true)
	var key := UnitWounds._key(base, "unhuma", levels)
	check(UnitWounds._jobs.has(key), "legacy custom request schedules a private composite")
	return UnitWounds._jobs.get(key, {})

func legacy_fallback() -> void:
	# Compare the actual uploaded outfit readback with independently decoded
	# archive layers. Metadata is deliberately supplied only by this fixture.
	var keys: Array = EIUnitModel._textures.keys()
	keys.sort()
	var selected := []
	var kinds := {}
	for key: String in keys:
		if not key.begins_with("unhuma|") or key.count("|") < 2: continue
		var body := key.get_slice("|", 1).begins_with("skin_")
		if EIUnitModel._textures[key] != null and not kinds.has(body):
			kinds[body] = true
			selected.append(key)
			if selected.size() == 2: break
	check(selected.size() == 2, "authored body and secondary atlases cover real legacy readback")
	for key: String in selected:
		UnitWounds.shutdown()
		var source := archive_source(key)
		var readback := ReadbackTexture.new()
		readback.backing = EIUnitModel._textures[key]
		var explicit := ReadbackTexture.new()
		explicit.backing = readback.backing
		explicit.set_meta(UnitWounds.SOURCE_IMAGE, source)
		var immutable := digest(source.get_data())
		for levels in [DAMAGE, PackedByteArray([1, 0, 0, 0, 0, 0])]:
			var actual := legacy_job(readback, levels)
			var expected := legacy_job(explicit, levels)
			UnitWounds.flush()
			check(actual.get("out") != null and expected.get("out") != null,
				"readback and explicit-source custom jobs produce pixels")
			if actual.get("out") == null or expected.get("out") == null: continue
			check(actual.src.get_data() == source.get_data(), "actual readback preserves authored composite pixels")
			check(actual.out.get_data() == expected.out.get_data(), "custom fallback preserves all output/mip bytes")
			legacy_rows.append({"key": key, "levels": levels.hex_encode(),
				"source_bytes": source.get_data_size(), "source_sha256": immutable,
				"output_sha256": digest(actual.out.get_data()), "reads": readback.reads})
		check(readback.reads == 1 and explicit.reads == 0,
			"custom fallback reads once per cached base; external metadata avoids readback")
		check(digest(source.get_data()) == immutable, "legacy workers never mutate external metadata")
		# Cache eviction while a worker owns its source must not invalidate it.
		var pending := legacy_job(readback, PackedByteArray([2, 0, 0, 0, 0, 0]))
		UnitWounds._bases.clear()
		UnitWounds.flush()
		check(pending.get("out") != null and pending.src.get_data() == source.get_data(),
			"pending custom job owns source independently of cache eviction")
		UnitWounds.shutdown()
		check(UnitWounds._bases.is_empty(), "custom source cache released at shutdown")
		legacy_job(readback, DAMAGE)
		UnitWounds.flush()
		check(readback.reads == 2, "custom fallback may read once again after explicit shutdown")
	UnitWounds.shutdown()

func _ready() -> void:
	retained = OS.get_cmdline_user_args().has("--expect-retained")
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["confine_mouse"] = 0
	Engine.max_fps = 120
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	UnitWounds.shutdown()
	corpus()
	uploaded_bytes()
	legacy_fallback()
	var report := {"checks": checks, "failures": failures, "expect_retained": retained,
		"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"threads": Portability.threads(), "corpus": rows, "samples": samples, "legacy": legacy_rows, "uploads": uploads,
		"scope": "Distinct explicit SOURCE_IMAGE owners in a bounded authored figure corpus, not RSS or a whole-game memory census. Headless renderer retains its own dummy pixels separately. GPU readbacks occur only in deliberate post-census upload/custom-material controls."}
	FileAccess.open("user://wound-retention.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("WOUND_RETENTION ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
