extends Node
## Rendered courtyard checks and captures; run with a desktop renderer.

var checks := 0
var failures: Array[String] = []
var screen: ArenaPveScreen
var errors := preload("arena_pve_ui.gd").Errors.new()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func frames(count := 30) -> void:
	for i in count: await get_tree().process_frame

func shot(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://field-" + label + ".png")

func _ready() -> void:
	OS.add_logger(errors)
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 800)
	var saved := GameData.options.duplicate()
	var old_fog := [Gfx.fog_sky, Gfx.fog_color, Gfx.fog_depth]
	var old_light := [Gfx.ambient, Gfx.sun, Gfx._cloud_sun_direction]
	var native_hash := hash(GameData.db.tables)
	screen = ArenaPveScreen.new()
	add_child(screen)
	await frames()
	screen._seed_input.text = "6519"
	screen._begin(0)
	screen.run.auto_save = false
	screen.run.wave = 4
	screen.run.pact = "vanguard"
	screen.run.army.clear()
	for family in [0, 1, 2, 3]: screen.run._recruit(family, 0, 3)
	screen.run.arrange()
	screen._clear_selection()
	await shot("shadows")
	screen._show_company()
	await shot("company")
	screen._clear_selection()
	screen.field.zoom = 8
	screen.field._update_camera()
	await shot("close")
	screen.field.reset_camera()
	screen.run.wave = 18
	screen.run.pact_rank = 2
	screen.run.army.clear()
	for family in ArenaRules.FAMILIES.size():
		var rank: int = ArenaRules.FAMILIES[family].forms.size() - 1
		screen.run._recruit(family, rank, 27)
	screen.run._recruit(-1, 0, 18, "orcfemalem5")
	screen.run.arrange()
	screen._clear_selection()
	await frames(90)
	var terrain := screen.battle.world.terrain
	var data_hash := hash([terrain.heights, terrain.ground, terrain.surface, terrain.water])
	check(terrain.details is ArenaGroundDetails, "courtyard owns visual grass variant")
	await shot("late-prepare")
	for options: Dictionary in [
		{"gfx_grass":0, "gfx_biome_cover":0, "gfx_contact_shadows":0, "gfx_ssao":0, "q_aa":1, "q_shadows":0},
		{"gfx_grass":1, "gfx_wind":0, "gfx_vegetation_interaction":0, "gfx_contact_shadows":1, "gfx_ssao":1, "q_aa":3, "q_shadows":2},
		{"gfx_grass":1, "gfx_wind":1, "gfx_vegetation_interaction":1, "gfx_biome_cover":1},
	]:
		GameData.options.merge(options, true)
		GameData.options_changed.emit()
		await frames(90)
		check(terrain.details is ArenaGroundDetails, "option refresh keeps arena presentation")
		check(screen.field._environment.ssao_enabled == Gfx.on("gfx_ssao"), "arena AO follows graphics option")
		check(screen.field.view.msaa_3d == (Viewport.MSAA_4X if GameData.option("q_aa") == 3 else Viewport.MSAA_DISABLED), "arena AA follows graphics option")
		check(is_equal_approx(screen.field._sun_light.shadow_blur, 1.8 if GameData.option("q_shadows") >= 2 else 1.0), "shadow filter matches quality budget")
		check(hash([terrain.heights, terrain.ground, terrain.surface, terrain.water]) == data_hash, "visual options preserve physical field")
		if options.gfx_grass:
			check(terrain.details._material.shader.code.contains("arena_court_edge"), "grass stays clear of courtyard")
			check(not TerrainDetails._base_shader.code.contains("arena_court_edge"), "campaign grass shader is unchanged")
			if options.get("gfx_biome_cover", 0):
				check(terrain.details._cover_material.shader.code.contains("arena_court_edge"), "optional cover respects courtyard")
		for unit: GameUnit in screen.battle.world.unit_rows():
			var shadow := unit.get_meta("contact_shadow") as Decal if unit.has_meta("contact_shadow") else null
			check(shadow != null and shadow.visible == Gfx.on("gfx_contact_shadows"), "contact shadow follows option")
		await shot("options-" + str(checks))
	GameData.options.assign(saved)
	GameData.options_changed.emit()
	await frames(30)
	screen.field.zoom = 35
	screen.field._update_camera()
	await shot("wide")
	for angle in [-PI / 2, 0.0, PI / 2, PI]:
		screen.field.yaw = angle
		screen.field._update_camera()
		for unit: GameUnit in screen.battle.world.unit_rows():
			var local := screen.field.camera.to_local(unit.global_position)
			check(-local.z > screen.field.camera.near and -local.z < screen.field.camera.far, "wide rotated view contains every combatant")
		if angle == 0.0: await shot("wide-rotated")
	screen.field.reset_camera()
	screen._start.pressed.emit()
	await get_tree().create_timer(3.0).timeout
	await shot("late-combat")
	screen.queue_free()
	await frames()
	check([Gfx.fog_sky, Gfx.fog_color, Gfx.fog_depth] == old_fog, "arena restores the previous scene palette")
	check([Gfx.ambient, Gfx.sun, Gfx._cloud_sun_direction] == old_light, "arena restores previous scene lighting")
	check(hash(GameData.db.tables) == native_hash, "presentation preserves native stats")
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no rendering or script errors: " + str(errors.messages))
	print("ARENA_PVE_VISUAL ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
