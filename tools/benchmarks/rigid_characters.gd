extends Node
## Independent original/rigid render worlds using the same real figure and
## animation data. This is a prototype, not an enabled character renderer.
const Batch = preload("rigid_part_batch.gd")
const MeshScreenRect = preload("res://src/ui/mesh_screen_rect.gd")
var checks := 0
var failures := 0
var rows := []
var timing_rows := []
var local_lights := 0
var control := false
var skipped_actions := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 6) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func fixture(record: Dictionary) -> Dictionary:
	var view := SubViewport.new(); view.size = Vector2i(512,512); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08,0.11,0.14)
	environment.environment.ambient_light_color = Color.WHITE
	view.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	for i in local_lights:
		var lamp := OmniLight3D.new()
		lamp.omni_range = 1.35; lamp.light_energy = 2.0; lamp.light_specular = Gfx.LOCAL_SPECULAR
		lamp.light_color = Color.from_hsv(float(i)/maxi(1,local_lights),0.8,1.0)
		lamp.position = Vector3(cos(i*TAU/maxi(1,local_lights))*0.8,0.15+(i%4)*0.55,sin(i*TAU/maxi(1,local_lights))*0.8)
		view.add_child(lamp)
	var model := EIUnitModel.create(record,false,false)
	check(model != null,"real character exists")
	view.add_child(model); model.set_process(false)
	model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8; view.add_child(camera)
	camera.position = Vector3(0,1.0,5.0); camera.look_at(Vector3(0,0.9,0)); camera.current = true
	return {"view":view,"model":model,"camera":camera,"sun":sun}

func fit_views(original: Dictionary, candidate: Dictionary, state: int) -> void:
	var bounds := AABB(); var first := true
	for mi: MeshInstance3D in original.model.find_children("*","MeshInstance3D",true,false):
		if not mi.is_visible_in_tree(): continue
		var box: AABB = mi.global_transform*mi.get_aabb()
		bounds = box if first else bounds.merge(box); first = false
	var extent := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
	var centre := bounds.get_center()
	for f: Dictionary in [original,candidate]:
		var camera: Camera3D = f.camera
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL if state == 0 else Camera3D.PROJECTION_PERSPECTIVE
		camera.size = maxf(0.2,extent*1.35)
		camera.position = centre+Vector3(0,0.0 if state == 0 else extent*0.7,extent*2.8+1.0)
		camera.look_at(centre)

func pose(model: EIUnitModel, clip: String, phase: float) -> void:
	var animation: Animation = model.player.get_animation("ei/"+clip)
	EIAnimPart.batch = true
	model.player.play("ei/"+clip,0.0)
	model.player.seek(animation.length*phase,true)
	EIAnimPart.batch = false
	for root: EIAnimPart in model._animation_roots: root._apply_key()

func difference(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var changed := 0; var over := 0; var sum := 0
	for i in range(0,aa.size(),4):
		var delta := 0
		for c in 3:
			var d := absi(aa[i+c]-bb[i+c]); delta = maxi(delta,d); sum += d
		peak = maxi(peak,delta); changed += int(delta>0); over += int(delta>2)
	return {"changed_pixels":changed,"pixels_over_2":over,"peak_delta":peak,"mean_rgb_delta":float(sum)/(a.get_width()*a.get_height()*3)}

func picking_rects(f: Dictionary) -> Array:
	# Use the exact production query. Merging meshes also merges the part
	# rectangles that Game._pick_unit prioritizes over a loose union hit.
	var out := []
	var context := MeshScreenRect.camera_context(f.camera)
	for mi: MeshInstance3D in f.model.find_children("*","MeshInstance3D",true,false):
		if not mi.is_visible_in_tree(): continue
		var rect := MeshScreenRect.of_context(mi,f.camera,context)
		if rect.size.x > 0 and rect.size.y > 0:
			out.append({"path":str(f.model.get_path_to(mi)),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	return out

func specimen(label: String, record: Dictionary, expect_merge := true) -> void:
	var original := fixture(record); var candidate := fixture(record)
	var batch := Batch.new()
	if not control: batch.build(candidate.model)
	if not control: check((batch.merged_meshes > 1) == expect_merge,label+" expected merge/keep policy")
	print("RIGID_BUILD ",JSON.stringify({"label":label,"before_meshes":batch.before_meshes,"merged_meshes":batch.merged_meshes,"surfaces":batch.surfaces}))
	for action: String in ["idle","walk","attack","death"]:
		# Resolve once: the native idle/death picker may randomly choose among
		# authored variants. Both worlds must use the same actual clip.
		var clip: String = original.model.resolve(action,1)
		if clip.is_empty():
			skipped_actions.append({"label":label,"action":action,"available":Array(original.model.anim_names())})
			continue # some flying figures have no authored walk clip
		for state in 2:
			for f: Dictionary in [original,candidate]:
				pose(f.model,clip,0.17+state*0.39)
				f.model.rotation.y = state*0.71
				f.model.set_detailed_head(state == 1)
				var proto := GameData.db.find("monster_prototypes",record.get("prototype",""))
				var race := GameData.db.find("race_models",proto.get("base_race",""))
				UnitWounds.apply(f.model,PackedByteArray([1,2,1,2,1,2]) if state == 1 else PackedByteArray([0,0,0,0,0,0]),int(race.get("type_id",0)) == 0x32)
			UnitWounds.flush()
			batch.sync()
			fit_views(original,candidate,state)
			await frames(10)
			var geometry: Dictionary = batch.geometry_error(original.model)
			check(geometry.position_error <= 0.00002,label+" "+action+" rigid vertex equivalence")
			check(geometry.normal_error <= 0.00002,label+" "+action+" rigid normal equivalence")
			var first: Image = original.view.get_texture().get_image(); var second: Image = candidate.view.get_texture().get_image()
			var delta := difference(first,second)
			var stem := "rigid-"+label+"-"+action+"-"+str(state)
			first.save_png("user://"+stem+"-original.png"); second.save_png("user://"+stem+"-candidate.png")
			var draw_before: int = original.view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var draw_after: int = candidate.view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			rows.append({"label":label,"action":action,"clip":clip,"state":state,"difference":delta,"geometry":geometry,
				"draws_original":draw_before,"draws_candidate":draw_after,"merged_meshes":batch.merged_meshes,"surfaces":batch.surfaces,
				"picking_original":picking_rects(original),"picking_candidate":picking_rects(candidate),
				"detailed_head":candidate.model.detailed_head_shown(),"local_lights":local_lights})
			print("RIGID_VIEW ",JSON.stringify(rows.back()))
	original.view.free(); candidate.view.free(); batch = null
	await frames(8)

func distribution(values: Array) -> Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*0.95)],"samples":values.size()}

func crowd_timing(count: int) -> void:
	# The delayed startup window update reads the saved options too.
	# Setting only Engine.max_fps lets that update restore the user's cap.
	GameData.options["fps_limit"] = 0; GameData.options["vsync"] = 0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for merged: bool in [false,true,true,false]:
		var start := Time.get_ticks_usec()
		var f := fixture({"prototype":"Human Hero"})
		var models: Array[EIUnitModel] = [f.model]
		var batches := []
		for i in range(1,count):
			var model := EIUnitModel.create({"prototype":"Human Hero"},false,false)
			f.view.add_child(model); model.set_process(false)
			model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			models.append(model)
		for i in models.size():
			models[i].position = Vector3((i%8-3.5)*1.6,0,(i/8)*1.8)
			pose(models[i],"cwalk01",fposmod(i*0.037,1.0))
			if merged:
				var batch := Batch.new(); batch.build(models[i]); batches.append(batch)
		f.camera.position = Vector3(0,13,20); f.camera.look_at(Vector3(0,0,3))
		f.camera.size = 17; f.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		var build_usec := Time.get_ticks_usec()-start
		var viewport: RID = f.view.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(viewport,true)
		var wall := []; var advance := []; var palette := []; var cpu := []; var gpu := []; var draws := []
		await frames(32)
		var previous := Time.get_ticks_usec()
		for frame in 224:
			start = Time.get_ticks_usec()
			EIAnimPart.batch = true
			for model: EIUnitModel in models: model.player.advance(1.0/60.0)
			EIAnimPart.batch = false
			for model: EIUnitModel in models:
				for root: EIAnimPart in model._animation_roots: root._apply_key()
			var advanced := Time.get_ticks_usec()
			for batch in batches: batch.sync()
			var synced := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if frame >= 64:
				wall.append((now-previous)/1000.0); advance.append((advanced-start)/1000.0); palette.append((synced-advanced)/1000.0)
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
				draws.append(f.view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
			previous = now
		var result := {"merged":merged,"count":count,"build_usec":build_usec,"frame_ms":distribution(wall),
			"animation_ms":distribution(advance),"palette_ms":distribution(palette),"viewport_cpu_ms":distribution(cpu),
			"viewport_gpu_ms":distribution(gpu),"draws":distribution(draws),
			"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}
		check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,"timing stays uncapped")
		timing_rows.append(result); print("RIGID_TIMING ",JSON.stringify(result))
		f.view.free(); models.clear(); batches.clear(); await frames(16)

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--rigid-catalog"):
		for race: Dictionary in GameData.db.tables.get("race_models",[]):
			var examples := []
			for proto: Dictionary in GameData.db.tables.get("monster_prototypes",[]):
				if proto.get("base_race") == race.name and examples.size() < 4: examples.append(proto.name)
			print("RIGID_RACE ",JSON.stringify({"name":race.name,"mask":race.get("mask"),"examples":examples}))
		get_tree().quit(); return
	seed(417)
	var timing_count := 0
	var suite := OS.get_cmdline_user_args().has("--rigid-suite")
	control = OS.get_cmdline_user_args().has("--rigid-control")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rigid-lights="): local_lights = int(arg.get_slice("=",1))
		if arg.begins_with("--rigid-timing="): timing_count = int(arg.get_slice("=",1))
	GameData.options.merge({"gfx_detailed_heads":0,"gfx_volumetric":0,"gfx_ssao":0,"gfx_bloom":0,"gfx_materials":0,
		"gfx_far_view":0,"confine_mouse":0},true)
	Gfx.ensure_globals(); Gfx.set_light(Color(0.55,0.55,0.55),Color.WHITE)
	RenderingServer.set_render_loop_enabled(true); Engine.max_fps = 120
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if timing_count > 0:
		await crowd_timing(timing_count)
	else:
		await specimen("human",{"prototype":"Human Hero"})
		if suite:
			await specimen("human-complexion",{"prototype":"Human Hero Hadagan","complexion":Vector3(0.2,0.85,0.95)})
			await specimen("human-female",{"prototype":"Human Mercenary Thief"})
			await specimen("orc-bow",{"prototype":"OrcFemaleBowA3"})
			await specimen("troll",{"prototype":"TrollBlueF12"})
			await specimen("wolf",{"prototype":"WolfGreyF2"})
			await specimen("dragon",{"prototype":"DragonBlueM14"})
			await specimen("wisp",{"prototype":"WillowispM1"},false)
	UnitWounds.shutdown(); TexUpscale.shutdown(); await frames(16)
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),
		"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),
		"control":control,"rows":rows,"timing":timing_rows,"skipped_actions":skipped_actions}
	FileAccess.open("user://rigid-characters.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("RIGID_CHARACTERS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
