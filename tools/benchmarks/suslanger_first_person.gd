extends Node
## Same-process original/optimized contact query at 4K Ultra, native first-person
## eye and full HUD. Simulation is held to isolate rendering. Camera/aim CPU work
## is measured separately; these timings are not a live-game FPS guarantee.
var session: Session
var game: Game

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	var zone := "gz17h"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="): zone = arg.trim_prefix("--zone=")
	var view := SubViewport.new(); view.size = Vector2i(3840,2160); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_parent().add_child(view); reparent(view)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"control_mode":3,"pad_enabled":0,"scroll_border":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	session = Session.new(); add_child(session); session.set_physics_process(false)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero"); session.state.world_time = 12
	await session.enter_zone(zone,1,false)
	session.world.set_physics_process(false); session.world.vm.instances.clear()
	var hero: GameUnit = session.world.party_units()[0]
	hero.blocked = false; game.selected.assign([hero]); game.rig.release()
	await frames(24)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(320,320)
	game.rig.set_process(false); game.direct.set_process(false); game.direct.pointer = false
	game.rig._window_focused = true
	var aim: Vector2 = session.world.terrain.size_ei()*0.5 - hero.pos
	game.direct.heading = atan2(aim.y,aim.x); game.direct.tilt = -0.12
	game.direct.apply_camera()
	Gfx.apply_quality(view)
	await frames(60)
	var cpu := {}
	for operation in ["camera","aim"]:
		var times := []
		for i in 160:
			var begin := Time.get_ticks_usec()
			if operation == "camera": game.direct.apply_camera(1.0/60.0)
			else: DirectCombat.preview(hero,game.rig.camera.global_position,-game.rig.camera.global_basis.z)
			times.append((Time.get_ticks_usec()-begin)/1000.0)
		times.sort(); cpu[operation] = {"median_ms":times[80],"p95_ms":times[152]}
	var owner: GroundContact = session.world.terrain.contact
	var pairs := []
	for shader: Shader in owner._shaders.values():
		assert(shader.code.contains("#define EI_CONTACT_QUERY_MASK"))
		pairs.append([shader,shader.code.replace("#define EI_CONTACT_QUERY_MASK",""),shader.code])
	var rows := []
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	for pass_id in 6:
		var optimized := pass_id % 2 == 1
		for pair: Array in pairs: pair[0].code = pair[2] if optimized else pair[1]
		owner.refresh_parameters()
		await frames(48)
		var gpu := []; var render_cpu := []; var intervals := []
		var previous := Time.get_ticks_usec()
		for i in 160:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			intervals.append((now-previous)/1000.0); previous = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		gpu.sort(); render_cpu.sort(); intervals.sort()
		var row := {"optimized":optimized,"gpu_median_ms":gpu[80],"gpu_p95_ms":gpu[152],"render_cpu_median_ms":render_cpu[80],"frame_median_ms":intervals[80],"frame_p95_ms":intervals[152]}
		rows.append(row); print("FIRST_PERSON_RENDER ",zone," ",JSON.stringify(row))
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("user://first-person-"+zone+".png")
	var report := {"zone":zone,"size":str(view.size),"options":GameData.options,"camera":str(game.rig.camera.global_transform),"cpu":cpu,"rows":rows,"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Frozen simulation, native first-person eye, full HUD, same-process shader A/B at 4K Ultra."}
	FileAccess.open("user://first-person-"+zone+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.free(); session.free(); await frames(2); TexUpscale.shutdown(); get_tree().quit()
