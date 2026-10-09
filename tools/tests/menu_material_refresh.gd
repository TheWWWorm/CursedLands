extends Node
## Real menu labels must keep their caller-owned materials across live graphics
## changes, including scenery contact enabled before or after menu creation.
const SIZE := Vector2i(1000, 893)
const NEW_OPTIONS := {"gfx_biome_cover":1, "gfx_vegetation_interaction":1, "gfx_ground_contact":1,
	"gfx_terrain_cliffs":1, "gfx_depth_of_field":1, "gfx_water_interaction":1,
	"gfx_water_caustics":1, "gfx_water_current":1, "gfx_water_waves":1, "gfx_waterfalls":1,
	"gfx_ambient_wildlife":1, "gfx_ambient_particles":1, "gfx_clouds":3, "gfx_weather_mist":1}
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var view: SubViewport


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func settle(count := 6) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame


func apply(values: Dictionary) -> void:
	for key in values:
		GameData.set_option(key, values[key])
		await get_tree().process_frame
	await settle()


func labels(menu: MenuScene) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mesh: MeshInstance3D in menu._column.find_children("*", "MeshInstance3D", true, false):
		var part := String(mesh.get_parent().name)
		if part.begins_with("but") and not part.begins_with("button"):
			out.append({"node":mesh, "material":mesh.material_override, "part":part})
	return out


func record(menu: MenuScene, originals: Array[Dictionary], label: String) -> void:
	await settle()
	var changed: Array[String] = []
	var wrong_labels: Array[String] = []
	var hover_refs := 0
	for entry in originals:
		var material := (entry.node as MeshInstance3D).material_override
		if material != entry.material:
			changed.append(entry.part)
		if not material is StandardMaterial3D or material.albedo_texture == null:
			wrong_labels.append(entry.part)
		for materials: Array in menu._mats.values():
			if materials.has(entry.material):
				hover_refs += 1
	check(changed.is_empty(), label + " retains exact menu label materials: " + str(changed))
	check(wrong_labels.is_empty(), label + " keeps textured menu labels: " + str(wrong_labels))
	check(hover_refs == originals.size(), label + " retains menu button material references")
	var image := view.get_texture().get_image()
	check(image.save_png("user://menu-material-" + label + ".png") == OK, label + " capture saved")
	rows.append({"label":label, "labels":originals.size(), "changed":changed, "wrong_labels":wrong_labels,
		"hover_references":hover_refs, "contact":GameData.options.gfx_ground_contact,
		"animation":menu._player.assigned_animation})


func scenario(startup_contact: bool) -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):
			GameData.options[option[0]] = 1
	for key in NEW_OPTIONS:
		GameData.options[key] = NEW_OPTIONS[key] if startup_contact else 0
	GameData.options.gfx_terrain = 2
	Gfx.apply_surface_options()
	var prefix := "startup-on" if startup_contact else "startup-off"
	var menu := MenuScene.create()
	check(menu != null, prefix + " real menu created")
	if menu == null:
		return
	view.add_child(menu)
	menu.set_hour(21.75)
	menu.set_process(false)
	menu.rain_bit = false
	menu.camera.current = true
	menu._player.pause()
	var originals := labels(menu)
	check(originals.size() == MenuScene.BOARDS.size(), prefix + " has all six labelled boards")
	await record(menu, originals, prefix + "-initial")
	# The actual setter performs the same save, renderer update and signal as
	# the Options dialog. The runner gives this test its own settings directory.
	await apply(NEW_OPTIONS)
	await record(menu, originals, prefix + "-live-options")
	menu._set_hover("button01_new_game")
	menu._player.advance(0.25)
	check(menu._hover == "button01_new_game" and menu._player.assigned_animation.begins_with("ei/uspecial"), prefix + " hover still plays its board animation")
	await record(menu, originals, prefix + "-hover")
	await apply({"gfx_ground_contact":0})
	await record(menu, originals, prefix + "-contact-off")
	await apply({"gfx_ground_contact":1})
	await record(menu, originals, prefix + "-contact-on-again")
	menu.free()
	await settle()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	GameData.options.merge({"auto_graphics":0, "confine_mouse":0, "q_aa":0, "q_shadows":2,
		"volume_sfx":0, "volume_stream":0, "volume_voice":0, "show_fps":0}, true)
	Gfx.ensure_globals()
	Engine.time_scale = 0
	Engine.max_fps = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	view = SubViewport.new()
	view.size = SIZE
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility():
		view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	await scenario(false)
	await scenario(true)
	view.free()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	await settle(4)
	var result := {"checks":checks, "failures":failures, "rows":rows, "renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("user://menu-material-refresh.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("MENU_MATERIAL_REFRESH checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
