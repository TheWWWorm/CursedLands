extends "res://tools/tests/water_raytrace_artifact.gd"
const PathWater = preload("res://src/game/fx/path_trace_water_device.gd")
var stages:=[]

func ready_mode(path: bool) -> bool:
	for i in 1200:
		await frames(1)
		var r: Node=t._reflection
		if r._rt_failed:return false
		if r._rt_ready and r._rt!=null and (r._rt is PathWater)==path and r._rt.output_ready() \
			and not r.rt_stats.get("rebuilding",true) and not ShaderCompilationScreen.active():return true
	return false

func record(label: String) -> void:
	await frames(20);await RenderingServer.frame_post_draw
	var r: Node=t._reflection
	var image: Image=r._rt.reflection_output().get_image()
	var hits:=0;var finite:=true
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			var c:=image.get_pixel(x,y)
			finite=finite and is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and c.a>=0 and c.a<=1
			if c.a>0.1:hits+=1
	check(finite and hits>100,label+": real campaign reflection contains finite scenery")
	image.duplicate().save_png(out.path_join(label+"-reflection.png"))
	await shot(label+"-world")
	stages.append({"label":label,"hits":hits,"stats":r.rt_stats.duplicate(true)})

func run() -> void:
	GameData.options.pt_mode=0;GameData.options.pt_accumulation=0;GameData.options.pt_denoiser=0
	var context:=await setup()
	Engine.max_fps=30;GameData.options.fps_limit=1
	GameData.options.q_water_rt_quality=0;GameData.options.gfx_water_reflections=3;t.apply_gfx()
	check(await ready_mode(false),"campaign begins with existing RT water")
	if not t._reflection._rt_ready:await finish_water_live(context);return
	await record("water-rt")
	GameData.options.pt_mode=1;GameData.options.rt_gi=1;GameData.options.rt_shadows=1
	check(await ready_mode(true),"enabling PT replaces RT water only after a complete path-traced frame")
	if not t._reflection._rt is PathWater:await finish_water_live(context);return
	var r: Node=t._reflection
	check(r._rt_live.path_materials and r._rt_live.lighting_camera_mask>=0 and r._rt_live._plane==-INF,"campaign water retains full PT material and underwater transport geometry")
	check(r._rt_frame!=null and not r._rt_frame.is_inside_tree(),"reflected history producer never processes a duplicate main-view scene")
	check(t._water_mat.get_shader_parameter("planar_texture")==r._rt.reflection_output(),"water material samples composed HDR instead of diffuse illumination")
	await record("water-pt")
	var previous: Object=r._rt
	GameData.options.pt_denoiser=1
	for i in 180:
		await frames(1)
		if r._rt.nrd_active and r._rt.nrd.directional:break
	check(r._rt==previous and r._rt.nrd_active and r._rt.nrd._description.directional,"live water setting activates directional NRD without rebuilding acceleration structures")
	for i in 9:
		var light:=OmniLight3D.new();context[1].add_child(light)
		light.global_position=camera.global_position+Vector3(i*0.2,2,0)
		light.omni_range=10;light.light_energy=0.05;light.light_color=Color(1,0.5,0.2)
		light.add_to_group(Gfx.POINT_LIGHT_GROUP)
	r._rt_topology_poll=0
	await frames(40)
	check(r._rt_lights.size()>7,"water PT receives the same extended local-light table as the main view")
	GameData.options.pt_mode=2
	await frames(30)
	check(r._rt==previous and r._rt._deep_paths and r._rt.output_ready(),"four-bounce water selects the deep integrator without a scene rebuild")
	await record("water-pt-directional")
	GameData.options.pt_accumulation=1;await frames(30)
	check(not r._rt.nrd_active and r._rt.output_ready(),"water Still scene bypasses NRD and retains HDR output")
	GameData.options.pt_accumulation=0
	r._rt_center+=Vector3(20,0,0)
	check(await ready_mode(true) and r._rt!=previous,"streamed water scene replacement retains the PT view")
	check(r._rt_frame!=null and r._rt_pending_frame==null and r._rt.nrd.directional,"replacement owns one independent reflected history producer")
	GameData.options.pt_mode=0
	check(await ready_mode(false),"disabling PT restores existing RT water")
	check(r._rt_frame==null and r._rt_pending_frame==null,"returning to RT releases reflected PT history producers")
	await finish_water_live(context)

func finish_water_live(context: Array) -> void:
	FileAccess.open(out.path_join("pt-water-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stages":stages},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_TRACE_WATER_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
