extends Node
## Shipped wound-only path: independent of outfit pixels/dimensions, bounded
## shared uploads, stale-request ownership, selection and native health rules.
var checks := 0
var failures := 0
var measured := {}
var LV := PackedByteArray([3,1,2,2,1,1])
var ZERO := PackedByteArray([0,0,0,0,0,0])

class ReadbackTexture extends Texture2D:
	var size := 16
	var reads := 0
	var backing: ImageTexture
	func _get_rid() -> RID: return backing.get_rid()
	func _get_image() -> Image:
		reads += 1
		var img := Image.create(size,size,false,Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		return img
	func _get_width() -> int: return size
	func _get_height() -> int: return size
	func _has_alpha() -> bool: return true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func image(size: int) -> Image:
	var out := Image.create(size,size,false,Image.FORMAT_RGBA8)
	out.fill(Color(0.3,0.2,0.1,0.7))
	return out

func base(size := 16) -> ReadbackTexture:
	var tex := ReadbackTexture.new()
	tex.size = size
	tex.backing = ImageTexture.create_from_image(image(size))
	return tex

func reset() -> void:
	UnitWounds.shutdown()
	# Shared, proven PNT3 skip fixture used by the legacy cache regression.
	var fixture: Node = load(get_script().resource_path.get_base_dir()+"/wound_cache.gd").new()
	fixture.seed_layers()
	fixture.free()

func model_with(material, texture: Texture2D, surface := false) -> EIUnitModel:
	var model := EIUnitModel.new()
	model.template = "test"
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	material.albedo_texture = texture
	if surface:
		mesh.mesh = BoxMesh.new()
		mesh.set_surface_override_material(0,material)
	else:
		mesh.material_override = material
	model.add_child(mesh)
	add_child(model)
	return model

func test_sharing() -> void:
	reset()
	var models := []
	var mats := [EIUnitModel.LitMaterial.new(),EIUnitModel.PreviewMaterial.new(),EIUnitModel.LitMaterial.new()]
	var bases := [base(16),base(32),base(64)]
	for i in mats.size():
		models.append(model_with(mats[i],bases[i]))
		UnitWounds.apply(models[i],LV,true)
	check(UnitWounds._jobs.size() == 1 and UnitWounds._layer_jobs.size() == 1,"three different outfits schedule one native wound upload")
	var job: Dictionary = UnitWounds._jobs.values()[0]
	check(job.base == null and job.src == null and job.overlay,"wound worker has no base texture or pixels")
	UnitWounds.flush()
	var wound: Texture2D = mats[0].wound_texture
	check(wound != null and job.tex == wound,"native wound upload published")
	check(job.out.get_size() == Vector2i(4,4) and job.out.has_mipmaps() and job.out.get_data_size() == 84,"only native-size wound plus its complete mip chain uploaded")
	for i in mats.size():
		check(mats[i].albedo_texture == bases[i] and bases[i].reads == 0,"base identity/no readback for outfit %d" % i)
		check(mats[i].wound_texture == wound,"all world/preview outfits share one GPU texture %d" % i)
	check(UnitWounds._composites.is_empty() and UnitWounds._bases.is_empty(),"shipped materials create no replacement-albedo cache")
	check(job.wound.get_data().slice(0,16) == PackedByteArray([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),"PNT3 skipped block stays transparent")
	var warm := UnitWounds._overlay("test",LV,true)
	check(warm.finished and warm.tex == wound and UnitWounds._jobs.is_empty(),"warm outfit needs no worker or upload")
	for model: Node in models: model.free()
	UnitWounds.shutdown()

func test_requests() -> void:
	reset()
	var models := []
	var mats := [EIUnitModel.LitMaterial.new(),EIUnitModel.PreviewMaterial.new(),EIUnitModel.LitMaterial.new(),EIUnitModel.PreviewMaterial.new()]
	var bases := []
	for i in mats.size():
		bases.append(base())
		models.append(model_with(mats[i],bases[-1]))
		UnitWounds.apply(models[-1],LV,true)
	UnitWounds.apply(models[0],ZERO,true)
	var replacement := base(32)
	mats[1].albedo_texture = replacement # no new apply: setter cancels old ownership
	mats[2].albedo_texture = replacement
	models[2].remove_meta("wound_key")
	var newer := PackedByteArray([1,0,0,0,0,0])
	UnitWounds.apply(models[2],newer,true)
	var ref := weakref(mats[3])
	models[3].free()
	mats[3] = null
	check(ref.get_ref() == null,"pending request does not retain a discarded preview material")
	UnitWounds.flush()
	check(mats[0].wound_texture == null and mats[0].albedo_texture == bases[0],"healing wins over pending layer")
	check(mats[1].wound_texture == null and mats[1].albedo_texture == replacement,"changing outfit alone invalidates pending layer")
	check(mats[2].wound_texture == UnitWounds._layer_textures[UnitWounds._layer_key("test",newer,true)] and mats[2].albedo_texture == replacement,"newest outfit/level request wins")
	check(UnitWounds._overlay_waiting.is_empty(),"all stale/dead consumers released")
	for i in 3: models[i].free()
	UnitWounds.shutdown()

func test_selection() -> void:
	for surface in [false,true]:
		reset()
		var mat := EIUnitModel.LitMaterial.new()
		var tex := base()
		var model := model_with(mat,tex,surface)
		var marks := OrderMarks.new()
		UnitWounds.apply(model,LV,true)
		marks._lighten(model,true) # select after request, before worker publication
		var selected: EIUnitModel.LitMaterial = marks._bright[mat]
		UnitWounds.flush()
		marks._lighten(model,true)
		check(selected.wound_texture == mat.wound_texture and selected.wound_texture != null,"selection created during pending wound catches publication: %s" % surface)
		check(selected.albedo_texture == tex and selected.get_shader_parameter("unit_emission") == Vector3.ONE,"selection retains base and white emission")
		UnitWounds.apply(model,PackedByteArray([2,0,0,0,0,0]),true)
		UnitWounds.flush()
		marks._lighten(model,true)
		check(selected.wound_texture == mat.wound_texture and selected.wound_texture != null,"continuously selected model changes wound")
		marks._lighten(model,false)
		UnitWounds.apply(model,ZERO,true)
		marks._lighten(model,true)
		check(selected.wound_texture == null and selected.albedo_texture == tex,"detached selection copy refreshes after heal/reselect")
		marks._lighten(model,false)
		model.free()
		marks.free()
	UnitWounds.shutdown()

func test_exclusions_and_fallback() -> void:
	for gpu_first in [false,true]:
		reset()
		var gpu := EIUnitModel.PreviewMaterial.new()
		var legacy := StandardMaterial3D.new()
		var b := base()
		var a := model_with(gpu,b)
		var c := model_with(legacy,base(8))
		var head := MeshInstance3D.new()
		var headmat := EIUnitModel.PreviewMaterial.new()
		headmat.albedo_texture = b
		head.material_override = headmat
		head.set_meta("detailed_head",true)
		a.add_child(head)
		UnitWounds.apply(a if gpu_first else c,LV,true)
		UnitWounds.apply(c if gpu_first else a,LV,true)
		check(UnitWounds._layer_jobs.size() == 1 and UnitWounds._jobs.size() == 2,"custom fallback and GPU share native composition in either request order")
		UnitWounds.flush()
		check(gpu.albedo_texture == b and gpu.wound_texture != null and b.reads == 0,"GPU follower/producer never consumes base pixels")
		check(legacy.albedo_texture != legacy.get_meta("wound_base") and UnitWounds._composites.size() == 1,"custom StandardMaterial keeps explicit legacy bake")
		check(headmat.albedo_texture == b and headmat.wound_texture == null,"detailed head atlas excluded")
		a.free(); c.free()
	reset()
	var missing := UnitWounds._overlay("no-such-wound-asset",LV,true)
	UnitWounds.flush()
	check(missing.finished and missing.tex == null and missing.out == null,"missing wound does not upload transparent replacement")
	check(UnitWounds._overlay("no-such-wound-asset",LV,true).finished and UnitWounds._jobs.is_empty(),"failed layer is cached without repeated jobs")
	UnitWounds.shutdown()

func test_cache() -> void:
	reset()
	var mat := EIUnitModel.LitMaterial.new()
	var model := model_with(mat,base())
	UnitWounds.apply(model,LV,true)
	# Finish producer but prevent dispatching its consumer until after eviction.
	var waiting := UnitWounds._overlay_waiting.duplicate()
	UnitWounds._overlay_waiting.clear()
	UnitWounds.flush()
	var job: Dictionary = waiting[0][3]
	var texture: Texture2D = job.tex
	for i in UnitWounds.LAYER_CACHE_LIMIT: UnitWounds._cache_layer("missing%d" % i,null)
	check(UnitWounds._wound_layers.size() == UnitWounds.LAYER_CACHE_LIMIT and UnitWounds._layer_textures.is_empty(),"entry eviction releases both CPU and GPU cached references")
	UnitWounds._overlay_waiting = waiting
	UnitWounds._poll()
	check(mat.wound_texture == texture,"eviction cannot orphan completed pending consumer")
	var rebuilt := UnitWounds._overlay("test",LV,true)
	UnitWounds.flush()
	check(rebuilt.tex != texture and rebuilt.out.get_data() == job.out.get_data(),"evicted upload rebuilds exact native mips while active consumer remains valid")
	for i in 6: UnitWounds._cache_layer("large%d" % i,image(512))
	check(UnitWounds._wound_layer_bytes == UnitWounds.LAYER_CACHE_BYTES and UnitWounds._layer_textures.is_empty(),"CPU byte eviction also drops GPU cache")
	UnitWounds._cache_layer("oversized",image(2048))
	check(not UnitWounds._wound_layers.has("oversized"),"oversized custom layer not retained")
	UnitWounds._cache_layer("large5",null)
	check(UnitWounds._wound_layer_bytes == 3 * 1024 * 1024,"replacement cache entry updates byte ownership")
	model.remove_meta("wound_key")
	UnitWounds.apply(model,PackedByteArray([2,0,0,0,0,0]),true)
	UnitWounds.shutdown()
	check(UnitWounds._jobs.is_empty() and UnitWounds._overlay_waiting.is_empty() and UnitWounds._layer_jobs.is_empty() and UnitWounds._layer_textures.is_empty() and UnitWounds._wound_layers.is_empty() and UnitWounds._wound_layer_bytes == 0,"shutdown drains workers and clears every cache/deferred reference")
	model.free()

func test_health() -> void:
	var unit := GameUnit.new()
	unit.race = {"type_id":0x32}
	var parts := []
	for hp in [100.0,75.0,74.9,33.0,1.01,1.0]: parts.append({"cur":hp,"max":100.0,"state":1})
	unit.parts = parts
	check(UnitWounds.levels(unit) == PackedByteArray([0,0,1,2,2,3]),"original inclusive health thresholds")
	unit.race = {"type_id":0}
	check(UnitWounds.levels(unit) == PackedByteArray([0,0,2,2,3,3]),"nonhuman paired limbs take worse damage")
	unit.race = {"type_id":0x32}
	unit.parts[2].state = 0
	unit.parts[3].max = 0
	check(UnitWounds.levels(unit) == PackedByteArray([0,0,0,0,2,3]),"absent/zero-maximum parts excluded")
	var covered := {}
	for armor: Dictionary in GameData.db.tables.get("armors",[]):
		var slot := int(armor.get("type_id",-1))
		if slot in [0,1,2] and not bool(armor.get("apply_wounds",true)) and not covered.has(slot): covered[slot] = armor.get("name","")
	check(covered.size() == 3,"authored wound-hiding armors cover all three slots")
	for slot in covered:
		for i in 6: parts[i] = {"cur":1.0,"max":100.0,"state":1}
		unit.parts = parts
		unit.info = {"armors":[covered[slot]]}
		var expected := PackedByteArray([3,3,3,3,3,3])
		for i in [[0],[1,2,3],[4,5]][slot]: expected[i] = 0
		check(UnitWounds.levels(unit) == expected,"authored armor suppression slot %d" % slot)
	unit.free()

func _ready() -> void:
	Gfx.ensure_globals()
	test_sharing()
	test_requests()
	test_selection()
	test_exclusions_and_fallback()
	test_cache()
	test_health()
	UnitWounds.shutdown()
	var report := {"checks":checks,"failures":failures,"threads":Portability.threads(),"measurements":measured}
	FileAccess.open("user://wound-gpu.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WOUND_GPU ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
