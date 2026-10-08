extends Node
## Shared native wounds must preserve material ownership and every output mip.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func image(size: int, colour := Color(0.17, 0.33, 0.59, 1.0)) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	return img

func texture(size: int, colour := Color(0.17, 0.33, 0.59, 1.0)) -> ImageTexture:
	var src := image(size, colour)
	var tex := ImageTexture.create_from_image(src)
	tex.set_meta(UnitWounds.SOURCE_IMAGE, src)
	return tex

func seed_layers() -> void:
	# A real PNT3 block with an explicit skip and a zero-alpha first pixel.
	# Its layers are deliberately different for human and paired-creature limbs.
	for code: String in ["hd", "bd", "lh", "rh", "ll", "rl", "h", "l"]:
		for level in range(1, 4):
			var data := PackedByteArray(); data.resize(EIMmp.DATA_OFFSET + 4 + 3 * 16)
			data.encode_u32(0, EIMmp.MAGIC)
			data.encode_u32(4, 4); data.encode_u32(8, 4)
			data.encode_u32(12, 64)
			data.encode_u32(16, 0x33544e50); data.encode_u32(20, 32)
			data.encode_u32(EIMmp.DATA_OFFSET, 16)
			for i in 12:
				var offset := EIMmp.DATA_OFFSET + 4 + i * 4
				data[offset] = 7 + i
				data[offset+1] = level * 9 + code.length() * 10
				data[offset+2] = level * 35
				data[offset+3] = 40 + level * 45
			for c in 4: data[EIMmp.DATA_OFFSET + 4 + c] = 0
			UnitWounds._layer_data["test%sw%d" % [code,level]] = data

func request(base: Texture2D, lv: PackedByteArray, human := true) -> Dictionary:
	var result := UnitWounds._wounded(base,"test",lv,human)
	var key := UnitWounds._key(base,"test",lv,human)
	check(result == null and UnitWounds._jobs.has(key),"new outfit scheduled")
	return UnitWounds._jobs.get(key,{})

func test_sharing() -> void:
	UnitWounds.shutdown(); seed_layers()
	var lv := PackedByteArray([3,1,2,2,1,1])
	var bases := [texture(4),texture(8),texture(16)]
	var jobs := []
	for base: Texture2D in bases: jobs.append(request(base,lv))
	check(UnitWounds._layer_jobs.size() == 1,"simultaneous outfits compose one wound layer")
	check(jobs[0].get("compose_layer",false) and jobs[1].has("layer_job") and jobs[2].has("layer_job"),"followers wait on producer without consuming workers")
	UnitWounds.flush()
	check(UnitWounds._jobs.is_empty() and UnitWounds._layer_jobs.is_empty(),"flush finishes all dependent jobs")
	var wound: Image = jobs[0].wound
	var original := wound.get_data()
	for i in bases.size():
		var expected := (bases[i].get_meta(UnitWounds.SOURCE_IMAGE) as Image).duplicate() as Image
		var resized := wound.duplicate() as Image
		if resized.get_size() != expected.get_size(): resized.resize(expected.get_width(),expected.get_height(),Image.INTERPOLATE_BILINEAR)
		expected.blend_rect(resized,Rect2i(Vector2i.ZERO,resized.get_size()),Vector2i.ZERO)
		expected.generate_mipmaps()
		check(jobs[i].wound == wound,"all outfits share immutable native wound")
		check(jobs[i].out.get_data() == expected.get_data(),"different outfit sizes retain blend-before-mipmap result")
	check(wound.get_size() == Vector2i(4,4) and not wound.has_mipmaps() and wound.get_data() == original,"resizing a follower cannot mutate shared layer")
	UnitWounds._composites.clear(); UnitWounds._bases.clear()
	var warm := request(texture(8,Color.GREEN),lv)
	check(not warm.has("layers") and warm.wound == wound,"new outfit reuses completed layer after albedo eviction")
	UnitWounds.flush()
	var creature := request(bases[0],lv,false)
	UnitWounds.flush()
	check(creature.wound.get_data() != wound.get_data(),"human and paired creature limb codes have separate cache identities")
	check(UnitWounds._wound_layers.size() == 2,"both limb layouts retained independently")
	# PNT3 skipped first four pixels remain empty in the composed native layer.
	check(wound.get_data().slice(0,16) == PackedByteArray([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),"native PNT3 skip bytes survive shared composition")
	# Creature arms/legs must remain duplicated. Removing a repeated layer changes it.
	var single := {"layers":[["h",null,UnitWounds._layer_data.testhw2]],"decoded":{}}
	var doubled := {"layers":single.layers + single.layers,"decoded":{}}
	check(UnitWounds._compose_layer(single).get_data() != UnitWounds._compose_layer(doubled).get_data(),"paired limb contributions are not deduplicated")
	UnitWounds.shutdown()

func model_with(m, base: Texture2D) -> EIUnitModel:
	var model := EIUnitModel.new(); model.template = "test"
	var mesh := MeshInstance3D.new(); mesh.name = "Body"; mesh.material_override = m
	m.albedo_texture = base; model.add_child(mesh); add_child(model)
	return model

func test_material_changes() -> void:
	UnitWounds.shutdown(); seed_layers()
	var lv := PackedByteArray([1,0,0,0,0,0]); var healed := PackedByteArray([0,0,0,0,0,0])
	var models := []
	var materials := [StandardMaterial3D.new(),EIUnitModel.LitMaterial.new(),EIUnitModel.PreviewMaterial.new()]
	var bases := []
	for m: Material in materials:
		var base := texture(4); bases.append(base)
		var model := model_with(m,base); models.append(model)
		UnitWounds.apply(model,lv,true)
	# Healing a follower before its wound is available must invalidate that request.
	UnitWounds.apply(models[1],healed,true)
	var replacement := texture(8,Color.GREEN)
	materials[2].albedo_texture = replacement
	models[2].remove_meta("wound_key")
	UnitWounds.apply(models[2],PackedByteArray([3,0,0,0,0,0]),true)
	materials[0].emission_texture = bases[0]
	UnitWounds.flush()
	check(materials[1].albedo_texture == bases[1],"healing beats a waiting shared-layer follower")
	check(materials[2].get_meta("wound_base") == replacement,"replacement preview keeps its current outfit")
	check(materials[2].albedo_texture == UnitWounds._composites[UnitWounds._key(replacement,"test",PackedByteArray([3,0,0,0,0,0]))],"replacement preview beats old deferred output")
	check(materials[0].albedo_texture == materials[0].emission_texture and materials[0].albedo_texture != bases[0],"selection emission follows wounded albedo")
	# An already wounded portrait and a worsening world material use their own bases.
	UnitWounds.apply(models[1],PackedByteArray([2,0,0,0,0,0]),true)
	UnitWounds.apply(models[2],lv,true)
	UnitWounds.flush()
	check(materials[1].get_meta("wound_base") == bases[1] and materials[1].albedo_texture != bases[1],"world material worsens after healing")
	check(materials[2].get_meta("wound_base") == replacement,"wounded preview never treats previous wounds as base")
	for i in models.size():
		UnitWounds.apply(models[i],healed,true)
		check(materials[i].albedo_texture == (replacement if i == 2 else bases[i]),"healing restores each material's original outfit")
		models[i].free()
	UnitWounds.shutdown()

func test_eviction_and_shutdown() -> void:
	UnitWounds.shutdown(); seed_layers()
	var lv := PackedByteArray([1,0,0,0,0,0])
	var first := request(texture(4),lv)
	var follower := request(texture(8),lv)
	# Bound both null/malformed entries and large custom layers while work is pending.
	for i in UnitWounds.LAYER_CACHE_LIMIT + 10: UnitWounds._cache_layer("missing%d" % i,null)
	check(UnitWounds._wound_layers.size() == UnitWounds.LAYER_CACHE_LIMIT,"failed decodes cannot grow entry cache unbounded")
	var megabyte := image(512)
	for i in 6: UnitWounds._cache_layer("large%d" % i,megabyte)
	check(UnitWounds._wound_layer_bytes <= UnitWounds.LAYER_CACHE_BYTES,"large wound layers obey byte bound")
	UnitWounds.flush()
	check(first.out != null and follower.out != null,"cache eviction cannot orphan pending dependents")
	var key := UnitWounds._layer_key("test",lv,true)
	for i in UnitWounds.LAYER_CACHE_LIMIT: UnitWounds._cache_layer("evict%d" % i,null)
	check(not UnitWounds._wound_layers.has(key),"old wound layer evicted")
	var rebuilt := request(texture(4),lv); UnitWounds.flush()
	check(rebuilt.out.get_data() == first.out.get_data(),"evicted layer rebuilds identical pixels and mips")
	UnitWounds._cache_layer("oversized",image(2048))
	check(not UnitWounds._wound_layers.has("oversized"),"oversized custom layer is not retained")
	var pending := PackedByteArray([2,0,0,0,0,0])
	request(texture(4),pending); request(texture(8),pending)
	UnitWounds.shutdown()
	check(UnitWounds._jobs.is_empty() and UnitWounds._layer_jobs.is_empty() and UnitWounds._wound_layers.is_empty() and UnitWounds._wound_layer_bytes == 0,"shutdown drains active workers and drops deferred work/cache")
	seed_layers(); request(texture(4),pending); UnitWounds.flush()
	check(UnitWounds._wound_layers.size() == 1,"new scene can rebuild after shutdown")
	UnitWounds.shutdown()

func _ready() -> void:
	Gfx.ensure_globals()
	test_sharing()
	test_material_changes()
	test_eviction_and_shutdown()
	var report := {"checks":checks,"failures":failures,"threads":Portability.threads()}
	FileAccess.open("user://wound-cache.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WOUND_CACHE ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
