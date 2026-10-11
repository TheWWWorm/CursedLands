extends Node
## Rendered regression at Dead City's Banshee pond near the Hadagan camp.
## Run with the original campaign on Forward+ and --audit-out=<directory>.
const Reflection := preload("res://src/game/fx/water_reflection.gd")
var out := "user://water-reflection-combat"
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)


func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame


func capture(label: String, reflection: Node) -> Dictionary:
	await frames()
	await RenderingServer.frame_post_draw
	var main := get_viewport().get_texture().get_image()
	var mirror: Image = reflection.viewport.get_texture().get_image()
	main.save_png(out.path_join(label + ".png"))
	mirror.save_png(out.path_join(label + "-reflection.png"))
	return {"main": main.get_data(), "mirror": mirror.get_data()}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not Reflection.supported() or GameData.campaign_id != CampaignProfile.ORIGINAL:
		print("SKIP water_reflection_combat requires rendered Forward+ and original campaign data")
		get_tree().quit()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"display_mode": 0, "auto_graphics": 0, "q_aa": 1,
		"q_shadows": 0, "vsync": 0, "confine_mouse": 0, "gfx_water": 1,
		"gfx_water_reflections": 2, "gfx_soft_particles": 1, "gfx_torch_glow": 1,
		"gfx_heat_haze": 1, "autosave": 0, "show_tutorial": 0, "unit_fog": 0,
		"net_upnp": 0, "net_lan": 0, "net_directory": 0}, true)
	GameData.resolution_size = "1280x720"
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1280, 720))
	Engine.max_fps = 60
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var session := Session.new()
	add_child(session)
	session.set_physics_process(false)
	var game := Game.new()
	game.session = session
	session.game = game
	add_child(game)
	session.state.ensure_hero(0, "Human Hero")
	session._enter_zone("gz9g", 1, false)
	session.state.world_time = 12.0
	session.set_physics_process(false)
	var world := session.world
	world.set_process(false)
	world.set_physics_process(false)
	world.vm.instances.clear()
	game.rig.set_process(false)
	game.direct.set_process(false)
	game.hud.hide()
	for unit: GameUnit in world.units.values(): unit.set_process(false)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.fov = 65
	camera.near = 0.08
	camera.current = true
	await frames(4)
	# Freeze animation, lighting and effect clocks for exact image comparisons.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	world.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.hide()
	var terrain := world.terrain
	var reflection := terrain._reflection
	reflection.set_process(false)
	var actor: GameUnit = world.units[1535]
	var pond := Vector2(85.5, 233.5)
	var level := terrain.water_at(pond.x, pond.y)
	check(is_finite(level) and terrain.height_at(pond.x, pond.y) < level - 0.2,
		"fixture uses original Dead City pond water")
	camera.global_position = Vector3(97.94248, 19.64636, -245.278)
	camera.look_at(actor.global_position + Vector3.UP)
	reflection._process(0.2)
	check(terrain._water_mat.get_shader_parameter("planar_enabled") == true,
		"pond selects a live reflected scene view")
	check(absf(reflection.plane - level) < 0.15, "reflection uses the pond's authored level")
	var fx := ParticleFx.of(world)
	fx.set_process(false)
	fx.spawn(0x2028, Vector3.ZERO, 1.0, actor, {"prewarm": 20})
	fx._tick()
	fx._process(0.01)
	var combat := await capture("combat", reflection)
	fx.hide()
	var quiet := await capture("quiet", reflection)
	check(combat.mirror != quiet.mirror, "original blue spell particles remain reflected")
	fx.show()
	var halo := Gfx.torch_halo(7.0, Color(0.2, 0.4, 1.0))
	game.add_child(halo)
	halo.global_position = Vector3(pond.x, level + 1.0, -pond.y)
	var halo_source: String = Gfx._halo_shader.code
	for night in [false, true]:
		RenderingServer.global_shader_parameter_set(&"ei_sun", Vector3.ONE * (0.2 if night else 1.0))
		var label := "night" if night else "day"
		halo.hide()
		var without := await capture(label + "-without-halo", reflection)
		halo.show()
		# Negative control: the original helper exposes a rectangular alpha
		# footprint even in daylight when the visible glow is zero.
		Gfx._halo_shader.code = Gfx.HALO_SHADER
		var old := await capture(label + "-old-halo", reflection)
		check(old.mirror != without.mirror, label + ": old halo reproduces reflected quad")
		Gfx._halo_shader.code = halo_source
		var fixed := await capture(label + "-fixed-halo", reflection)
		check(fixed.mirror == without.mirror, label + ": halo adds no square to reflection")
		if night:
			check(fixed.main != without.main, "night halo remains visible in the main camera")
		observations.append({"night": night, "old_quad": old.mirror != without.mirror,
			"fixed_exact_match": fixed.mirror == without.mirror})
	halo.hide()
	var haze := Gfx.heat_haze(3.0)
	game.add_child(haze)
	haze.global_position = halo.global_position
	haze.hide()
	var no_haze := await capture("without-haze", reflection)
	haze.show()
	var with_haze := await capture("with-haze", reflection)
	check(with_haze.mirror == no_haze.mirror, "screen distortion stays out of the mirror view")
	haze.hide()
	var marker := fx.spawn(0x203a, ParticleFx.ei(actor.global_position), 1.0, null, {"prewarm": 2})
	fx._tick()
	fx._process(0.01)
	check(marker.mmi != null and marker.mmi.multimesh.visible_instance_count > 0,
		"target marker has live visible particles")
	for through in [0, 1]:
		GameData.options.path_through = through
		marker.mmi.material_override = fx._material_of(marker.e)
		marker.mmi.hide()
		var hidden := await capture("marker-%d-hidden" % through, reflection)
		marker.mmi.show()
		var shown := await capture("marker-%d-visible" % through, reflection)
		check(shown.mirror == hidden.mirror, "target marker is not reflected, through=%d" % through)
		check(shown.main != hidden.main, "target marker remains visible, through=%d" % through)
	FileAccess.open(out.path_join("verification.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"zone": "gz9g", "map": "zone9", "actor": actor.uid, "water": str(pond),
		"plane": reflection.plane, "observations": observations, "checks": checks,
		"failures": failures}, "\t"))
	game.queue_free()
	session.queue_free()
	await frames(10)
	TexUpscale.shutdown()
	print("WATER_REFLECTION_COMBAT checks=", checks, " failures=", failures.size())
	get_tree().quit(int(not failures.is_empty()))
