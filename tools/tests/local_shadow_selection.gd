extends Node3D
## Exercise the actual light manager with camera/focus movement, not a copy of
## its ranking algorithm. --shadow-control=/absolute/old_local_lighting.gd
## accepts the previous script with its class_name declaration removed.
var checks := 0
var failures := 0
var control: Script
var churn := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func fixture() -> Dictionary:
	var game := Game.new()
	var world := GameWorld.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(world)
	game.world = world
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 18, 26)
	camera.look_at(Vector3(0, 2, 0))
	camera.current = true
	var manager = control.new(game) if control else LocalLighting.new(game)
	add_child(manager)
	manager.set_process(false)
	manager._world = world
	return {"game": game, "world": world, "camera": camera, "manager": manager,
			"fx": ParticleFx.of(world)}

func dispose(f: Dictionary) -> void:
	f.manager.free()
	f.game.free()
	f.world.free()
	f.camera.free()

func fire(f: Dictionary, p: Vector3) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = p
	light.omni_range = 8.0
	f.world.add_child(light)
	var d := {"light": light, "kind": "fire", "energy": 1.0, "pos": p, "until": -1}
	LocalLighting.prepare_particle(d)
	f.fx.lights.append(d)
	return light

func clustered_fire(f: Dictionary) -> Array[OmniLight3D]:
	for z in [-1.0, 0.0, 1.0]:
		fire(f, Vector3(0, 2, z))
	return [fire(f, Vector3(-10, 2, 0)), fire(f, Vector3(10, 2, 0))]

func scan(f: Dictionary, time: float, x: float) -> Array:
	f.manager._time = time
	f.manager._assign_shadows(f.fx, f.camera, Vector3(x, 2, 0))
	var ids := []
	var lava := 0
	for d: Dictionary in f.fx.lights + f.manager._lava:
		if is_instance_valid(d.light) and d.light.shadow_enabled:
			ids.append(d.light.get_instance_id())
			lava += int(d.has("cell"))
			var marker := Gfx.LOCAL_SPECULAR_PASS if Portability.compatibility() else Gfx.LOCAL_SPECULAR
			check(is_equal_approx(d.light.light_specular, marker), "selected light retains renderer pass marker")
	check(ids.size() <= 4 and lava <= 2, "shared four-shadow and two-lava limits hold")
	if not control:
		check(f.manager._shadow_since.size() == ids.size(), "tenure state only contains current selections")
	ids.sort()
	return ids

func test_hold_and_churn() -> void:
	var f := fixture()
	var pair := clustered_fire(f)
	scan(f, 0, -2)
	check(pair[0].shadow_enabled and not pair[1].shadow_enabled, "initial selection prefers nearer torch")
	scan(f, 0.25, 2)
	check(pair[0].shadow_enabled, "brief focus reversal keeps new incumbent")
	scan(f, 1.75, 2)
	check(pair[0].shadow_enabled, "eligible torch keeps two-second minimum tenure")
	scan(f, 2, 2)
	check(pair[1].shadow_enabled and not pair[0].shadow_enabled, "better challenger wins when tenure expires")
	scan(f, 2.25, -2)
	check(pair[1].shadow_enabled, "replacement receives its own full tenure")
	scan(f, 4, -2)
	check(pair[0].shadow_enabled, "continued movement can replace the next incumbent")
	f.fx.lights.reverse()
	scan(f, 6, -0.1)
	check(pair[0].shadow_enabled, "record reordering does not disturb nearly equal incumbents")
	Gfx.set_local_shadow(pair[0], false)
	scan(f, 6.25, -2)
	scan(f, 6.5, 2)
	check(pair[0].shadow_enabled, "externally disabled and reselected light receives fresh tenure")
	dispose(f)
	f = fixture()
	clustered_fire(f)
	var previous := scan(f, 0, -2)
	for tick in range(1, 32):
		var selected := scan(f, tick * 0.25, 2 if tick % 2 else -2)
		churn += int(selected != previous)
		previous = selected
	check(churn <= 4, "eight-second focus oscillation does not exchange shadows every scan")
	dispose(f)

func test_eligibility() -> void:
	var f := fixture()
	var pair := clustered_fire(f)
	scan(f, 0, -2)
	pair[0].hide()
	scan(f, 0.25, -2)
	check(not pair[0].shadow_enabled and pair[1].shadow_enabled, "hidden light releases tenure immediately")
	pair[1].position = Vector3(500, 2, 0)
	scan(f, 0.5, -2)
	check(not pair[1].shadow_enabled, "carried light leaving view/range releases tenure immediately")
	pair[0].free()
	scan(f, 0.75, -2)
	check(true, "freed particle light record is tolerated")
	dispose(f)
	f = fixture()
	var light := fire(f, Vector3(0, 2, 0))
	for row: Array in [[64.0, true], [66.0, true], [70.0, false], [66.0, false], [64.0, true]]:
		f.camera.position = light.global_position + Vector3(0, 0, row[0])
		f.camera.look_at(light.global_position)
		scan(f, 0.25, 0)
		check(light.shadow_enabled == row[1], "65 m entry and 69 m exit use separate thresholds")
	light.queue_free()
	scan(f, 0.5, 0)
	check(not light.shadow_enabled, "queued light releases its shadow before destruction")
	dispose(f)

func lava(f: Dictionary, entries: Array[Dictionary]) -> void:
	f.manager._sync_lava(entries)
	# The regular _process fades these on. These scenarios start after that fade.
	for d: Dictionary in f.manager._lava:
		d.light.visible = d.active
		d.light.light_energy = 0.58 if d.active else 0.0

func lava_ids(f: Dictionary) -> Array:
	var cells := []
	for d: Dictionary in f.manager._lava:
		if d.light.shadow_enabled:
			cells.append(d.cell)
	cells.sort()
	return cells

func test_lava_and_lifetime() -> void:
	var f := fixture()
	clustered_fire(f)
	check(scan(f, 0, -2).size() == 4, "fire can fill the budget before lava appears")
	var entries: Array[Dictionary] = [{"cell": 1, "pos": Vector3(-10, 1, 0)},
			{"cell": 2, "pos": Vector3(0, 1, 0)}, {"cell": 3, "pos": Vector3(10, 1, 0)}]
	lava(f, entries)
	check(scan(f, 0, -2).size() == 4 and lava_ids(f) == [1, 2], "lava reserves two of four shared shadows")
	scan(f, 0.25, 2)
	check(lava_ids(f) == [1, 2], "lava also keeps minimum tenure")
	scan(f, 2, 2)
	check(lava_ids(f) == [2, 3], "lava challenger wins after hold")
	scan(f, 5, -0.1)
	check(lava_ids(f) == [2, 3], "nearly equal lava banks keep incumbent after hold")
	f.manager._disable_shadows(f.fx)
	scan(f, 6, -2)
	var reused: OmniLight3D = f.manager._lava[0].light
	lava(f, [entries[1], entries[2], {"cell": 4, "pos": Vector3(30, 1, 0)}])
	scan(f, 6.25, -2)
	check(f.manager._lava[0].light == reused and lava_ids(f) == [2, 3], "new lava cell never inherits pooled node tenure")
	lava(f, [])
	check(scan(f, 6.5, -2).size() == 4 and lava_ids(f).is_empty(), "inactive lava immediately returns slots to fire")
	GameData.options["gfx_firelight"] = 0
	f.manager.apply_options()
	for d: Dictionary in f.fx.lights:
		check(not d.light.shadow_enabled and d.light.light_specular == d.original.light_specular,
				"option off restores original shadow and pass properties")
	if not control:
		check(f.manager._shadow_since.is_empty(), "option off clears tenure immediately")
	GameData.options["gfx_firelight"] = 1
	f.manager.apply_options()
	scan(f, 6.75, 2)
	f.manager._disable_shadows(f.fx)
	check(scan(f, 7, -2).has(f.fx.lights[3].light.get_instance_id()), "no-camera reset permits a fresh selection")
	f.game.world = null
	f.manager._process(0.25)
	check(f.manager._lava.is_empty(), "world change clears pooled lava")
	if not control:
		check(f.manager._shadow_since.is_empty(), "world change clears all tenure")
	dispose(f)

func capture(view: SubViewport, label: String) -> Image:
	for i in 8:
		RenderingServer.force_draw()
		await get_tree().process_frame
	var pixels := view.get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	check(pixels.save_png("user://local-shadows-" + RenderingServer.get_current_rendering_method()
			+ "-" + label + ".png") == OK, "shadow capture saved")
	return pixels

func changed_pixels(a: Image, b: Image) -> int:
	var first := a.get_data()
	var second := b.get_data()
	var count := 0
	for p in range(0, first.size(), 4):
		for c in 3:
			if absi(first[p + c] - second[p + c]) > 2:
				count += 1
				break
	return count

func test_rendered_transitions() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Engine.max_fps = 30
	GameData.options["gfx_volumetric"] = 0
	var view := SubViewport.new()
	view.size = Vector2i(640, 480)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.positional_shadow_atlas_size = 2048
	add_child(view)
	var f := fixture()
	f.world.reparent(view)
	f.camera.reparent(view)
	f.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	f.camera.size = 8
	f.camera.position = Vector3(0, 0, 8)
	f.camera.rotation = Vector3.ZERO
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	view.add_child(env)
	Gfx.ensure_globals()
	Gfx.set_light(Color(0.16, 0.16, 0.18), Color(0.25, 0.25, 0.3))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", Vector3.BACK)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 100, 0))
	view.add_child(DirectionalLight3D.new())
	var pixels := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.7, 0.7, 0.7))
	var material := ShaderMaterial.new()
	material.shader = Gfx.make_shader(EIFigure.OBJECT_SHADER)
	material.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(pixels))
	var plane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(12, 10)
	plane.mesh = quad
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(plane)
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 1.5, 0.2)
	blocker.mesh = box
	blocker.position.z = 1
	blocker.material_override = material
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	view.add_child(blocker)
	for z in [-1.0, 0.0, 1.0]:
		var anchor := fire(f, Vector3(0, 2, z))
		anchor.light_energy = 0.03
	var pair: Array[OmniLight3D] = [fire(f, Vector3(-2, 2, 3)), fire(f, Vector3(2, 2, 3))]
	for light in pair:
		light.light_energy = 0.7
		light.omni_attenuation = 0.0
	scan(f, 0, -2)
	check(pair[0].shadow_enabled and not pair[1].shadow_enabled, "GPU fixture selects left torch first")
	var before := await capture(view, "initial")
	scan(f, 0.25, 2)
	var held := await capture(view, "held")
	check(before.get_data() == held.get_data(), "minimum tenure preserves actual rendered shadow pixels")
	scan(f, 2, 2)
	check(pair[1].shadow_enabled and not pair[0].shadow_enabled, "GPU fixture selects right torch after tenure")
	var replaced := await capture(view, "replaced")
	var replacement_pixels := changed_pixels(before, replaced)
	check(replacement_pixels > 100, "expired tenure changes a visible shadow, not an empty fixture")
	blocker.position.x += 0.6
	scan(f, 2.25, 2)
	var moved_caster := await capture(view, "moved-caster")
	var caster_pixels := changed_pixels(replaced, moved_caster)
	check(caster_pixels > 100, "selected shadow follows moving caster during tenure")
	pair[1].position.x += 0.6
	scan(f, 2.5, 2)
	var moved_light := await capture(view, "moved-light")
	var light_pixels := changed_pixels(moved_caster, moved_light)
	check(pair[1].shadow_enabled and light_pixels > 100, "carried light updates its shadow while selected")
	print("LOCAL_SHADOW_GPU ", JSON.stringify({"replacement_pixels": replacement_pixels,
			"moving_caster_pixels": caster_pixels, "moving_light_pixels": light_pixels,
			"held_pixels": changed_pixels(before, held), "adapter": RenderingServer.get_video_adapter_name()}))
	dispose(f)
	view.free()

func _ready() -> void:
	GameData.options["gfx_firelight"] = 1
	GameData.options["gfx_lava_light"] = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shadow-control="):
			control = load(arg.trim_prefix("--shadow-control="))
	test_hold_and_churn()
	test_eligibility()
	test_lava_and_lifetime()
	if DisplayServer.get_name() != "headless":
		await test_rendered_transitions()
	print("LOCAL_SHADOW_SELECTION ", JSON.stringify({"checks": checks, "failures": failures,
			"selection_changes": churn, "control": control != null,
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor")}))
	get_tree().quit(1 if failures else 0)
