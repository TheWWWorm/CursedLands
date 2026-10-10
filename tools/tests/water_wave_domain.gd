extends "water_interaction.gd"
## Exact pre-change domain oracle, including fractional window alignment,
## currents, liquid exclusions and level changes. CPU timings exclude checks.
const DomainField = preload("res://src/game/fx/water_wave_field.gd")
const Reference = preload("water_wave_domain_reference.gd")
const Current = preload("res://src/game/fx/water_current.gd")
var any_flow := false


func candidate() -> RefCounted:
	return DomainField.new() # Source-substitution fixtures override this factory.


func dense_case() -> void:
	var terrain := EITerrain.new(); terrain.sectors_x = 1; terrain.sectors_y = 1; terrain.grid_w = 33
	terrain.materials = [{"type":2,"wave":0.0,"color":Color.WHITE,"self_illum":0.0}]
	terrain.heights.resize(33*33); terrain.liquid_ground.resize(32*32)
	terrain._lava.resize(64); terrain._level.resize(64)
	terrain.visible = false; add_child(terrain); terrain.set_process(false)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,4,0),Vector3(32,7.2,0),Vector3(0,2.4,-32),Vector3(32,5.6,-32)])
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,1,3,2])
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name = "Water_0_0"; node.mesh = mesh; terrain.add_child(node)
	var first_row := rows.size()
	compare_domains(terrain,[Vector2i(0,-128),Vector2i(0,-128),Vector2i(1,-127),Vector2i(3,-125)],"dense-sloped-plane")
	check(rows[first_row].wet_samples == DomainField.SIZE*DomainField.SIZE,"dense case covers every sample with sloping water")
	terrain.free()


func compare_domains(terrain: EITerrain, origins: Array[Vector2i], label: String) -> void:
	var fields := [Reference.new(),candidate(),candidate(),Reference.new()]
	for origin: Vector2i in origins:
		var durations := []; var samples: Dictionary; var reference := PackedFloat32Array()
		var levels := PackedFloat32Array(); var flow_build := -1
		for i in fields.size():
			var field: RefCounted = fields[i]; field.origin = origin
			var start := Time.get_ticks_usec(); field._domain(terrain)
			durations.append(Time.get_ticks_usec()-start)
			if i == 0:
				reference = field.domain.duplicate(); samples = field._cells.duplicate(true)
				levels = field._levels.duplicate(); flow_build = field._flow_build
			else:
				check(field.domain.to_byte_array() == reference.to_byte_array(),label+" exact domain "+str(origin)+" arm "+str(i))
				check(field._cells == samples,label+" exact retained samples "+str(origin)+" arm "+str(i))
				check(field._levels == levels and field._flow_build == flow_build,label+" exact invalidation keys "+str(origin)+" arm "+str(i))
			check(field._cells.size() <= 33*33 and field._surface._sectors.size() <= Surface.CACHE_SECTORS,label+" bounded caches")
		var wet := 0; var max_flow := 0.0
		for i in DomainField.SIZE*DomainField.SIZE:
			wet += int(reference[i*4+3] > 0)
			max_flow = maxf(max_flow,absf(reference[i*4+1])+absf(reference[i*4+2]))
		any_flow = any_flow or max_flow > 0.01
		rows.append({"case":label,"origin":str(origin),"domain_us_abba":durations,
			"wet_samples":wet,"max_flow":max_flow,"cached_cells":samples.size()})
	for field: RefCounted in fields: field.clear()


func map_cases(name: String) -> void:
	var terrain := EITerrain.load_map(name)
	check(terrain != null,name+" loads")
	if terrain == null: return
	terrain.visible = false; add_child(terrain); terrain.set_process(false)
	var point := centre(terrain)
	check(point.is_finite(),name+" has exposed water")
	if not point.is_finite(): terrain.free(); return
	var base := Vector2i(floori(point.x/DomainField.CELL)-64,floori(point.z/DomainField.CELL)-64)
	var origins: Array[Vector2i] = [base,base,base+Vector2i(17,0),base+Vector2i(34,17),base+Vector2i(34,17)]
	for y in 4:
		for x in 4: origins.append(Vector2i(base.x&~3,base.y&~3)+Vector2i(x,y))
	origins.append_array([Vector2i(-1,-1),Vector2i(-127,-127),Vector2i(-140,-140),
		Vector2i(terrain.sectors_x*128-1,-1),Vector2i(-1,-terrain.sectors_y*128-1),base+Vector2i(300,300)])
	var water := terrain.water.duplicate(); var ground := terrain.heights.duplicate()
	compare_domains(terrain,origins,name+"/still")
	var current := Current.new(terrain); terrain._current = current
	compare_domains(terrain,[base,base,base+Vector2i(17,0),base+Vector2i(34,17)],name+"/current")
	terrain._current = null; current.clear()
	var m := int(terrain.water_mat[floori(-point.z)*terrain.sectors_x*32+floori(point.x)])
	for offset: float in [0.4,-0.3,0.0]:
		terrain.set_water_offset(m,offset)
		compare_domains(terrain,[base,base+Vector2i(17,-17)],name+"/level/"+str(offset))
	# Admission controls retain the same real triangles and land geometry.
	var lava := terrain._lava.duplicate(); terrain._lava[m] = 1.0
	compare_domains(terrain,[base],name+"/lava"); terrain._lava = lava
	var authored: Dictionary = terrain.materials[m].duplicate(true)
	terrain.materials[m]["self_illum"] = 1.0; terrain.materials[m]["color"] = Color.WHITE
	compare_domains(terrain,[base],name+"/emissive"); terrain.materials[m] = authored
	var cells := terrain.liquid_ground.duplicate()
	for excluded: int in [13,14,255]:
		terrain.liquid_ground.fill(excluded)
		compare_domains(terrain,[base],name+"/excluded/"+str(excluded))
	terrain.liquid_ground = cells
	check(terrain.water == water and terrain.heights == ground,name+" navigation and land remain unchanged")
	terrain.free(); await get_tree().process_frame
	print("WAVE_DOMAIN_MAP ",name)


func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"gfx_water":1,"auto_graphics":0,"confine_mouse":0,"vsync":0},true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	dense_case()
	for name: String in ["zone1","zone11","zone8"]: await map_cases(name)
	check(any_flow,"current cases include nonzero authored flow")
	TexUpscale.shutdown(); await get_tree().process_frame
	var report := {"checks":checks,"failures":failures,"rows":rows,"platform":OS.get_name(),
		"scope":"CPU domain construction only, identical real-map inputs in ABBA order; no rendering/FPS claim."}
	FileAccess.open("user://water-wave-domain.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WATER_WAVE_DOMAIN checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
