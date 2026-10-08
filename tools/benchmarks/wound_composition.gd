extends Node
## Run the same workload with frozen old/new packs; compare every output hash.
## Timings are diagnostics. Native composition counts describe removed work;
## this does not measure gameplay FPS or reduced GPU uploads.
var checks := 0
var failures := 0
var rows := []
var waves := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func digest(data: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(data)
	return h.finish().hex_encode()

func source_copy(base: Texture2D, size: int) -> Texture2D:
	var source := (base.get_meta(UnitWounds.SOURCE_IMAGE) as Image).duplicate() as Image
	if source.get_width() != size: source.resize(size,size,Image.INTERPOLATE_BILINEAR)
	var pixels := source.duplicate() as Image; pixels.generate_mipmaps()
	var texture := ImageTexture.create_from_image(pixels)
	texture.set_meta(UnitWounds.SOURCE_IMAGE,source)
	return texture

func wave(label: String, mask: String, human: bool, lv: PackedByteArray, specimens: Array) -> void:
	var jobs := []; var originals := []; var composed := 0; var submitted_us := 0
	var start := Time.get_ticks_usec()
	for row: Array in specimens:
		var base: Texture2D = row[1]
		originals.append(digest((base.get_meta(UnitWounds.SOURCE_IMAGE) as Image).get_data()))
		var before := Time.get_ticks_usec()
		var pending := UnitWounds._wounded(base,mask,lv,human)
		submitted_us += Time.get_ticks_usec()-before
		check(pending == null,label + " queues fresh outfit")
		var found := {}
		for job: Dictionary in UnitWounds._jobs.values():
			if job.base == base: found = job; break
		check(not found.is_empty(),label + " owns composite job")
		if found.is_empty(): return
		composed += int(not (found.get("layers",[]) as Array).is_empty())
		jobs.append(found)
	# Exercise ordinary polling rather than only the blocking test flush.
	UnitWounds._start_poll()
	var frames := 0
	while not UnitWounds._jobs.is_empty() and frames < 120:
		await get_tree().process_frame
		frames += 1
	check(UnitWounds._jobs.is_empty(),label + " completes within bounded frames")
	var elapsed := Time.get_ticks_usec()-start
	var layer_ids := {}; var output_bytes := 0
	for i in jobs.size():
		var out: Image = jobs[i].out
		check(out != null,label + " creates wounded output")
		if out == null: continue
		var base: Texture2D = specimens[i][1]
		check(digest((base.get_meta(UnitWounds.SOURCE_IMAGE) as Image).get_data()) == originals[i],label + " leaves source immutable")
		if jobs[i].get("wound") != null: layer_ids[jobs[i].wound.get_instance_id()] = true
		output_bytes += out.get_data_size()
		rows.append({"wave":label,"specimen":specimens[i][0],"mask":mask,"human":human,
			"levels":lv.hex_encode(),"size":str(out.get_size()),"mips":out.has_mipmaps(),
			"bytes":out.get_data_size(),"sha256":digest(out.get_data())})
	waves.append({"label":label,"requests":jobs.size(),"native_layer_compositions":composed,
			"shared_layer_images":layer_ids.size(),"output_upload_bytes":output_bytes,
			"main_submission_us":submitted_us,"completion_us":elapsed,"completion_frames":frames})

func human_specimens(bases: Array) -> Array:
	var specimens := []
	for row: Array in bases:
		for size: int in [64,128,256,512]:
			specimens.append(["%s-%d" % [row[0],size],source_copy(row[1],size)])
	return specimens

func capture(view: SubViewport, label: String) -> void:
	for i in 24:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	var image := view.get_texture().get_image()
	check(image.save_png("user://wound-presentation-"+label+".png") == OK,"captured " + label)

func render_presentations() -> void:
	Gfx.ensure_globals()
	Gfx.set_light(Color(0.55,0.55,0.55),Color.WHITE)
	RenderingServer.set_render_loop_enabled(true)
	var view := SubViewport.new(); view.size = Vector2i(768,512); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment)
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.09,0.11,0.13)
	environment.environment.background_energy_multiplier = 1.0
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	view.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-40,-35,0); view.add_child(light)
	var camera := Camera3D.new(); camera.position = Vector3(0,1.2,6); view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 2.2
	camera.look_at(Vector3(0,0.7,0)); camera.current = true
	var models := []
	for preview in [false,true]:
		var model := EIUnitModel.create({"template":"unhuma"},preview,false)
		check(model != null,"real world/preview figure created")
		if model == null: continue
		view.add_child(model); model.position.x = 0.65 if preview else -0.65
		model.act("idle",1,0.0)
		if model.player:
			model.player.seek(0.0,true); model.player.pause()
		model.process_mode = Node.PROCESS_MODE_DISABLED
		if preview:
			for m in UnitWounds._materials(model): m.albedo_texture = EIUnitModel._compose("unhuma",["skin_14"])
		models.append(model)
	var marks := OrderMarks.new()
	for sharp in [false,true]:
		RenderingServer.global_shader_parameter_set(&"ei_unit_sharp",Vector3(1,EIUnitModel.SHARP_MIP_BIAS,0) if sharp else Vector3.ZERO)
		var prefix := "sharp%d-" % int(sharp)
		await capture(view,prefix+"healthy")
		for model: EIUnitModel in models: UnitWounds.apply(model,PackedByteArray([3,1,2,0,1,3]),true)
		UnitWounds.flush()
		await capture(view,prefix+"wounded")
		if not models.is_empty(): marks._lighten(models[0],true)
		await capture(view,prefix+"selected")
		for model: EIUnitModel in models: UnitWounds.apply(model,PackedByteArray([3,3,3,3,3,3]),true)
		UnitWounds.flush()
		await capture(view,prefix+"worse-selected")
		if not models.is_empty(): marks._lighten(models[0],false)
		for model: EIUnitModel in models: UnitWounds.apply(model,PackedByteArray([0,0,0,0,0,0]),true)
		await capture(view,prefix+"healed")
		# Reusing a detached selection copy must resync its albedo after healing.
		if not models.is_empty(): marks._lighten(models[0],true)
		await capture(view,prefix+"selected-healed")
		if not models.is_empty(): marks._lighten(models[0],false)
	marks.free(); view.free(); UnitWounds.shutdown()

func _ready() -> void:
	GameData.options["gfx_hd_textures"] = 0
	Engine.max_fps = 120
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	UnitWounds.shutdown()
	var bases := []
	for skin: String in ["skin_00","skin_14"]:
		var base := EIUnitModel._compose("unhuma",[skin])
		check(base != null,"real human outfit " + skin)
		if base: bases.append([skin,base])
	var lv := PackedByteArray([3,1,2,0,1,3])
	await wave("human-cold","unhuma",true,lv,human_specimens(bases))
	await wave("human-warm-new-outfits","unhuma",true,lv,human_specimens(bases))
	UnitWounds._composites.clear(); UnitWounds._bases.clear()
	await wave("human-after-albedo-eviction","unhuma",true,lv,human_specimens(bases))
	await wave("human-worse","unhuma",true,PackedByteArray([3,3,3,3,3,3]),human_specimens(bases))
	# Locate a real creature wound set without hard-coding database row order.
	var names: Array = Array(GameData.textures.names_with_suffix("hdw1.mmp")); names.sort()
	var creature := ""
	for file: String in names:
		var mask := file.trim_suffix("hdw1.mmp")
		if not UnitWounds._layer_bytes(mask + "hw2").is_empty() and not UnitWounds._layer_bytes(mask + "lw1").is_empty():
			creature = mask; break
	check(not creature.is_empty(),"real creature wound set found")
	if not creature.is_empty() and not bases.is_empty():
		await wave("creature-paired-cold",creature,false,PackedByteArray([1,0,2,2,1,1]),human_specimens(bases))
		await wave("creature-paired-warm",creature,false,PackedByteArray([1,0,2,2,1,1]),human_specimens(bases))
	UnitWounds.shutdown()
	if OS.get_cmdline_user_args().has("--wound-render") and DisplayServer.get_name() != "headless":
		await render_presentations()
	var report := {"checks":checks,"failures":failures,"threads":Portability.threads(),"waves":waves,"images":rows,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"limitation":"Synthetic outfit variants and real wound assets; not a combat/FPS/upload-reduction claim."}
	FileAccess.open("user://wound-composition.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WOUND_COMPOSITION ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
