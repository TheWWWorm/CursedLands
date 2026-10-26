extends "res://tools/tests/water_raytrace_artifact.gd"
const Dielectric=preload("res://src/game/fx/path_trace_dielectric.gd")
var stages:=[]
func nrd_trace_size(extent: Vector2i) -> Vector2i:
	# This fixture fixes q_rt_lighting=0: NRD traces at half the applied
	# integer raster grid. DLSS/FSR may already have scaled that grid down.
	var raster:=Vector2i(Vector2(extent)*camera.get_viewport().scaling_3d_scale).max(Vector2i.ONE)
	return Vector2i(maxi(2,roundi(raster.x*.5)),maxi(2,roundi(raster.y*.5)))
func ready_transport(rt: Node,enabled:=true,after_generation: int=-1,water_version:=PackedFloat32Array(),extent:=Vector2i.ZERO) -> bool:
	for i in 1800:
		await frames(1)
		if rt._failed:return false
		if rt.device==null or not rt.device.output_ready() or rt.stats.get("rebuilding",true) or ShaderCompilationScreen.active() or rt.device.transmission.active!=enabled:continue
		# A working old scene is intentionally still active before the topology
		# poll and while retirement drains. Await the requested publication.
		if int(rt.stats.get("snapshot_generation",0))<=after_generation:continue
		if not water_version.is_empty() and (rt._scene==null or rt._scene._water_version!=water_version):continue
		if extent!=Vector2i.ZERO:
			if get_window().size!=extent or Vector2i(camera.get_viewport().get_visible_rect().size)!=extent:continue
			if rt.device.output.get_size()!=Vector2(nrd_trace_size(extent)):continue
		return true
	print("TRANSMISSION_WAIT_TIMEOUT ",{"enabled":enabled,"after_generation":after_generation,"generation":rt.stats.get("snapshot_generation",0),"extent":extent,"stats":rt.stats})
	return false
func record(rt: Node,label: String) -> void:
	await frames(12);await RenderingServer.frame_post_draw
	var image: Image=rt.device.transmission.colour.get_image()
	var water:=0;var glass:=0;var finite:=true
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			var c:=image.get_pixel(x,y)
			finite=finite and is_finite(c.r+c.g+c.b+c.a) and c.r>=0 and c.g>=0 and c.b>=0
			if c.a>.5 and c.a<1.5:water+=1
			elif c.a>1.5:glass+=1
	check(finite and water>30,label+": finite refracted water pixels in the real campaign")
	stages.append({"label":label,"water_pixels":water,"glass_pixels":glass,"stats":rt.stats.duplicate(true)})
	await shot(label)
	image.save_png(out.path_join(label+"-transport.png"))
func run() -> void:
	GameData.options.merge({"pt_mode":1,"pt_refraction":0,"pt_accumulation":0,"q_rt_lighting":0,"pt_denoiser":1,"pt_ray_reconstruction":0,"pt_restir":1,"pt_target_fps":0},true)
	var context:=await setup();Engine.max_fps=30;GameData.options.fps_limit=1
	var game: Game=context[1];game._update_daylight(false)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_transport(rt,false),"campaign starts with ordinary transparency")
	await shot("refraction-off")
	GameData.options.pt_refraction=1
	await frames(2)
	check(await ready_transport(rt),"enabling refraction builds actual water tiles and dispatches")
	if rt.device==null or not rt.device.transmission.active:await finish_transport(context,rt);return
	check(rt._scene.path_transmission and rt._scene.geometries.any(func(g: Dictionary):return g.get("dielectric",PackedFloat32Array()).size()==8),"campaign scene contains explicit water media")
	check(rt.device.nrd_active and rt.device._rtxdi_mode,"transmission coexists with directional NRD and actual RTXDI")
	await record(rt,"refraction-water")
	var original:=t._water_mat.shader;var audit:=Shader.new()
	audit.code=Gfx._function_tail(original.code,"fragment","""
    vec3 audit_colour;
    bool audit_match=ei_transmission(wpos,gn,1.0,PROJECTION_MATRIX*VIEW_MATRIX,audit_colour);
    ALBEDO=vec3(0.0);EMISSION=audit_match?vec3(0,1,0):vec3(1,0,0);ALPHA=1.0;ei_wave_scale=0.0;
""")
	t._water_mat.shader=audit;await frames(8)
	var coverage:=await capture("water-transmission-receivers");var matched:=0
	for y in range(0,coverage.get_height(),2):
		for x in range(0,coverage.get_width(),2):
			var c:=coverage.get_pixel(x,y)
			if c.g>.5 and c.g>c.r+.2 and c.g>c.b+.2:matched+=1
	check(matched>100,"actual raster water samples matching transparent guides")
	t._water_mat.shader=original
	# Add an explicit glass test object through the normal scene collector.
	var root:=Node3D.new();game.world.add_child(root);root.add_to_group(GameWorld.RAYTRACE_GEOMETRY_GROUP)
	root.global_position=camera.global_position-camera.global_basis.z*4+camera.global_basis.x*.65
	var before_glass: int=rt.stats.snapshot_generation
	var mesh:=MeshInstance3D.new();root.add_child(mesh)
	var box:=BoxMesh.new();box.size=Vector3(.8,1.2,.6);mesh.mesh=box
	mesh.material_override=Dielectric.material(1.5,Color(.25,.8,.95),1)
	check(await ready_transport(rt,true,before_glass),"authored glass enters the streamed PT scene")
	await record(rt,"refraction-glass")
	check(stages.back().glass_pixels>10,"actual glass geometry receives refracted radiance")
	var displayed:=await capture("glass-visible")
	var glass_pixel:=Vector2i(camera.unproject_position(root.global_position))
	var glass_colour:=displayed.get_pixelv(glass_pixel)
	check(glass_colour.r+glass_colour.g+glass_colour.b>.15,"unshaded glass displays the traced colour instead of a black silhouette")
	var old_level: PackedFloat32Array=t._level.duplicate()
	var before_level: int=rt.stats.snapshot_generation
	for i in t._level.size():t._level[i]+=.15
	t._water_mat.set_shader_parameter("level",t._level)
	check(await ready_transport(rt,true,before_level,t._level.duplicate()),"water level changes rebuild optical geometry")
	check(rt._scene._water_version==t._level,"published water geometry follows SetWaterLevel")
	print("TRANSMISSION_WATER_PUBLICATION ",before_level," -> ",rt.stats.snapshot_generation)
	before_level=rt.stats.snapshot_generation
	t._level=old_level;t._water_mat.set_shader_parameter("level",t._level)
	check(await ready_transport(rt,true,before_level,old_level),"original water level restores")
	print("TRANSMISSION_WATER_RESTORED ",before_level," -> ",rt.stats.snapshot_generation)
	for extent: Vector2i in [Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().size=extent;await frames(12)
		check(await ready_transport(rt,true,-1,PackedFloat32Array(),extent),"refraction survives viewport resize "+str(extent))
		await record(rt,"refraction-%dx%d"%[extent.x,extent.y])
		check(rt.device.transmission._size==nrd_trace_size(extent),"transparent images match the current trace grid "+str(extent))
	get_window().size=Vector2i(1280,720);await frames(12)
	# Windows additionally evaluates the real RR callback with transparency.
	if RtxGraphics.facts().get("rr",false):
		GameData.resolution_size="1280x720";GameData.options.rtx_upscaling=2;GameData.options.pt_ray_reconstruction=1;GameData._apply_window()
		var evaluated:=false
		for i in 600:
			await frames(1)
			var status: Dictionary=RtxGraphics.bridge().call("get_status")
			if status.get("rr_active",false) and status.get("rr_evaluations",0)>10 and rt.device.transmission.active:evaluated=true;break
		check(evaluated,"actual DLSS Ray Reconstruction evaluates alongside transparent radiance")
		await record(rt,"refraction-rr")
		var rr_display:=await capture("refraction-rr-visible")
		var rr_glass:=rr_display.get_pixelv(Vector2i(camera.unproject_position(root.global_position)))
		check(rr_glass.r+rr_glass.g+rr_glass.b>.15,"RR displays transmitted glass radiance instead of a black silhouette")
		var rr_transport: Image=rt.device.transmission.colour.get_image()
		var water_colour:=Vector3.ZERO;var water_samples:=0
		for y in range(0,rr_transport.get_height(),4):
			for x in range(0,rr_transport.get_width(),4):
				var traced:=rr_transport.get_pixel(x,y)
				if traced.a<.5 or traced.a>1.5:continue
				var at:=Vector2i(Vector2(x+.5,y+.5)*Vector2(rr_display.get_size())/Vector2(rr_transport.get_size()))
				var displayed_water:=rr_display.get_pixelv(at)
				water_colour+=Vector3(displayed_water.r,displayed_water.g,displayed_water.b);water_samples+=1
		water_colour/=maxi(water_samples,1)
		check(water_samples>100 and water_colour.z>water_colour.x-.03,"RR retains the campaign water colour instead of a red projection artifact")
		stages.back()["rr_visible_glass"]=rr_glass
		stages.back()["rr_visible_water_mean"]=water_colour
		stages.back()["rr_native_status"]=RtxGraphics.bridge().call("get_status")
		GameData.options.pt_ray_reconstruction=0
	var old: RefCounted=rt.device
	GameData.options.pt_refraction=0
	await frames(2)
	check(await ready_transport(rt,false),"Off restores ordinary water and glass fallback")
	check(old.transmission.bytes==0,"Off retires the previous optical image storage")
	await shot("refraction-restored")
	root.queue_free();await finish_transport(context,rt)
func finish_transport(context: Array,rt: Node) -> void:
	FileAccess.open(out.path_join("transmission-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stages":stages,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_TRANSMISSION_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
