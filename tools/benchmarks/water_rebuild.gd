extends Node
## Held terrain, actual SetWaterLevel/deferred callbacks. Measures CPU stages,
## not gameplay FPS or shader preparation. Source state is hashed after timing.
const TimedFalls = preload("water_rebuild_falls.gd")
const Current = preload("res://src/game/fx/water_current.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures+=1; printerr("FAIL ",label)

func digest(value: Variant) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(value)); return h.finish().hex_encode()

func geometry(helper: Node) -> String:
	var meshes := []
	for node: MeshInstance3D in helper.get_children():
		meshes.append([String(node.name),node.mesh.surface_get_arrays(0)])
	return digest(meshes)

func retained_bytes(helper: Node) -> Dictionary:
	var eligible: Variant=helper.field.get("_eligible")
	var result := {"index_bytes":eligible.size()*20 if eligible!=null else 0,"query_sectors":0,"query_array_bytes":0}
	var surface: Variant=helper.get("_surface")
	if surface==null: return result
	result.query_sectors=surface._sectors.size()
	for rec: Dictionary in surface._sectors.values():
		for key in ["vertices","indices","uv2","posed"]: result.query_array_bytes+=rec[key].to_byte_array().size()
		result.query_array_bytes+=rec.ready.size()
		for bucket: PackedInt32Array in rec.buckets.values(): result.query_array_bytes+=bucket.size()*4
	return result

func probe(name: String) -> void:
	var started := Time.get_ticks_usec()
	var terrain := EITerrain.load_map(name)
	var load_us := Time.get_ticks_usec()-started
	check(terrain!=null,name+" loaded")
	if terrain==null: return
	terrain.visible=false; add_child(terrain); terrain.set_process(false)
	var original_water := terrain.water.duplicate()
	started=Time.get_ticks_usec()
	var current := Current.new(terrain)
	var current_init_us := Time.get_ticks_usec()-started
	terrain._current=current
	var helper := TimedFalls.new(); terrain.add_child(helper); terrain._waterfalls=helper
	started=Time.get_ticks_usec(); helper.configure(terrain)
	var falls_init_us := Time.get_ticks_usec()-started
	var original_falls: Array = helper.field.falls.duplicate(true)
	var original_layers := digest([helper.field.layer,helper.field.exposed])
	var original_flow := digest(current.values)
	var used := -1
	for m: int in helper.field.owners:
		if m>=0: used=m; break
	if not original_falls.is_empty(): used=int(original_falls[0].top_owner)
	check(used>=0,name+" has authored liquid")
	var unused := -1
	for m in range(63,-1,-1):
		if not m in helper.field.owners and not m in current.owners and not m in terrain.water_mat:
			unused=m; break
	check(unused>=0,name+" has unused material control")
	var row := {"map":name,"size":str(helper.field.size),"load_us":load_us,
		"native_current":current._kernel!=null,"current_init_us":current_init_us,
		"current_initial_build_us":current.last_build_us,"falls_init_us":falls_init_us,
		"falls_initial_classification_us":helper.field.build_us,"falls_initial_mesh_us":helper.mesh_us,
		"used_material":used,"unused_material":unused,"initial_falls":original_falls,"steps":[]}
	if used>=0 and unused>=0:
		for step: Array in [[used,0.0],[used,0.2],[used,0.4],[used,0.6],[used,0.0],
			[unused,0.2],[unused,0.4],[unused,0.0],[used,-0.3],[used,0.0]]:
			var before := helper.refreshes.size(); var old_current: int=current.builds
			started=Time.get_ticks_usec()
			var changed := terrain.set_water_offset(step[0],step[1])
			var setter_us := Time.get_ticks_usec()-started
			await get_tree().process_frame
			for i in 4:
				if not helper._dirty and not terrain._current_dirty: break
				await get_tree().process_frame
			# Held terrain does not run its usual fallback-worker poll.
			for i in 600:
				current.poll()
				if current._task<0: break
				await get_tree().process_frame
			check(current._task<0,name+" current field converges")
			check(not helper._dirty and not terrain._current_dirty,name+" deferred updates drain")
			var samples: Array=helper.refreshes.slice(before)
			row.steps.append({"material":step[0],"offset":step[1],"changed_cells":str(changed),
				"setter_us":setter_us,"fall_refreshes":samples,
				"current_build_us":current.last_build_us if current.builds!=old_current else 0,
				"current_upload_us":current.last_upload_us if current.builds!=old_current else 0,
				"water_hash":digest(terrain.water),"falls_hash":digest(helper.field.falls),"geometry_hash":geometry(helper),
				"layers_hash":digest([helper.field.layer,helper.field.exposed]),"current_hash":digest(current.values)})
	check(terrain.water==original_water,name+" original navigation water restored")
	check(helper.field.falls==original_falls,name+" original fall records restored")
	check(digest([helper.field.layer,helper.field.exposed])==original_layers,name+" original exposed fields restored")
	check(digest(current.values)==original_flow,name+" original current restored")
	row.retained_cache=retained_bytes(helper)
	rows.append(row); print("WATER_REBUILD_MAP ",JSON.stringify(row))
	terrain.free(); current=null; helper=null; await get_tree().process_frame

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"gfx_water":1,"auto_graphics":0,"confine_mouse":0,"vsync":0},true)
	Gfx.ensure_globals(); Engine.time_scale=0; process_mode=Node.PROCESS_MODE_ALWAYS
	Engine.max_fps=120; RenderingServer.set_render_loop_enabled(true)
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	var names := ["zone11","zone13","zone8"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--water-rebuild-map="): names=[arg.trim_prefix("--water-rebuild-map=")]
	for name: String in names: await probe(name)
	TexUpscale.shutdown(); await get_tree().process_frame
	var report := {"checks":checks,"failures":failures,"maps":rows,
		"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),
		"scope":"CPU stages of actual level-change callbacks on hidden held terrain; no gameplay FPS or GPU cost claim."}
	FileAccess.open("user://water-rebuild.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WATER_REBUILD checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
