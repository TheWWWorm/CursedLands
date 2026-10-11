extends Node
var out := "user://"
var rows := []
var failures := []
func frames(n:=4) -> void:
	for i in n: await get_tree().process_frame
func check(ok:bool, label:String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":0,"vsync":0,"confine_mouse":0,
		"gfx_water":1,"gfx_water_reflections":2,"autosave":0,"show_tutorial":0,"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="1280x720";GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720))
	Engine.max_fps=60;RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var s:=Session.new();add_child(s);s.set_physics_process(false)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	var zone:=s.campaign.zone_by_map("zone3obr")
	s._enter_zone(zone.id,1,false);s.state.world_time=19.5
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.rig.set_process(false);g.direct.set_process(false);g.hud.process_mode=Node.PROCESS_MODE_DISABLED;g.hud.hide()
	var camera:=Camera3D.new();g.add_child(camera);camera.fov=65;camera.near=0.08;camera.current=true
	for u:GameUnit in s.world.units.values():u.visible=false;u.set_process(false)
	await frames(50)
	g.set_process(false);s.world.terrain.set_process(false)
	var t:=s.world.terrain
	check(not is_instance_valid(t._reflection),"fallback renderer does not allocate a planar viewport")
	camera.global_position=Vector3(183.065,8.676689,-150.5906);camera.look_at(Vector3(171.2955,7.045171,-148.2495))
	for mode in [0,1,2]:
		GameData.options.gfx_water_reflections=mode;t.apply_gfx();await frames(10);await RenderingServer.frame_post_draw
		check(not is_instance_valid(t._reflection),"fallback water mode %d stays on its original renderer path"%mode)
		get_viewport().get_texture().get_image().save_png(out.path_join("fallback-%d.png"%mode))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	FileAccess.open(out.path_join("reflection-fallback.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":4,"failures":failures},"\t"))
	print("REFLECTION_FALLBACK 4 checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
