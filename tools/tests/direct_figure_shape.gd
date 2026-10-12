extends "third_person_kbm.gd"
## The native torso is rigid. Direct control, camera cycling and preview
## rebuilds must not introduce vertex weights or deform its authored shape.
var measurements := []

func frames(n := 4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g): g.rig._window_focused = true

func chest_error(model: EIUnitModel, vertices: PackedVector3Array) -> float:
	model.flush_pending_pose()
	var chest := model.get_node("hp/bd") as EIAnimPart
	var skeleton := model.get_node_or_null("Skeleton") as Skeleton3D
	if skeleton == null:
		for mesh: MeshInstance3D in chest.find_children("*","MeshInstance3D",false,false):
			if mesh.mesh and mesh.skin == null:
				var actual: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				if actual.size() != vertices.size(): return INF
				var error := 0.0
				for i in actual.size(): error = maxf(error,(mesh.transform * actual[i]).distance_to(vertices[i]))
				return error
		return INF
	var body := skeleton.get_node("Body") as MeshInstance3D
	var expected_bone := skeleton.find_bone("bd")
	var index := 0
	var worst := 0.0
	for surface in body.mesh.get_surface_count():
		var arrays := body.mesh.surface_get_arrays(surface)
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			if arrays[Mesh.ARRAY_BONES][i*4] != expected_bone: continue
			var posed := Vector3.ZERO
			for influence in 4:
				var bind: int = arrays[Mesh.ARRAY_BONES][i*4+influence]
				var bone := skeleton.find_bone(body.skin.get_bind_name(bind))
				posed += (skeleton.get_bone_global_pose(bone) * body.skin.get_bind_pose(bind) * arrays[Mesh.ARRAY_VERTEX][i]) * arrays[Mesh.ARRAY_WEIGHTS][i*4+influence]
			worst = maxf(worst, chest.to_local(skeleton.to_global(posed)).distance_to(vertices[index]))
			index += 1
	return worst if index == vertices.size() else INF

func shape(model: EIUnitModel, label: String) -> void:
	var record := hero.figure_info()
	record.smooth_joints = false
	var reference := EIUnitModel.create(record,false,false)
	var native_mesh: MeshInstance3D = reference.get_node("hp/bd").find_children("*","MeshInstance3D",false,false)[0]
	var vertices: PackedVector3Array = native_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	reference.free()
	var worst := 0.0
	model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for act: String in ["idle","walk","run","attack","cast"]:
		model.act(act,1,0)
		var clip := model.player.get_animation(model.player.current_animation)
		for i in 12:
			model.player.seek(clip.length*float(i)/12.0,true)
			model.flush_pending_pose()
			for part: Node3D in model.find_children("*","EIAnimPart",true,false): part.force_update_transform()
			await frames(1)
			worst = maxf(worst,chest_error(model,vertices))
	check(worst < .00001,label+" retains the rigid authored chest across 60 animation frames")
	measurements.append({"case":label,"max_chest_deformation":worst})

func _ready() -> void:
	mode="direct figure shape"
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":2,"pad_enabled":0,"confine_mouse":0,"display_mode":0,"blood":0},true)
	if OS.get_cmdline_user_args().has("--hd"):
		check(ModStore.create_profile("Figure shape HD",false,["community.hd-lands-textures@1.4.0"]).is_empty(),"enable installed HD pack")
		check(GameData.open(GameData.root).is_empty(),"mount HD pack")
	RenderingServer.set_render_loop_enabled(true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g",1,false);await prepare()
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,720)
	hero.set_process(false);hero.set_physics_process(false)
	hero.action="idle";hero.model.act("idle",1,0)
	s.apply_command({"t":"direct_control","leader":hero.uid},0)
	hero._present_frame(1.0/60)
	await frames(4)
	check(hero.direct_controlled,"direct-control authority is active")
	if hero._direct_pose: hero._direct_pose.set_process(false)
	await shape(hero.model,"world after entering direct control")
	var doll := Paperdoll.new()
	doll.size=Vector2(320,480);doll.position=Vector2(0,100)
	add_child(doll);doll.show_unit(hero);await frames(6);doll.set_process(false)
	await shape(doll._model,"new HUD/inventory preview after direct control")
	var armor:=PackedStringArray(hero.info.get("armors",[]))
	var weapons:=PackedStringArray(hero.info.get("weapons",[]))
	for equipped: bool in [false,true]:
		hero.set_equipment(armor,weapons if equipped else PackedStringArray())
		hero.refresh_figure(true)
		doll.show_unit(hero);await frames(6);doll.set_process(false)
		await shape(hero.model,"world after equipment rebuild "+str(equipped))
		await shape(doll._model,"preview after equipment rebuild "+str(equipped))
	for camera_mode: int in [3,2,1,3,1,2]:
		GameData.options.control_mode=camera_mode
		g.direct.apply_camera(1.0/60)
		await frames(4)
		check(hero.model._view_active == (camera_mode == 3),"camera mode applies the matching body presentation: "+str(camera_mode))
		if camera_mode != 3: await shape(hero.model,"world after camera mode "+str(camera_mode))
	doll.free()
	hero.action="idle";hero.model.act("idle",1,0)
	hero.model.player.seek(.25,true);hero.model.flush_pending_pose()
	g.rig.camera.global_position=hero.model.to_global(Vector3(.4,1.6,3.0))
	g.rig.camera.look_at(hero.model.to_global(Vector3(0,.95,0)))
	g.rig.camera.fov=50
	if DisplayServer.get_name() != "headless":
		await frames(6);await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://zak-rigid-chest.png")
	g.queue_free();s.queue_free();await frames(8)
	print("DIRECT_FIGURE_SHAPE ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
