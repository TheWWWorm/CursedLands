extends "res://tools/tests/path_trace_camera_routes.gd"
## Original Gipat hills and trees with wind, surface detail and ground contact.
## Match 4K Performance upscaling's raster size and PT low's 960x540 grid.
func run() -> void:
	map_name="zone1";resolution=Vector2i(3840,2160)
	var dlss:=OS.get_cmdline_user_args().has("--pt-dlss")
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1]
	GameData.options.merge({"gfx_wind":1,"gfx_ground_contact":1},true)
	game._apply_options()
	var rt: Node=game.get_node("SceneRaytrace")
	get_viewport().scaling_3d_scale=0.5
	if dlss:
		GameData.options.rtx_upscaling=4
		RtxGraphics.apply_upscaling(get_viewport())
		check(RtxGraphics.sr_active(),"DLSS Performance is available")
	var start:=camera.global_position
	camera.global_position=Vector3(start.x,t.height_at(start.x,-start.z)+1.7,start.z)
	camera.rotation_degrees=Vector3(-8,180,0)
	check(await ready_scene(rt),"windy eye-height campaign scene is ready")
	check(rt.stats.get("size",[])==[960,540],"PT grid matches recorded low/Performance combination")
	var contact_wind:=0
	for mesh: MeshInstance3D in game.world.find_children("*","MeshInstance3D",true,false):
		var material:=mesh.get_active_material(0) as ShaderMaterial
		if material!=null and material.shader.code.contains("#define EI_FOLIAGE_WIND") \
			and material.shader.code.contains("#define EI_GROUND_CONTACT"):contact_wind+=1
	check(contact_wind>0,"actual trees use combined wind and ground-contact shader")
	var original:=camera.global_transform
	var inactive:=0;var nrd_inactive:=0
	var dlss_before:=int(RtxGraphics.bridge().call("get_status").get("dlss_evaluations",0)) if dlss else 0
	for i in 120:
		camera.global_transform=original
		camera.rotate_y(sin(i*0.04)*0.15)
		Gfx.set_wind_frame({"state":Vector4(0.6,0.8,1,1),"phases":Vector4(i*0.03,i*0.05,i*0.07,i*0.09)})
		await frames(1)
		if not rt.stats.get("active",false):inactive+=1
		if rt.device==null or not rt.device.nrd_active:nrd_inactive+=1
		if i in [0,30,60,90,119]:await save_buffers(rt,"wind-%03d"%i)
	await receiver_coverage()
	check(inactive==0 and nrd_inactive==0,"PT and NRD stay active during wind and camera motion")
	check(float(receiver_counts.fraction)>0.99,"nearby terrain retains traced lighting during motion")
	var dlss_status: Dictionary=RtxGraphics.bridge().call("get_status") if dlss else {}
	if dlss:
		check(int(dlss_status.get("dlss_evaluations",0))-dlss_before>=120,"SDK evaluates DLSS throughout wind and camera motion")
		check(int(dlss_status.get("last_error",-1))==0 and RtxGraphics.sr_active(),"DLSS remains active without SDK errors")
	FileAccess.open(out.path_join("wind-live.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"stats":rt.stats,"terrain":receiver_counts,"dlss":dlss_status,
		"inactive_frames":inactive,"nrd_inactive_frames":nrd_inactive,"contact_wind_materials":contact_wind},"\t"))
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_WIND_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
