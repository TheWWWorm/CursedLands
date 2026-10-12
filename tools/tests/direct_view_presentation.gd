extends "third_person_kbm.gd"
## Rendered native figure shadows and actual HUD layout. The shadow receiver
## is a controlled plane; the HUD uses the loaded Ingos field and HD pack.
var measurements := []

func capture(label: String, viewport: Viewport = null) -> Image:
	if viewport == null: viewport = get_viewport()
	await frames(4)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png("user://" + label + ".png")
	return image

func shadow_pixels() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480);viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.3,.3,.3)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .35
	viewport.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new();floor_mesh.mesh.size = Vector2(10,10)
	floor_mesh.material_override = StandardMaterial3D.new()
	floor_mesh.material_override.albedo_color = Color(.8,.8,.8)
	viewport.add_child(floor_mesh)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true;light.shadow_bias = .01;light.shadow_normal_bias = .1
	light.directional_shadow_max_distance = 20.0
	viewport.add_child(light);light.look_at(Vector3(.6,-1,.4))
	var camera := Camera3D.new()
	viewport.add_child(camera);camera.fov=50;camera.position = Vector3(1.6,2.5,2.5);camera.look_at(Vector3(0,.3,0))
	for smooth: bool in [false,true]:
		var model := EIUnitModel.create({"prototype":"Human Hero","smooth_joints":smooth})
		viewport.add_child(model)
		model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		model.act("idle",1,0);model.player.seek(.2,true);model.flush_pending_pose()
		model.set_first_person_view(true)
		model.align_first_person_body(model.eye_position(),Vector3.RIGHT)
		var complete := await capture("shadow-complete-"+str(smooth),viewport)
		var head_rows := []
		for row: Dictionary in model._view_shadows:
			if model._head.is_ancestor_of(row.source):
				head_rows.append([row,row.cast]);row.cast = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var headless := await capture("shadow-headless-control-"+str(smooth),viewport)
		var changed := 0
		for y in complete.get_height():
			for x in complete.get_width():
				if headless.get_pixel(x,y).get_luminance() - complete.get_pixel(x,y).get_luminance() > .05: changed += 1
		check(changed > 50,"hidden head adds visible shadow pixels, smooth="+str(smooth))
		measurements.append({"smooth":smooth,"head_shadow_pixels":changed})
		for row: Array in head_rows: row[0].cast = row[1]
		model.free()
	viewport.queue_free();await frames(2)

func hud_layout() -> void:
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz11k",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false)
	g.rig.follow(hero);g.rig._follow(g,0)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=resolution
		await frames(6)
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			for guide: int in [1,2]:
				GameData.options.direct_hints=guide;g.direct.tilt=-.3;g.direct.apply_camera()
				g.direct._overlay.queue_redraw();await frames(2)
				var marker := g.hud._faces.marker_screen_rect()
				var baseline := g.direct._overlay.get_global_transform_with_canvas() * Vector2(0,g.direct.hint_baseline())
				check(marker.has_area() and baseline.y + 3.0*resolution.y/720.0 < marker.position.y,
					"guide clears visible follow icon: %s %s guide%d" % [resolution,language,guide])
				if language=="ru" and resolution.x==1280: await capture("ingos-hud-guide"+str(guide))
	check(g.hud.minimap._mark_col[0].g > .9 and g.hud.minimap._mark_col[2].r > .9,"loaded minimap retains green and red markers")
	g.queue_free();s.queue_free();await frames(5)

func _ready() -> void:
	mode="direct-view presentation"
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":3,"cam_follow":1,"pad_enabled":0,"confine_mouse":0,"display_mode":0},true)
	if OS.get_cmdline_user_args().has("--hd"):
		check(ModStore.create_profile("Presentation HD",false,["community.hd-lands-textures@1.4.0"]).is_empty(),"enable installed HD pack")
		check(GameData.open(GameData.root).is_empty(),"mount HD pack")
	GameData.resolution_size="1280x720";GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720))
	RenderingServer.set_render_loop_enabled(true)
	await shadow_pixels()
	await hud_layout()
	print("DIRECT_VIEW_PRESENTATION ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
