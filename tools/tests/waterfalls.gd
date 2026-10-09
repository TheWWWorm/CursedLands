extends Node
const Field = preload("res://src/game/fx/waterfall_field.gd")
const Falls = preload("res://src/game/fx/waterfalls.gd")
var checks := 0
var failures := 0
var records := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func fixture(mode := "step") -> RefCounted:
	var field := Field.new()
	field.size = Vector2i(65,33)
	field.rest.resize(65*33); field.rest.fill(INF)
	field.owners.resize(65*33); field.owners.fill(-1)
	field.bed.resize(65*33)
	for y in range(3,30):
		for x in range(2 if mode == "border" else 8,57 if mode == "wide" else 25):
			var i := y*65+x
			field.rest[i] = 11.0 if y < 16 else 5.0
			if mode == "rapid": field.rest[i] = 30.0-y*0.75
			if mode == "spike": field.rest[i] = 11.0
			field.bed[i] = field.rest[i]+1.0 if mode == "buried" else field.rest[i]-2.5
			field.owners[i] = 0 if y < 16 else 1
	if mode in ["spike","step-spike"]: field.rest[8*65+20] = 9.0
	var levels := PackedFloat32Array(); levels.resize(64)
	field.refresh(levels)
	return field

func analytic() -> void:
	var field := fixture()
	check(field.falls.size() == 1,"coherent six metre step is one waterfall")
	if not field.falls.is_empty():
		var fall: Dictionary = field.falls[0]
		check(absf(fall.top-11.0)<0.001 and absf(fall.bottom-5.0)<0.001,"levels follow river and pool")
		check(fall.direction.dot(Vector2.DOWN)>0.99 and absf(fall.lip.y-15.0)<0.1,"lip and downstream direction follow authored step")
		check(absf(fall.width-17.0)<0.1,"coherent lip spans river width")
	for mode in ["rapid","spike","buried","border","wide"]:
		check(fixture(mode).falls.is_empty(),"not a waterfall: "+mode)
	check(fixture("step-spike").falls.size()==1,"isolated stray spike does not add a waterfall")
	var before: Array = field.falls.duplicate(true)
	check(not field.refresh(field.levels),"unchanged levels reuse classification")
	var levels: PackedFloat32Array = field.levels.duplicate(); levels[1]=6.0
	check(field.refresh(levels) and field.falls.is_empty(),"flooded pool removes the drop")
	levels[1]=0.0; field.refresh(levels)
	check(field.falls==before,"restoring levels restores deterministic waterfall records")
	check(not is_finite(field.sample(Vector2(-0.01,10)).x),"outside sample cannot address a map edge")
	check(not is_finite(Field.new().sample(Vector2.ZERO).x),"empty grid has no surface")
	levels[0]=NAN; levels[1]=NAN; field.refresh(levels)
	check(field.falls.is_empty(),"nonfinite levels cannot produce an emitter")

func snapshot() -> void:
	var terrain := EITerrain.new(); terrain.sectors_x=1; terrain.sectors_y=1
	terrain.heights.resize(33*33); terrain.heights.fill(-3.0)
	terrain.liquid_ground.resize(32*32)
	terrain._level.resize(64); terrain._lava.resize(64)
	terrain.materials=[{"type":4,"self_illum":0.0},{"type":3,"self_illum":0.0}]
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array(); var uv2 := PackedVector2Array()
	for k in 9:
		vertices.append(Vector3(10+k%3-128.0/252.0,5.0+k*0.1,-12-k/3+128.0/252.0))
		uv2.append(Vector2(0,0 if k==0 else 65))
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV2]=uv2
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,3,1,4,3,4,5,7,5,8,7])
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name="Water_0_0"; node.mesh=mesh; terrain.add_child(node)
	var field := Field.new(terrain)
	check(field.owners[12*33+10]==0 and absf(field.rest[12*33+10]-5.0)<0.001,"type-4 half-metre XY jitter retains authored tile grid")
	check(field.owners[12*33+11]==1 and absf(field.rest[12*33+11]-5.1)<0.001,"mixed vertex owner and sign-bit decoding remain available at a lip")
	terrain._lava[1]=1.0
	field=Field.new(terrain)
	check(field.owners[12*33+11]<0 and field.owners[12*33+10]==0,"lava owner cannot leak into waterfall snapshot")
	terrain.liquid_ground[12*32+10]=14
	field=Field.new(terrain)
	check(field.owners.count(-1)==field.owners.size(),"swamp tile cannot seed a waterfall")
	terrain.free()

func maps() -> void:
	var names := ["zone1","zone8","zone11","zone13","zone15"]
	if "--waterfall-census" in OS.get_cmdline_user_args():
		names.clear()
		for name: String in GameFiles.files(GameData.root.path_join("maps")):
			if name.to_lower().begins_with("zone") and name.get_extension().to_lower()=="mpr": names.append(name.get_basename())
		names.sort()
	for map: String in names:
		if not GameFiles.exists(GameData.root.path_join("maps/"+map+".mpr")): continue
		var terrain := EITerrain.load_map(map)
		check(terrain != null,"real map loaded "+map)
		if terrain == null: continue
		add_child(terrain); terrain.set_process(false)
		var ground := terrain.heights.duplicate(); var navigation := terrain.water.duplicate()
		var start := Time.get_ticks_usec()
		var field := Field.new(terrain)
		var elapsed := Time.get_ticks_usec()-start
		var row := {"map":map,"size":str(field.size),"falls":field.falls,"candidates":field.candidates,"conflicts":field.conflicts,
			"snapshot_detect_us":elapsed,"detect_us":field.build_us,"materials":str(terrain.materials)}
		check(field.falls.size() <= Field.MAX_FALLS,"bounded site count "+map)
		check(terrain.heights==ground and terrain.water==navigation,"detection preserves ground and navigation "+map)
		if "--waterfall-geometry" in OS.get_cmdline_user_args():
			check(terrain._waterfalls==null,"default-off map has no waterfall owner "+map)
			GameData.options.gfx_water=1; GameData.options.gfx_waterfalls=1; terrain.apply_gfx()
			var helper: Falls = terrain._waterfalls
			check(helper!=null,"water option creates production owner "+map)
			if helper==null: terrain.free(); continue
			check(helper.field.falls==field.falls,"controller uses independent authored classification "+map)
			check(helper.shell_vertices<=Falls.MAX_SHELL_VERTICES and helper.sprites<=Falls.MAX_SPRITES,"global geometry bounds "+map)
			if not field.falls.is_empty():
				check(helper.shell_vertices>0,"real drop receives shell "+map)
				check(helper.sprites>0,"exact exposed liquid admits spray "+map)
				for site: Dictionary in helper.sites:
					check(site.lip>0 and site.impact>0 and site.mist>0,"real drop admits each emitter role "+map)
				var builds: int = helper.field.builds
				var clock: Variant = helper._shell.get_shader_parameter("fall_clock")
				for n in 10: helper.advance()
				check(helper.field.builds==builds and helper._shell.get_shader_parameter("fall_clock")==clock,"quiet frames reuse field and held clock "+map)
				row["geometry"]=helper.sites
				var owner: int = field.falls[0].top_owner
				terrain.set_water_offset(owner,0.2); terrain.set_water_offset(owner,0.4); terrain.set_water_offset(owner,0.6)
				check(not helper.visible,"flood hides stale lip before deferred refresh "+map)
				await get_tree().process_frame
				check(helper.visible and helper.field.builds==builds+1 and absf(helper.field.levels[owner]-0.6)<0.001,"multiple level writes coalesce once "+map)
				terrain.set_water_offset(owner,0.0); await get_tree().process_frame
				check(helper.field.falls==field.falls,"restored mean levels restore classification "+map)
			else:
				check(helper.get_child_count()==0 and helper._shell==null and helper._spray==null,"no matched drops means no render resources "+map)
			var weak := weakref(helper.field)
			GameData.options.gfx_waterfalls=0; terrain.apply_gfx()
			check(terrain._waterfalls==null and weak.get_ref()==null,"option disable releases visual field "+map)
			GameData.options.gfx_water=0; GameData.options.gfx_waterfalls=1; terrain.apply_gfx()
			check(terrain._waterfalls==null,"Water and lava effects is required "+map)
			GameData.options.gfx_waterfalls=0
		records.append(row); print("WATERFALL_MAP ",JSON.stringify(row))
		terrain.free(); await get_tree().process_frame

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"confine_mouse":0,"vsync":0,"auto_graphics":0},true)
	Gfx.ensure_globals()
	analytic(); snapshot(); await maps()
	TexUpscale.shutdown()
	FileAccess.open("user://waterfalls.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maps":records},"\t"))
	print("WATERFALLS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
