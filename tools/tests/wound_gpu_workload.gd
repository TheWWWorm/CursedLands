extends Node
## Bounded allocation/work-submission control, runnable against old/new packs.
## Eight distinct 256px outfit texture identities use the same authored human
## wound state. Their pixels are prepared before timing; this is not FPS QA.
var checks := 0
var failures := 0
var rows := []
var production := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func frames(count := 4) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func group_from(image: Image) -> Array:
	var group := []
	for i in 8:
		var texture := ImageTexture.create_from_image(image)
		var retained := image.duplicate() as Image
		retained.clear_mipmaps()
		texture.set_meta(UnitWounds.SOURCE_IMAGE,retained)
		var material = EIUnitModel.LitMaterial.new() if i % 2 == 0 else EIUnitModel.PreviewMaterial.new()
		material.albedo_texture = texture
		var model := EIUnitModel.new()
		model.template = "unhuma"
		var mesh := MeshInstance3D.new()
		mesh.material_override = material
		model.add_child(mesh)
		add_child(model)
		group.append([model,material,texture])
	return group

func batch(group: Array, label: String) -> void:
	await frames()
	var memory_before := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	var start := Time.get_ticks_usec()
	for row: Array in group: UnitWounds.apply(row[0],PackedByteArray([3,1,2,0,1,3]),true)
	var submission_us := Time.get_ticks_usec()-start
	var jobs := UnitWounds._jobs.values().duplicate()
	var wait_frames := 0
	while not UnitWounds._jobs.is_empty() and wait_frames < 100:
		await get_tree().process_frame
		wait_frames += 1
	var completed_us := Time.get_ticks_usec()-start
	check(UnitWounds._jobs.is_empty(),label+": workers publish through normal frame polling")
	await frames()
	var uploaded_bytes := 0
	var upload_count := 0
	var native_compositions := 0
	for job: Dictionary in jobs:
		if job.get("compose_layer",false): native_compositions += 1
		if job.out != null:
			upload_count += 1
			uploaded_bytes += job.out.get_data_size()
	var textures := {}
	var unchanged := 0
	for row: Array in group:
		if row[1].albedo_texture == row[2]: unchanged += 1
		var texture: Texture2D = row[1].get("wound_texture") if production else row[1].albedo_texture
		if texture: textures[texture.get_instance_id()] = true
	check(unchanged == (8 if production else 0),label+": expected base identity contract")
	check(textures.size() == (1 if production else 8),label+": expected texture sharing")
	var cold := label.ends_with("cold")
	check(upload_count == (int(cold) if production else 8),label+": measured upload count")
	check(uploaded_bytes == ((87380 if cold else 0) if production else 2796192),label+": measured RGBA8 mip bytes")
	check(native_compositions == int(cold),label+": wound composition independent of outfit count")
	if production: check(UnitWounds._composites.is_empty() and UnitWounds._bases.is_empty(),label+": no replacement cache")
	rows.append({"label":label,"submission_us":submission_us,"publication_us":completed_us,"publication_frames":wait_frames,
		"jobs":jobs.size(),"native_compositions":native_compositions,"uploads":upload_count,"uploaded_mip_bytes":uploaded_bytes,
		"unique_result_textures":textures.size(),"unchanged_base_textures":unchanged,
		"texture_memory_delta":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)-memory_before})

func _ready() -> void:
	production = OS.get_cmdline_user_args().has("--production")
	check(DisplayServer.get_name() != "headless","allocation control has a real renderer")
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["confine_mouse"] = 0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	Gfx.ensure_globals()
	var source: Image = EIUnitModel._compose("unhuma",["skin_14"]).get_meta(UnitWounds.SOURCE_IMAGE)
	source = source.duplicate()
	source.resize(256,256,Image.INTERPOLATE_BILINEAR)
	source.generate_mipmaps()
	for iteration in 3:
		UnitWounds.shutdown()
		var cold := group_from(source)
		var warm := group_from(source)
		await frames(16)
		await batch(cold,"%d-cold" % iteration)
		await batch(warm,"%d-warm" % iteration)
		for row: Array in cold+warm: row[0].free()
		UnitWounds.shutdown()
		await frames()
	var report := {"checks":checks,"failures":failures,"production":production,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows,
		"scope":"Eight controlled 256px outfit identities per batch, authored unhuma wound bytes; normal asynchronous frame publication. Allocation/work-submission evidence, not device or FPS performance."}
	FileAccess.open("user://wound-gpu-workload.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WOUND_GPU_WORKLOAD ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
