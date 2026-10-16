extends Node
## Real map, native colour jobs and native footprints on Mobile. Cache
## ownership is checked through upload, deformation, expiry and option swaps.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func capture(label: String) -> void:
	# Let the new camera's shadow cascades and asynchronously compiled draw
	# pipelines settle before comparing restored receiver materials.
	await get_tree().create_timer(1.0).timeout
	for i in 4: await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://terrain-cache-"+label+".png")

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile":
		printerr("TERRAIN_COLOR_LIFECYCLE requires Mobile and --ei-baked-terrain on desktop")
		get_tree().quit(2); return
	GameData.options.merge(GfxPresets.values(GfxPresets.MEDIUM),true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0,"show_tutorial":0,"q_aa":0},true)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(1920,1080)
	var session := Session.new(); add_child(session)
	var game := Game.new(); game.session=session; session.game=game; add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0)); session.state.world_time=12.0
	var zone := session.campaign.zone_by_map("zone11")
	check(not zone.is_empty(),"authored Ingos zone exists")
	if zone.is_empty(): get_tree().quit(1); return
	await session.enter_zone(String(zone.id),1,false)
	session.set_physics_process(false); game.world.set_physics_process(false)
	game.world.vm.briefings._check=INF; game.rig.set_process(false)
	var terrain := game.world.terrain
	var cache := terrain.color_cache
	var soft := terrain.details.soft_ground
	check(is_instance_valid(cache) and cache._enabled,"Mobile cache enabled with soft ground")
	if not is_instance_valid(cache): get_tree().quit(1); return
	soft.set_process(false); soft._age=123.0
	var point := Vector2.INF
	for row: Dictionary in cache._resident.values():
		var sector := row.node as EITerrainSector
		for y in [16,8,24]:
			for x in [16,8,24]:
				var p := Vector2(sector.tile_origin*2)+Vector2(x+.5,y+.5)
				if soft.step_allowed(p): point=p; break
			if point.is_finite(): break
		if point.is_finite(): break
	check(point.is_finite(),"cached authored sector supports snow footprints")
	if not point.is_finite(): get_tree().quit(1); return
	var focus := Vector3(point.x,terrain.height_at(point.x,point.y),-point.y)
	game.rig.global_position=focus; game.rig.camera.global_position=focus+Vector3(0,6,4)
	game.rig.camera.look_at(focus); cache.prepare(game.rig.camera)
	var key := Vector2i((point/32.0).floor())
	check(cache._resident.has(key),"focused sector is resident")
	if not cache._resident.has(key): get_tree().quit(1); return
	var sector := cache._resident[key].node as EITerrainSector
	var baked := cache._resident[key].material as ShaderMaterial
	check(sector._parts[0].get_active_material(0)==baked,"resident colour is drawn")
	await capture("before")
	soft.add_step(point,Vector2(.20,.32),.3)
	for i in 8: soft._process(0.0); soft._finish_mesh_jobs(true)
	check(soft.sectors.has(key),"native footprint sector installed")
	if soft.sectors.has(key):
		check(sector._parts[0].get_active_material(0)==soft.sectors[key].material,"live track material supersedes cached colour")
	check(sector.get_surface_override_material(0)==baked,"cache retained while tracks are active")
	await capture("tracks")
	soft.clear()
	check(sector._parts[0].get_active_material(0)==baked,"expiry restores the same cached material")
	await capture("restored")
	GameData.options.gfx_terrain=0; terrain.apply_gfx()
	check(cache._resident.is_empty() and cache._bytes==0 and cache._jobs.is_empty(),"disabling detail releases cache and joins jobs")
	GameData.options.gfx_terrain=1; terrain.apply_gfx(); cache.prepare(game.rig.camera)
	check(cache._resident.has(key) and cache._bytes<=TerrainColorCache.BUDGET_BYTES,"reenabling detail rebuilds within budget")
	await capture("reenabled")
	GameData.options.gfx_terrain=2; terrain.apply_gfx(); cache.prepare(game.rig.camera)
	check(cache._enabled and cache._bytes<=TerrainColorCache.BUDGET_BYTES,"Natural terrain retains bounded cached base colour")
	check(terrain._land_mat.shader.code.contains("terrain_samples(") and cache._shader.code.contains("EI_BAKED_TERRAIN"),"live and cached terrain keep their intended sampler variants")
	await capture("natural")
	cache.clear()
	check(cache._resident.is_empty() and cache._bytes==0 and cache._jobs.is_empty(),"explicit clear releases all derived resources")
	game.free(); session.free(); TexUpscale.shutdown()
	print("TERRAIN_COLOR_LIFECYCLE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))
