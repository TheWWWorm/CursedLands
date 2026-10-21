extends Node
## Matched real-map renders. The 32 m reference is the original equation
## evaluated by the remake shader; these are NOT original-executable captures.
var out := "user://border-fog"
var rows := []
var failures := []
var checks := 0
var requested_zone := ""

func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
		if arg.begins_with("--audit-zone="): requested_zone = arg.trim_prefix("--audit-zone=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"display_mode":0,
		"autosave":0,"show_tutorial":0,"unit_fog":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"gfx_wind":0,"gfx_clouds":0,"q_aa":0,"q_shadows":0}, true)
	GameData.resolution_size = "1280x720"
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280,720))
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.max_fps = 60
	var s := Session.new(); add_child(s); s.set_physics_process(false)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, "Human Hero")
	var zone := s.campaign.zone_by_map("zone1")
	if not requested_zone.is_empty(): zone = s.campaign.zones[requested_zone]
	s._enter_zone(zone.id,1,false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear()
	g.rig.set_process(false); g.direct.set_process(false)
	g.hud.process_mode = Node.PROCESS_MODE_DISABLED; g.hud.hide()
	var camera := Camera3D.new(); g.add_child(camera)
	camera.fov = 65; camera.near = 0.08; camera.far = Gfx.far_clip()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.current = true
	for u: GameUnit in s.world.units.values(): u.set_process(false)
	await frames(45)
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720)
	g.set_process(false); s.world.terrain.set_process(false)
	var t := s.world.terrain
	var size := t.size_ei()
	var poses := [
		{"name":"west-edge", "eye":Vector2(38,size.y*0.5), "target":Vector2(0,size.y*0.5), "lift":15.0},
		{"name":"northwest-corner", "eye":Vector2(35,35), "target":Vector2(0,0), "lift":20.0},
		{"name":"west-low", "eye":Vector2(26,size.y*0.5), "target":Vector2(0,size.y*0.5), "lift":3.0}]
	poses.append({"name":"playable-border", "eye":Vector2(5,76), "target":Vector2(23,111), "lift":25.0})
	for hour in [12.0, 1.0]:
		s.state.world_time = hour; g._update_daylight(false)
		for pose: Dictionary in poses:
			var eye: Vector2 = pose.eye; var target: Vector2 = pose.target
			var ground := -INF
			for i in 25:
				var p := eye.lerp(target,float(i)/24.0)
				ground = maxf(ground,t.height_at(p.x,p.y))
			camera.global_position = Vector3(eye.x,ground+float(pose.lift),-eye.y)
			var aim := Vector3(target.x,t.height_at(target.x,target.y)+2.0,-target.y)
			camera.look_at(aim); camera.make_current()
			for profile in ["no-border-control","current-16-quadratic","original-equation-32-linear"]:
				var band := Vector4(size.x,size.y,16.0,1.0)
				if profile == "no-border-control": band.z = 0.0
				if profile == "original-equation-32-linear": band.z = 32.0; band.w = 0.0
				RenderingServer.global_shader_parameter_set(&"ei_border",band)
				await frames(8); await RenderingServer.frame_post_draw
				var name := "%s-%02d-%s-%s.png" % [zone.id,int(hour),pose.name,profile]
				var im := get_viewport().get_texture().get_image()
				check(im.get_size()==Vector2i(1280,720),"fixed camera aspect "+name)
				check(im.save_png(out.path_join(name))==OK,"capture "+name)
				rows.append({"zone":zone.id,"hour":hour,"pose":pose.name,"profile":profile,
					"map_size":[size.x,size.y],"position":[camera.position.x,camera.position.y,camera.position.z],
					"target":[aim.x,aim.y,aim.z],"border":[band.x,band.y,band.z,band.w],"image":name})
	Gfx.set_border(size,6.0)
	check(Gfx._border_menu==6.0,"menu uses its separate 6 m ramp")
	Gfx.set_border(size)
	check(Gfx._border_menu==-1.0 and Gfx._border_size==size,"entering a map resets menu fog ownership")
	Gfx.refresh_border()
	check(Gfx.BORDER_FOG==16.0,"audit captures the current production band")
	FileAccess.open(out.path_join("captures.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"evidence":"Actual remake renders; original-equation profile is a controlled shader substitution, not an original-executable image.",
		"renderer":RenderingServer.get_current_rendering_method(),"campaign":GameData.campaign_id,
		"checks":checks,"failures":failures,"rows":rows},"\t"))
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	print("BORDER_FOG_AUDIT %d checks %d failures" % [checks,failures.size()])
	get_tree().quit(1 if not failures.is_empty() else 0)
