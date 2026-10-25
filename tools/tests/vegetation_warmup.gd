extends Node
## Compare loading-time representatives with the production streamed meshes.
## Placement is fixed explicitly; this is a layout/admission regression, not a
## claim about GPU compilation. Rendered campaign traces cover the latter.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Warm = preload("res://src/game/shader_warmup.gd")

class Details extends TerrainDetails:
	func prepare_grass() -> void: pass # The immutable fixture is already prepared.

class Pile extends "res://src/game/fx/biome_mounds.gd":
	func records(_field: RefCounted, _key: Vector2i, _boxes: Array) -> Array:
		return [{"p":Vector2(0.35,0.35),"kind":1,"radius":0.6,"height":0.2,"phase":0.4,
			"triangles":[{"cell":Vector2i.ZERO,"side":0,
				"grid":[Vector2i.DOWN,Vector2i.RIGHT,Vector2i.ZERO] as Array[Vector2i],
				"vertices":[Vector3(0,0,-1),Vector3(1,0,0),Vector3.ZERO] as Array[Vector3]}]}]

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func _ready() -> void:
	GameData.options.merge({"gfx_contact_shadows":1,"gfx_volumetric":0},true)
	Gfx.ensure_globals()
	for sea in [false,true]:
		for cave in [false,true]: coverage(sea,cave)
	print("VEGETATION_WARMUP checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func fixture(sea: bool, cave: bool) -> Details:
	var d := Details.new()
	var field := Cover.new(); field.size=Vector2i(8,8); field.grid_w=9
	field.xy.resize(81); field.heights.resize(81); field.tiles.resize(16)
	var uv := PackedVector2Array()
	for y in 3:
		for x in 3: uv.append(Vector2(x,y)*0.5)
	field.uv_table[0]=uv
	field.mounds=Pile.new(); field.mounds.enabled=true
	field.regions.cave=cave
	if sea: field.sea.tiles[Vector2i.ZERO]=true
	d._cover_field=field
	d._cover_material=ShaderMaterial.new()
	d._cover_material.shader=Cover.Geometry.shader(false,false,false,sea,cave)
	d._cover_contact_material=ShaderMaterial.new(); d._cover_contact_material.shader=Cover.Contact.shader(false)
	d._mound_material=ShaderMaterial.new(); d._mound_material.shader=Cover.Mounds.shader(false)
	d._material=ShaderMaterial.new()
	d._mesh=ArrayMesh.new(); d._far_mesh=d._mesh
	return d

func coverage(sea: bool, cave: bool) -> void:
	var label := "sea=%s cave=%s: " % [sea,cave]
	var d := fixture(sea,cave)
	var field := d._cover_field
	var snapshot := var_to_bytes([field.xy,field.heights,field.tiles,field.uv_table])
	seed(7125); var expected_rng := randi(); seed(7125)
	var variants := d.cover_warmup_variants()
	check(randi()==expected_rng,label+"warm-up preserves global RNG")
	check(snapshot==var_to_bytes([field.xy,field.heights,field.tiles,field.uv_table]),label+"immutable field is unchanged")
	check(d.get_child_count()==0 and d._chunks.is_empty() and d._queue.is_empty() and d._grass_jobs.is_empty(),
		label+"warm-up neither installs chunks nor starts streaming work")
	check(variants.size()==4,label+"leaf, stone, contact and mound are all admitted")
	# The unfixed code returns only the two loose-cover layouts. Stop here so
	# this same test reports an assertion failure against the old warm-up API.
	if variants.size()!=4:
		d.free(); return

	var records: Array[Dictionary]=[]
	for kind in [Cover.Kind.LEAF,Cover.Kind.STONE]:
		records.append({"kind":kind,"p":Vector2(3.4,3.4),"height":0.0,"seed":0.3,
			"angle":0.5,"scale":0.9,"normal":Vector3.UP,"colour":Color.WHITE})
	var arrays := Cover.Geometry.new().build(records,Vector2i.ZERO,field.sea if sea else null,field if cave else null)
	var contacts := Cover.Contact.build(field,records,Vector2i.ZERO)
	var mounds := field.mounds.build(field,Vector2i.ZERO,[])
	check(not contacts.is_empty() and not mounds.records.is_empty(),label+"production builders generate contact and mound geometry")
	var transforms: Array[Transform3D]=[]; var colours: Array[Color]=[]
	d._install_chunk(Vector2i.ZERO,{"transforms":transforms,"colours":colours,"custom":colours,
		"cover":{"records":records,"arrays":arrays,"contacts":contacts,"mounds":mounds}})
	var chunk: Node=d._chunks[Vector2i.ZERO]
	var warmer := Warm.new(); warmer._make_groups()
	for path in ["BiomeCover","BiomeCover/StoneContacts","BiomeMounds"]:
		var actual := chunk.get_node(path) as MeshInstance3D
		var matching := variants.filter(func(v: Array): return v[0]==actual.material_override \
			and v[1].surface_get_format(0)==actual.mesh.surface_get_format(0) and v[2]==actual.cast_shadow)
		check(not matching.is_empty(),label+path+" material, complete vertex format and shadow mode are prepared")
		if matching.is_empty(): continue
		var variant: Array=matching[0]
		var zero := Warm._zero_format(variant[1])
		check(zero.surface_get_format(0)==actual.mesh.surface_get_format(0),label+path+" format survives collapse")
		check(zero.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array().count(0)== \
			zero.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array().size(),label+path+" collapsed vertices write no geometry")
		var shown: Array=Callable(warmer,"_show").callv([variant[0],Warm.MESH,zero,variant[2]])
		check(shown.size()==4 and shown.all(func(n: GeometryInstance3D): return n.cast_shadow==actual.cast_shadow \
			and n.material_override==actual.material_override and n.mesh==zero),label+path+" all light groups draw the actual state")
		for n: Node in shown: n.free()
		cache_states(variant[0],zero,label+path)
	# Existing arena/particle callers retain their default state when no
	# per-instance override is supplied.
	for kind in [Warm.MESH,Warm.GRASS,Warm.PARTICLE,Warm.INSTANCED,Warm.REGIONAL,Warm.COLORED]:
		var expected := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind==Warm.MESH else \
			GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if kind==Warm.GRASS else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shown := warmer._show(d._cover_material,kind,Warm._zero_format(variants[0][1]))
		check(shown.all(func(n: GeometryInstance3D): return n.cast_shadow==expected),label+"default kind "+str(kind))
		for n: Node in shown: n.free()
	warmer.free()
	GameData.options["gfx_contact_shadows"]=0
	check(d.cover_warmup_variants().all(func(v: Array): return v[0]!=d._cover_contact_material),label+"disabled contacts add no warm-up draw")
	GameData.options["gfx_contact_shadows"]=1
	field.mounds.enabled=false
	check(d.cover_warmup_variants().all(func(v: Array): return v[0]!=d._mound_material),label+"maps without mounds add no mound draw")
	d.free()

func cache_states(material: Material, mesh: Mesh, label: String) -> void:
	var items := []; var seen := {}; var env := "vegetation-regression:"+label
	for mode in [GeometryInstance3D.SHADOW_CASTING_SETTING_ON,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED]:
		Callable(Warm,"_add").callv([items,seen,material,env,Warm.MESH,mesh,mode])
	check(items.size()==3,label+" distinct shadow pipelines survive deduplication")
	if items.size()!=3: return
	Warm._warmed[items[0][0]]=true
	var later := []; var later_seen := {}
	for mode in [GeometryInstance3D.SHADOW_CASTING_SETTING_ON,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED]:
		Callable(Warm,"_add").callv([later,later_seen,material,env,Warm.MESH,mesh,mode])
	check(later.size()==2,label+" one completed shadow variant cannot hide another")
	Warm._warmed.erase(items[0][0])
