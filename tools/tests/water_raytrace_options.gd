extends "res://tools/tests/water_raytrace_artifact.gd"
## Real settings UI, persistence and live GPU targets for the RT quality tiers.
const QUALITY := "q_water_rt_quality"
const QUALITY_ROW := 2
var samples := []

func settle_window(size: Vector2i) -> void:
	# Applying settings can reframe the X11 window asynchronously. Wait for
	# that before restoring the fixed capture size used by this fixture.
	Engine.max_fps = 60
	await get_tree().create_timer(0.2,true,false,true).timeout
	get_window().borderless = true
	get_window().size = size
	await get_tree().create_timer(0.2,true,false,true).timeout
	check(Vector2i(get_viewport().get_visible_rect().size) == size,"test viewport settles to "+str(size))

func key(panel: OptionsPanel, code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	panel._unhandled_key_input(event)

func click_quality(panel: OptionsPanel) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		event.position = panel.p8(Vector2(600,panel._row_y(QUALITY_ROW)+12))
		panel._gui_input(event)

func menu_checks() -> void:
	check(GameData.option(QUALITY) == 2,"profiles without an RT quality key default to High")
	check(QUALITY in GameData.OPTIONS_APPLIED,"RT quality is registered as an applied setting")
	var panel := OptionsPanel.new(); add_child(panel); panel.open()
	panel._show_group(OptionsPanel.WATER_GROUP)
	check(panel._rows[QUALITY_ROW].name == QUALITY and panel._rows[QUALITY_ROW].disabled,"quality sits below reflections and is disabled for Mirror")
	panel._sel = QUALITY_ROW
	click_quality(panel); key(panel,KEY_LEFT)
	check(panel._values[QUALITY] == 2,"mouse and keyboard cannot change disabled quality")
	panel._sel = 1; key(panel,KEY_DOWN)
	check(panel._sel == 3,"keyboard skips the disabled quality row")
	panel._set_value("gfx_water_reflections",3)
	check(not panel._rows[QUALITY_ROW].disabled,"selecting RT enables quality before applying")
	panel._sel = QUALITY_ROW; key(panel,KEY_LEFT)
	check(panel._values[QUALITY] == 1 and GameData.option(QUALITY) == 2,"keyboard selects Medium without prematurely applying it")
	click_quality(panel)
	check(panel._values[QUALITY] == 2,"mouse cycles Medium to High")
	panel._set_value("gfx_water",0)
	check(panel._rows[QUALITY_ROW].disabled,"disabling water also disables RT quality")
	panel._set_value("gfx_water",1)
	panel._set_value(QUALITY,0)
	panel._restore(); panel._close(); panel.open()
	check(panel._values[QUALITY] == 2,"discarding pending quality restores the saved choice")
	panel._show_group(OptionsPanel.WATER_GROUP)
	panel._set_value(QUALITY,1)
	for preset in [GfxPresets.ORIGINAL,GfxPresets.LOW,GfxPresets.HIGH,GfxPresets.ULTRA]:
		panel._set_value("graphics_preset",preset)
		check(panel._values[QUALITY] == 1 and panel._rows[QUALITY_ROW].disabled,"preset preserves RT quality and refreshes its dependency: "+str(preset))
	check(not GfxDetect.keys().has(QUALITY),"automatic graphics detection preserves independent RT quality")
	# Drop preset changes; the real quality choices below use the original scene.
	panel._close(); panel.open(); panel._show_group(OptionsPanel.WATER_GROUP)
	panel._set_value("gfx_water_reflections",3)
	panel._set_value(QUALITY,2); panel._accept()
	panel.queue_free(); await frames(4)

func read_target(expected: Vector2i, label: String, material_rid: RID) -> void:
	await frames(8); await RenderingServer.frame_post_draw
	var reflection := t._reflection
	var image := reflection._rt.output.get_image()
	check(reflection.rt_stats.get("active",false),label+": hardware RT remains active")
	check(image != null and image.get_size() == expected,label+": actual GPU texture matches the chosen resolution")
	check(reflection.rt_stats.get("samples_per_pixel",0) == 4,label+": four samples retained")
	check(reflection._rt.output.get_rid() == material_rid and t._water_mat.get_shader_parameter("planar_texture") == reflection._rt.output,label+": water material keeps its bound texture through resize")
	var hits := 0
	if image:
		for y in range(0,image.get_height(),32):
			for x in range(0,image.get_width(),32):
				if image.get_pixel(x,y).a > 0.01: hits += 1
	check(hits > 10,label+": resized reflection contains real geometry")
	samples.append({"case":label,"size":reflection.rt_stats.get("size"),"quality":reflection.rt_stats.get("quality"),"samples_per_pixel":reflection.rt_stats.get("samples_per_pixel"),"geometry_samples":hits})

func rendered_layout() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,false)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(800,600)]:
		await settle_window(size)
		for language: String in ["en","ru","de"]:
			RemakeText.lang = language
			var panel := OptionsPanel.new(); add_child(panel); panel.open()
			panel._show_group(OptionsPanel.WATER_GROUP)
			panel._sel = QUALITY_ROW
			var row: Dictionary = panel._rows[QUALITY_ROW]
			check(panel.text_width(row.label) <= 260.0,"quality label fits: "+language+str(size))
			for choice: String in row.choices:
				check(panel.text_width(choice) <= 160.0,"quality choice fits: "+language+" "+choice+str(size))
			for quality in 3:
				panel._set_value(QUALITY,quality)
				check(panel._switch_text(row) == GameData.option_choices(QUALITY)[quality],"dynamic quality choice resolves in "+language)
				await frames(2)
				await shot("options-%s-%dx%d-%d"%[language,size.x,size.y,quality])
			get_window().grab_focus()
			GameData._tips.delay = 0.1
			Input.warp_mouse(Vector2(20,20)); await frames(3)
			var at := panel.p8(Vector2(400,panel._row_y(QUALITY_ROW)+12))
			Input.warp_mouse(at)
			var motion := InputEventMouseMotion.new(); motion.position = at; Input.parse_input_event(motion)
			await get_tree().create_timer(0.4,true,false,true).timeout
			check(GameData._tips._panel.visible and GameData._tips._text.contains(RemakeText.t(GameData.REMAKE_OPTIONS[QUALITY][1])),"translated quality help is visible: "+language+str(size))
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"quality help fits: "+language+str(size))
			await shot("help-%s-%dx%d"%[language,size.x,size.y])
			panel._close(); panel.queue_free(); GameData._tips._hide(); await frames(3)
	RemakeText.lang = "en"
	get_window().size = Vector2i(1280,720)

func run() -> void:
	var context := await setup()
	await menu_checks()
	await settle_window(Vector2i(1280,720))
	for i in 1200:
		if t._reflection._rt_ready or t._reflection._rt_failed: break
		await frames(1)
	check(t._reflection._rt_ready,"RT is ready after applying its settings")
	if t._reflection._rt_ready:
		await frames(8)
		var device := t._reflection._rt
		var material_rid := device.output.get_rid()
		var panel := OptionsPanel.new(); add_child(panel)
		for quality in [0,1,2,0,2]:
			panel.open(); panel._show_group(OptionsPanel.WATER_GROUP)
			panel._set_value(QUALITY,quality); panel._accept()
			await settle_window(Vector2i(1280,720))
			await read_target([Vector2i(640,360),Vector2i(960,540),Vector2i(1280,720)][quality],"applied-tier-"+str(quality),material_rid)
			check(t._reflection._rt == device,"quality change reuses the scene and acceleration structures")
			var saved := ConfigFile.new()
			check(saved.load(GameData.CONFIG_PATH) == OK and saved.get_value("options",QUALITY,-1) == quality,"quality is written to the isolated player profile")
			await shot("river-quality-"+str(quality))
		panel.open()
		check(panel._values[QUALITY] == 2,"saved High is restored on reopening options")
		panel._close(); panel.queue_free()
		# Offscreen source view exercises full 4K allocation on smaller monitors.
		# Dispatch through the production controller, with the real river scene.
		t._reflection.set_process(false)
		var source_view := SubViewport.new(); source_view.size = Vector2i(3840,2160)
		source_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		source_view.world_3d = t.get_world_3d(); add_child(source_view)
		var source := Camera3D.new(); source_view.add_child(source)
		source.global_transform = camera.global_transform
		for quality in [0,1,2]:
			GameData.options[QUALITY] = quality
			t._reflection._update_raytrace(source)
			await read_target([Vector2i(1920,1080),Vector2i(2880,1620),Vector2i(3840,2160)][quality],"4K-tier-"+str(quality),material_rid)
		source_view.queue_free(); t._reflection.set_process(true)
		await frames(8)
		await read_target(Vector2i(1280,720),"return-to-window",material_rid)
		if not OS.get_cmdline_user_args().has("--skip-layout"): await rendered_layout()
	FileAccess.open(out.path_join("rt-quality-options.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_driver_name(),"samples":samples},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	print("RT_QUALITY_OPTIONS ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
