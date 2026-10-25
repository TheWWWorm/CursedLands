extends "res://tools/tests/path_trace_camera_routes.gd"
## Production controller, terrain/material variants, local lights, streaming,
## accumulation switches and complete teardown in the actual campaign.
var cave := false
var high_quality := false
var cache_readback := PackedInt32Array()
signal cache_inspected
func enable_diagnostics(target: Object) -> void:
	target.sharc.diagnostics=true
	cache_inspected.emit.call_deferred()
func read_cache(target: Object) -> void:
	cache_readback=target.sharc.counters();cache_inspected.emit.call_deferred()
func select_sharc(rt: Node,enabled: bool) -> bool:
	GameData.options.pt_sharc=int(enabled)
	await frames(2)
	for i in 900:
		await frames(1)
		if rt._failed:return false
		if rt.device!=null and rt.device.output_ready() and rt.device.sharc.active==enabled \
			and not rt.stats.get("rebuilding",false) and not ShaderCompilationScreen.active():return true
	return false
func setup_sharc() -> Array:
	resolution=Vector2i(1920,1080)
	for arg in OS.get_cmdline_user_args():
		if arg=="--sharc-cave":cave=true
		if arg=="--sharc-high":high_quality=true
	var context := await setup_route()
	if context.is_empty():return []
	var session: Session=context[0];var game: Game=context[1]
	if cave:
		await session.enter_zone("gz5g",1,false);t=game.world.terrain
		session.set_physics_process(false);session.world.set_physics_process(false);session.world.vm.instances.clear()
		game.set_process(false);game.rig.set_process(false);game.direct.set_process(false);game._update_daylight(false)
		var hero: GameUnit=session.party_units(0)[0]
		var focus := hero.global_position+Vector3.UP
		camera.global_position=focus+Vector3(6,6,7);camera.look_at(focus);camera.current=true
	for unit: GameUnit in session.world.units.values():
		unit.set_process(false);unit.set_physics_process(false)
		if unit.model!=null and unit.model.player!=null:unit.model.player.pause()
	GameData.options.merge({"pt_mode":2,"pt_accumulation":0,"pt_sharc":0,"pt_target_fps":0},true)
	if high_quality:GameData.options.q_rt_lighting=2
	return context
func run() -> void:
	var context := await setup_sharc()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1];var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"ordinary PT prepares actual campaign scene")
	if rt.device==null:await finish_live(context,rt);return
	var previous: Object=rt.device
	await frames(30);var original := await capture("sharc-off")
	check(await select_sharc(rt,true),"production SHaRC option reaches rendered output")
	check(rt.device==previous,"enabling SHaRC retains the current scene acceleration structures")
	RenderingServer.call_on_render_thread(enable_diagnostics.bind(rt.device));await cache_inspected
	await frames(60)
	check(rt.device.sharc.active and rt.device.nrd_active and not rt.device.sharc_failed,"terrain, cached paths and NRD remain active together")
	RenderingServer.call_on_render_thread(read_cache.bind(rt.device));await cache_inspected
	check(cache_readback.size()==4 and cache_readback[0]>0 and cache_readback[2]>0,"real campaign uses populated cache cells: "+str(cache_readback))
	var cached := await capture("sharc-on")
	check(mean_difference(original,cached)>0.00001,"SHaRC changes actual indirect world lighting")
	GameData.options.pt_mode=1;await frames(20)
	check(rt.device.sharc.active and rt.stats.path_bounces==2,"two-bounce query permutation is usable")
	GameData.options.pt_mode=2;await frames(20)
	var lamp := OmniLight3D.new();lamp.light_color=Color(1,0.02,0.01);lamp.light_energy=5;lamp.omni_range=15
	lamp.add_to_group(Gfx.POINT_LIGHT_GROUP);game.add_child(lamp)
	lamp.global_position=camera.global_position-camera.global_basis.z*8+Vector3.DOWN*2
	await frames(30);var lit := await capture("sharc-lamp-red")
	var resets: int=rt.device.sharc.resets
	lamp.light_color=Color(0.01,0.02,1);lamp.global_position+=Vector3.RIGHT*2
	await frames(6)
	check(rt.device.sharc.resets>resets,"moving/recolouring a local light invalidates production cache history")
	var blue := await capture("sharc-lamp-blue")
	check(mean_difference(lit,blue)>0.0001,"local-light colour and position change the rendered scene")
	lamp.queue_free();await frames(8)
	check(rt.device.sharc.active and rt.device.output_ready(),"removing a transient lamp retains working cached PT")
	GameData.options.pt_accumulation=1;await frames(20)
	check(not rt.device.sharc.active and rt.device._sharc_mode==0,"production Still scene bypasses SHaRC")
	GameData.options.pt_accumulation=0
	check(await select_sharc(rt,true),"returning to Responsive restores SHaRC")
	var old_generation: int=rt.stats.get("snapshot_generation",0)
	camera.global_position+=Vector3(20,0,0)
	check(await ready_scene(rt),"camera travel completes a fresh scene generation")
	await frames(20)
	check(rt.stats.get("snapshot_generation",0)>old_generation and rt.device.sharc.active and rt.device.nrd_active,
		"streamed scene replacement owns a fresh cache and retains NRD")
	check(await select_sharc(rt,false),"live Off restores original PT without unloading the scene")
	check(rt.device.sharc._owned.is_empty() and rt.device.output_ready(),"Off releases all cache memory")
	GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(20)
	check(rt.device==null and not Gfx.path_trace_active,"leaving PT disposes both scene and cache")
	await finish_live(context,rt)
func finish_live(context: Array,rt: Node) -> void:
	FileAccess.open(out.path_join("sharc-live.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"cave":cave,"counters":Array(cache_readback),"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("SHARC_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
