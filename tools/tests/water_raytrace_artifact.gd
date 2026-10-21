extends Node
## Rendered regression for reverse-facing water at the gz3g river bank.
var out := "user://water-rt-artifact"
var t: EITerrain
var camera: Camera3D

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name+".png"))

func _ready() -> void: run.call_deferred()

func setup() -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":0,"vsync":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"gfx_water":1,"gfx_water_reflections":2,"gfx_sky":1,"autosave":0,"show_tutorial":0,
		"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size = "1280x720"
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280,720))
	Engine.max_fps = 60
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var s := Session.new(); add_child(s); s.set_physics_process(false)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	var zone := s.campaign.zone_by_map("zone3obr")
	s._enter_zone(zone.id,1,false); s.state.world_time = 12.0
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear()
	g.rig.set_process(false); g.direct.set_process(false)
	g.hud.process_mode = Node.PROCESS_MODE_DISABLED; g.hud.hide()
	camera = Camera3D.new(); g.add_child(camera)
	camera.fov = 65; camera.near = 0.08; camera.current = true
	for u: GameUnit in s.world.units.values(): u.hide(); u.set_process(false)
	t = s.world.terrain
	var tree: Node3D = s.world.objects[4442]
	for i in 32:
		var angle := i*TAU/32
		var p := Vector2(tree.global_position.x,-tree.global_position.z)+Vector2(cos(angle),sin(angle))*14.0
		var level := t.water_at(p.x,p.y)
		if not is_finite(level) or t.height_at(p.x,p.y) >= level-0.3: continue
		camera.global_position = Vector3(p.x,level+1.8,-p.y)
		camera.look_at(tree.global_position+Vector3.UP*1.8)
		break
	await frames(30)
	g.set_process(false); t.set_process(false)
	print("ARTIFACT_CAMERA ",camera.global_transform)
	return [s,g]

var failures := []
var checks := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out.path_join(name+".png"))
	return image

func compare(fixed: Image, old: Image, label: String) -> void:
	# Only the reported foreground wedge, excluding the sky and distant river.
	# A negative control restores the signed cosine so a blank/moved camera
	# or a fixture which never draws the reverse face cannot pass.
	var count := 0; var before := 0.0; var after := 0.0
	for y in range(630,720):
		for x in range(740,865):
			var a := old.get_pixel(x,y)
			if a.r < 0.25 and a.g > 0.43 and a.b > 0.55:
				count += 1; before += a.b; after += fixed.get_pixel(x,y).b
	check(count > 100,label+": signed-cosine control reproduces the cyan wedge")
	before /= maxf(count,1); after /= maxf(count,1)
	check(before-after > 0.15 and after > 0.1,label+": reverse face retains visible water without full sky reflection")
	# Front-facing water away from the folded surface should stay unchanged.
	var error := 0.0
	for y in range(565,590):
		for x in range(950,1000):
			var a := fixed.get_pixel(x,y); var b := old.get_pixel(x,y)
			error += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
	error /= 25*50*3
	check(error < 0.015,label+": front-facing reflections are preserved")
	rows.append({"case":label,"wedge_pixels":count,"old_blue_mean":before,"fixed_blue_mean":after,"front_error":error})

func run() -> void:
	var context := await setup()
	var initial := camera.global_transform
	for mode in [0,2,3]:
		GameData.options.gfx_water_reflections = mode; t.apply_gfx(); await frames(8)
		if mode == 3:
			for i in 1200:
				if t._reflection._rt_ready or t._reflection._rt_failed: break
				await frames(1)
			check(t._reflection._rt_ready,"hardware RT is ready for the artifact comparison")
		var original := t._water_mat.shader
		var legacy := Shader.new()
		legacy.code = original.code.replace("clamp(abs(dot(rn, VIEW)), 0.0, 1.0)","clamp(dot(rn, VIEW), 0.0, 1.0)")
		check(legacy.code != original.code,"mode %d: negative control restores the old Fresnel"%mode)
		# Small turns exercise the same overlapping river triangles from nearby views.
		for turn in ([0.0,-0.025,0.025] if mode == 3 else [0.0]):
			camera.global_transform = initial; camera.rotate_y(turn)
			var label := "mode-%d-turn-%s"%[mode,str(turn)]
			t._water_mat.shader = legacy; await frames(15)
			var old := await capture(label+"-before")
			t._water_mat.shader = original; await frames(45)
			var fixed := await capture(label+"-fixed")
			compare(fixed,old,label)
		camera.global_transform = initial
	FileAccess.open(out.path_join("artifact.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":rows},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
