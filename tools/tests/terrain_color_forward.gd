extends Node
## Real Ingos snow: asynchronous colour pages, live native footprints, option
## changes and eviction. This is a lifecycle/visual check, not an FPS sample.
var checks := 0
var failures := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func frames(count := 12) -> void:
	for i in count: await get_tree().process_frame

func capture(label: String) -> void:
	await frames(30)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://terrain-color-forward-"+label+".png")

func _ready() -> void: run.call_deferred()

func run() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Forward+ is required");get_tree().quit(2);return
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.gfx_terrain=1
	GameData.options.merge({"auto_graphics":0,"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0,"show_tutorial":0,"confine_mouse":0,"fps_limit":0,"vsync":0,"scroll_border":0},true)
	get_window().size=Vector2i(1920,1080)
	var session := Session.new();add_child(session)
	var game := Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0));session.state.world_time=12
	var zone := session.campaign.zone_by_map("zone11")
	await session.enter_zone(String(zone.id),1,false)
	session.set_physics_process(false);game.world.set_physics_process(false);game.world.vm.instances.clear()
	game.rig.set_process(false);game.direct.set_process(false)
	var terrain := game.world.terrain
	var cache := terrain.color_cache
	check(is_instance_valid(cache) and cache._enabled,"enhanced snow installs the Forward+ cache")
	if not is_instance_valid(cache):get_tree().quit(1);return
	cache.set_process(false)
	var soft := terrain.details.soft_ground
	soft.set_process(false);soft._age=123
	var camera := game.rig.camera
	cache.prepare(camera)
	check(cache._bytes>0 and cache._bytes<=TerrainColorCache.BUDGET_BYTES,"pages stay within 128 MiB")
	var point := Vector2.INF
	for row: Dictionary in cache._resident.values():
		for y in [16,8,24]:
			for x in [16,8,24]:
				var p := Vector2(row.node.tile_origin*2)+Vector2(x+.5,y+.5)
				if soft.step_allowed(p):point=p;break
			if point.is_finite():break
		if point.is_finite():break
	# The initial view can contain hard ground. Find an authored soft tile
	# elsewhere before moving the camera and its bounded resident set.
	if not point.is_finite():
		for i in terrain.land_tile.size():
			var code: int=terrain.land_tile[i]
			var kind: int=terrain.tile_types[((code>>6)&255)*64+(code&63)]
			if not kind in SoftGroundDeform.TYPES:continue
			var p := Vector2(i%(terrain.sectors_x*16),i/(terrain.sectors_x*16))*2+Vector2.ONE
			if soft.step_allowed(p):point=p;break
	check(point.is_finite(),"an authored soft tile accepts tracks")
	if not point.is_finite():get_tree().quit(1);return
	var focus := Vector3(point.x,terrain.height_at(point.x,point.y),-point.y)
	camera.global_position=focus+Vector3(0,7,5);camera.look_at(focus)
	cache.prepare(camera)
	var key := Vector2i((point/32).floor())
	check(cache._resident.has(key),"focused sector is resident")
	await capture("before")
	soft.add_step(point,Vector2(.25,.40),.3)
	for i in 8:soft._process(0);soft._finish_mesh_jobs(true)
	check(soft.sectors.has(key),"native footprint mesh installed")
	if not soft.sectors.has(key):get_tree().quit(1);return
	var rec: Dictionary=soft.sectors[key]
	var mesh: MeshInstance3D=rec.node.get_ref()
	check(mesh.mesh!=rec.source and mesh.get_active_material(0)==rec.material,"live footprint material remains drawn")
	check(rec.material.shader==cache._shader,"deformed sector uses cached colour")
	check(rec.material.get_shader_parameter("soft_tracks")==true,"track sampling remains enabled")
	check(rec.material.get_shader_parameter("baked_ground")==cache._resident[key].material.get_shader_parameter("baked_ground"),"deformation shares the resident colour page")
	var track_texture := soft.field.texture
	var deformed_mesh := mesh.mesh
	soft._process(1.0)
	check(is_equal_approx(rec.material.get_shader_parameter("soft_track_time"),soft._age),"track aging still updates the live material")
	await capture("tracks")
	for mode in [0,1,2]:
		GameData.options.gfx_terrain=mode;Gfx.apply_surface_options();terrain.apply_gfx();cache.prepare(camera)
		var cached: bool = mode!=0 and TerrainColorCache.available(terrain)
		check(soft.field.texture==track_texture and mesh.mesh==deformed_mesh,"detail change retains native trail geometry and field")
		rec=soft.sectors[key]
		check((rec.material.get_shader_parameter("baked_ground")!=null)==cached,"detail change selects the matching colour sampler")
		check(rec.material.get_shader_parameter("soft_tracks")==true,"detail change retains track sampling")
		if not cached:check(cache._bytes==0 and cache._jobs.is_empty(),"disabled or unsupported detail releases pages and joins workers")
		else:check(cache._bytes<=TerrainColorCache.BUDGET_BYTES and cache._resident.has(key),"detail rebuild stays bounded")
		await capture("detail-%d"%mode)
	GameData.options.gfx_terrain=1;Gfx.apply_surface_options();terrain.apply_gfx();cache.prepare(camera)
	rec=soft.sectors[key]
	var water_id := -1
	for id:int in terrain.water_mat:
		if id>=0 and id<64:water_id=id;break
	check(water_id>=0,"the fixture contains an authored water material")
	if water_id>=0:
		terrain.set_water_offset(water_id,.25)
		check(rec.material.get_shader_parameter("level")==terrain._level,"scripted water change reaches live cached tracks")
		check(cache._resident[key].material.get_shader_parameter("level")==terrain._level,"scripted water change reaches ordinary cached terrain")
		terrain.set_water_offset(water_id,0)
	# Evict this page while its native track is still present.
	cache._wanted_keys=cache._resident.duplicate();cache._wanted_keys.erase(key)
	check(cache._evict() and not cache._resident.has(key),"a page can be evicted under a live footprint")
	check(mesh.mesh==deformed_mesh and soft.field.texture==track_texture,"eviction preserves the deformed mesh and field")
	check(rec.material.shader==terrain._land_mat.shader and rec.material.get_shader_parameter("baked_ground")==null,"eviction restores the original sampler")
	await capture("evicted")
	cache.prepare(camera)
	check(cache._resident.has(key) and rec.material.shader==cache._shader,"returning to a page reinstates cached colour on existing tracks")
	var old_size := terrain._atlas_source_size
	terrain._atlas_source_size=terrain.texture_size*8;cache.refresh()
	check(not cache._enabled and cache._bytes==0,"oversized replacement textures retain authored detail")
	check(rec.material.get_shader_parameter("baked_ground")==null,"oversized fallback retains uncached live footprints")
	terrain._atlas_source_size=old_size;cache.refresh();cache.prepare(camera)
	check(cache._resident.has(key),"normal texture source can restore the cache")
	soft.clear()
	check(mesh.get_active_material(0)==cache._resident[key].material,"track expiry restores the resident ordinary material")
	await capture("restored")
	# Start genuine asynchronous work elsewhere and clear while it is pending.
	var remote := focus
	var farthest := 0.0
	for row:Dictionary in cache._sectors:
		var centre:Vector3=row.box.get_center()
		if centre.distance_squared_to(focus)>farthest:
			remote=centre;farthest=centre.distance_squared_to(focus)
	camera.global_position=remote+Vector3(0,20,12);camera.look_at(remote)
	cache._select(camera);cache._start_jobs()
	check(not cache._jobs.is_empty(),"camera movement starts new native page jobs")
	cache.clear()
	check(cache._bytes==0 and cache._resident.is_empty() and cache._jobs.is_empty(),"clear joins pending jobs and releases pages")
	check(cache._field==null and cache._shader==null,"clear releases owned source pixels and shader")
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()}
	FileAccess.open("user://terrain-color-forward.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TERRAIN_COLOR_FORWARD ",JSON.stringify(report))
	game.free();session.free();await frames(4);TexUpscale.shutdown();get_tree().quit(int(not failures.is_empty()))
