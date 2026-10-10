extends "water_surface_cache.gd"
## Compare against the eager initializer/vertex method, including first deformed frame
## after mean-only queries. Constructor and first-use timings are separate.
const Eager = preload("water_surface_phase_reference.gd")

func reference(terrain: EITerrain) -> RefCounted:
	return Eager.new(terrain)

func begin(surfaces: Array, deformed: bool, cache_mean := true) -> void:
	for surface: RefCounted in surfaces: surface.begin_frame(deformed,cache_mean)

func construct(terrain: EITerrain) -> Dictionary:
	var surfaces := []; var times := []
	for optimized: bool in [false,true,true,false]:
		var start := Time.get_ticks_usec()
		var surface := candidate(terrain) if optimized else reference(terrain)
		times.append(Time.get_ticks_usec()-start); surfaces.append(surface)
	return {"surfaces":surfaces,"constructor_us_abba":times}

func phase_case(name: String) -> void:
	var terrain := EITerrain.load_map(name)
	check(terrain != null,name+" loads")
	if terrain == null: return
	terrain.visible = false; add_child(terrain); terrain.set_process(false)
	var p := centre(terrain); check(p.is_finite(),name+" has exposed water")
	if not p.is_finite(): terrain.free(); return
	var point := Vector2(p.x,p.z)
	var navigation := terrain.water.duplicate(); var land := terrain.heights.duplicate()
	var phase := Surface.WaveState.phase_grid()
	var constructor_runs := []
	for repeat in 12:
		var built := construct(terrain); constructor_runs.append(built.constructor_us_abba)
		check(built.surfaces[0]._phase.to_byte_array() == phase.to_byte_array(),name+" eager constructor has exact phases")
		check(built.surfaces[1]._phase.is_empty() and built.surfaces[2]._phase.is_empty(),name+" lazy constructors allocate no phases")
	rows.append({"case":name+"/constructors","constructor_us_abba":constructor_runs,
		"before_phase_bytes":phase.size()*4,"after_unused_phase_bytes":0})
	var built := construct(terrain); var surfaces: Array = built.surfaces
	var points := PackedVector2Array()
	for y in 16:
		for x in 16: points.append(point+Vector2(x-7.25,y-7.75))
	begin(surfaces,false); compare(surfaces,points,name+"/mean-first")
	check(surfaces[1]._phase.is_empty(),name+" dense mean queries need no phases")
	for surface: RefCounted in surfaces: surface.clear()
	check(surfaces[1]._phase.is_empty(),name+" clear of unused surface keeps phases absent")
	terrain._water_mat.set_shader_parameter("waves",0.0)
	begin(surfaces,true,false); compare(surfaces,points,name+"/waves-disabled")
	check(surfaces[1]._phase.is_empty(),name+" posed request with waves disabled needs no phases")
	terrain._water_mat.set_shader_parameter("waves",1.0)
	terrain._waves.advance(7.37); begin(surfaces,true,false)
	check(surfaces[1]._phase.to_byte_array() == phase.to_byte_array(),name+" deformed frame prepares phases before contact queries")
	compare(surfaces,PackedVector2Array([Vector2(-100,100),Vector2(INF,0),Vector2(NAN,0)]),name+"/empty-posed")
	check(surfaces[1]._phase.to_byte_array() == phase.to_byte_array(),name+" empty posed queries retain prepared phases")
	# Posed queries use the original field even if the water clock advanced
	# before the first deformed frame.
	compare(surfaces,PackedVector2Array([point]),name+"/first-posed-after-mean")
	check(surfaces[1]._phase.to_byte_array() == phase.to_byte_array(),name+" first posed use retains exact phase bytes")
	check(not surfaces[1].sample(point).is_empty(),name+" first posed control is a positive hit")
	compare(surfaces,points,name+"/posed-repeat")
	terrain._waves.advance(0.137); begin(surfaces,true,false)
	compare(surfaces,points,name+"/posed-clock-advanced")
	var material := int(surfaces[1].sample(point).material)
	terrain.set_water_offset(material,0.375); begin(surfaces,true,false)
	compare(surfaces,points,name+"/posed-offset")
	terrain.set_water_offset(material,0.0)
	for surface: RefCounted in surfaces: surface.clear()
	check(surfaces[1]._phase.to_byte_array() == phase.to_byte_array(),name+" clear retains already computed deterministic phases")
	begin(surfaces,false); compare(surfaces,points,name+"/mean-after-posed-clear")
	begin(surfaces,true,false); compare(surfaces,points,name+"/posed-after-clear")
	# Guard per-instance ownership and against rebuilding a prepared field.
	surfaces[1]._phase[0] += 0.125
	check(surfaces[2]._phase.to_byte_array() == phase.to_byte_array(),name+" phase storage is independently owned")
	var altered: PackedByteArray = surfaces[1]._phase.to_byte_array()
	surfaces[1].clear(); surfaces[1].begin_frame(); surfaces[1].sample(point)
	check(surfaces[1]._phase.to_byte_array() == altered,name+" subsequent posed use does not regenerate phases")
	surfaces[1]._phase = phase.duplicate()
	# A fresh query also works without an explicit begin_frame, as before.
	var fresh := candidate(terrain); var eager := reference(terrain)
	check(fresh._phase.is_empty(),name+" fresh implicit frame starts lazy")
	fresh.sample(Vector2(-100,100))
	check(fresh._phase.is_empty(),name+" empty implicit query leaves phases absent")
	check(var_to_bytes(fresh.sample(point)) == var_to_bytes(eager.sample(point)),name+" implicit first posed frame stays exact")
	check(fresh._phase.to_byte_array() == phase.to_byte_array(),name+" implicit first frame initializes phases")
	# Explicitly include constructor + first posed work, so a deferred cost
	# cannot be advertised as a saving for consumers that need animated water.
	var posed_totals := []
	for repeat in 6:
		var batch := construct(terrain); var totals: Array = batch.constructor_us_abba
		for i in batch.surfaces.size():
			var surface: RefCounted = batch.surfaces[i]
			var start := Time.get_ticks_usec(); surface.begin_frame(); surface.sample(point)
			totals[i] += Time.get_ticks_usec()-start
		posed_totals.append(totals)
	rows.append({"case":name+"/constructor-plus-first-posed","total_us_abba":posed_totals})
	check(terrain.water == navigation and terrain.heights == land,name+" phase preparation leaves navigation intact")
	terrain.free(); await get_tree().process_frame
	print("SURFACE_PHASE_MAP ",name)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"gfx_water":1,"auto_graphics":0,"confine_mouse":0,"vsync":0},true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120; process_mode = Node.PROCESS_MODE_ALWAYS
	for name: String in ["zone1","zone11","zone8"]: await phase_case(name)
	TexUpscale.shutdown(); await get_tree().process_frame
	FileAccess.open("user://surface-phase.json",FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rows":rows,"platform":OS.get_name()},"\t"))
	print("SURFACE_PHASE_DONE checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
