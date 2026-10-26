extends "res://tools/tests/path_trace_camera_routes.gd"
## Required native RR evaluation, full-resolution noisy PT, fresh material
## guides, camera/resize resets and return to the selected NRD mode.
const GuideAudit=preload("res://tools/tests/path_trace_rr_input_audit.gd")
var rr_stages:=[]
var readbacks: Array[Image]=[]
var retired_images: Array[RID]=[]
var retirement_ok:=false
signal inspected

func native_status() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge()!=null else {}

func rr_ready(rt: Node) -> bool:
	var before:=int(native_status().get("rr_evaluations",0))
	var stable:=0
	for i in 1000:
		await frames(1)
		if rt._failed or rt._rr_failed or not RtxGraphics.facts().rr:return false
		if rt._rr_effect!=null and rt._rr_effect.submitted_frames>5 and native_status().get("rr_active",false) \
			and not ShaderCompilationScreen.active() and not rt.stats.get("rebuilding",true) \
			and native_status().rr_input_size==Vector2i(Vector2(get_window().size)*get_window().scaling_3d_scale) \
			and rt._rr_effect.last_size==native_status().rr_input_size:
			stable+=1
		else:stable=0
		if stable>=6 and int(native_status().rr_evaluations)>=before+6:return true
	return false

func read_inputs(rt: Node) -> void:
	readbacks.clear()
	var device: Object=rt.device
	for i in 4:
		readbacks.append(Image.create_from_data(device._size.x,device._size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[i],0)))
		readbacks.append(Image.create_from_data(device._size.x,device._size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._history[i],0)))
	if rt._rr_effect!=null:
		for i in 4:
			readbacks.append(Image.create_from_data(device._size.x,device._size.y,false,Image.FORMAT_RH if i==3 else Image.FORMAT_RGBAH,device._rd.texture_get_data(rt._rr_effect._images[i],0)))
	inspected.emit.call_deferred()

func inspect_retirement() -> void:
	var rd:=RenderingServer.get_rendering_device()
	retirement_ok=retired_images.all(func(rid: RID):return not rd.texture_is_valid(rid))
	inspected.emit.call_deferred()

func record_rr(rt: Node,label: String) -> void:
	await frames(24);await RenderingServer.frame_post_draw
	var status:=native_status()
	await shot(label)
	rr_stages.append({"label":label,"status":status,"stats":rt.stats.duplicate(true),"frames":rt._rr_effect.submitted_frames if rt._rr_effect!=null else 0})
	FileAccess.open(out.path_join("rr-live-progress.json"),FileAccess.WRITE).store_string(JSON.stringify(rr_stages,"\t"))
	print("RR_STAGE ",label," ",status)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	print("RR_INITIAL ",native_status())
	check(RtxGraphics.facts().rr,"native SDK reports real RR capability")
	if not RtxGraphics.facts().rr:await finish_rr([],null);return
	resolution=Vector2i(1280,720)
	GameData.options.merge({"rtx_upscaling":2,"rtx_frame_generation":0,"pt_ray_reconstruction":0},true)
	var context:=await setup_route()
	if context.is_empty():await finish_rr(context,null);return
	GameData.options.fps_limit=1;Engine.max_fps=30
	GameData.options.rtx_upscaling=2;GameData._apply_window()
	var rt: Node=context[1].get_node("SceneRaytrace")
	check(await ready_scene(rt),"baseline campaign PT prepares")
	if rt.device==null:await finish_rr(context,rt);return
	check(rt.device.nrd_active and not rt.device.ray_reconstruction,"baseline uses NRD")
	await record_rr(rt,"rr-off-nrd")
	GameData.options.pt_ray_reconstruction=1
	check(await rr_ready(rt),"actual DLSS RR evaluates the noisy campaign view")
	if rt._rr_effect==null or not native_status().get("rr_active",false):await finish_rr(context,rt);return
	await record_rr(rt,"rr-quality")
	var state:=native_status()
	check(state.get("rr_preset","")=="F" and int(state.get("rr_last_error",-1))==0,"latest transformer preset F evaluates without an SDK error")
	check(rt.device.ray_reconstruction and not rt.device.nrd_active and not rt.device._direct_valid,"RR bypasses main-view NRD, direct-light history and spatial denoising")
	check(rt.stats.size==rt.stats.render_size and Vector2i(rt.stats.size[0],rt.stats.size[1])==state.get("rr_input_size",Vector2i.ZERO),"trace pixels and all native RR inputs match full DLSS input resolution")
	RenderingServer.call_on_render_thread(read_inputs.bind(rt));await inspected
	var raw_exact:=readbacks.size()==12
	for i in 4:raw_exact=raw_exact and readbacks[i*2].get_data()==readbacks[i*2+1].get_data()
	check(raw_exact,"all four published lighting channels exactly match current noisy PT images")
	var finite:=true;var surfaces:=0;var max_hit:=0.0
	for y in range(0,readbacks[8].get_height(),8):
		for x in range(0,readbacks[8].get_width(),8):
			var n:=readbacks[10].get_pixel(x,y)
			var a:=readbacks[8].get_pixel(x,y);var s:=readbacks[9].get_pixel(x,y);var h:=readbacks[11].get_pixel(x,y).r
			finite=finite and is_finite(n.r+n.g+n.b+n.a+a.r+a.g+a.b+s.r+s.g+s.b+h) and n.a>=0 and n.a<=1 and h>=0
			if Vector3(n.r,n.g,n.b).length()>0.9:surfaces+=1
			max_hit=maxf(max_hit,h)
	check(finite and surfaces>100 and max_hit>0.1,"RR receives finite material guides, world normals, linear roughness and secondary hit distance")
	for i in 4:readbacks[8+i].save_exr(out.path_join("rr-guide-%d.exr"%i))
	var audit:=GuideAudit.new();audit.owner_effect=weakref(rt._rr_effect)
	var effects:=camera.compositor.compositor_effects;effects.append(audit);camera.compositor.compositor_effects=effects
	await audit.inspected
	check(audit.results.size()==5 and audit.results.all(func(value: bool):return value),"native camera/ray projections agree; bridge rejects missing, wrong-sized and wrong-format guides and accepts a complete set")
	effects.erase(audit);camera.compositor.compositor_effects=effects;audit=null
	GameData.options.pt_target_fps=3;await frames(10)
	check(rt.stats.adaptive_target_fps==0 and rt.stats.size==rt.stats.render_size,"RR pauses dynamic PT resolution without changing the saved frame target")
	var before:=native_status();var original:=camera.global_transform
	for i in 35:
		camera.global_position=original.origin+Vector3(sin(i*.07)*.3,0,0)
		await frames(1)
	var after:=native_status()
	check(int(after.rr_evaluations)-int(before.rr_evaluations)>=30 and int(after.dlss_evaluations)==int(before.dlss_evaluations),"moving camera evaluates RR instead of stacking SR")
	check(rt._rr_effect.last_projection!=camera.get_camera_projection(),"PT rays use the renderer's current subpixel jitter")
	await record_rr(rt,"rr-moving")
	camera.global_transform=original;camera.global_position+=Vector3(7,0,0)
	before=native_status();await frames(12)
	check(int(native_status().rr_resets)>int(before.rr_resets),"camera cut resets RR history")
	GameData.options.rtx_upscaling=1;GameData._apply_window()
	check(await rr_ready(rt),"live DLAA size change recreates the RR context")
	await record_rr(rt,"rr-dlaa")
	check(rt.stats.size==[1280,720],"DLAA traces the full native input")
	GameData.options.rtx_upscaling=4;GameData.resolution_size="3840x2160"
	GameData._apply_window();get_window().size=Vector2i(3840,2160)
	check(await rr_ready(rt),"4K output recreates RR with Performance input resolution")
	await record_rr(rt,"rr-4k-performance")
	check(get_window().size==Vector2i(3840,2160) and rt.stats.size==[1920,1080] and native_status().rr_input_size==Vector2i(1920,1080),"native 4K output uses matching 1080p noisy inputs")
	check(int(native_status().rr_last_error)==0,"4K RR evaluates without an SDK error")
	GameData.resolution_size="1280x720";GameData.options.rtx_upscaling=2
	GameData._apply_window();get_window().size=Vector2i(1280,720)
	check(await rr_ready(rt),"return from 4K restores the quality-sized RR view")
	check(native_status().rr_input_size==Vector2i(853,480),"restored RR uses the current quality extent")
	var generation: int=rt.stats.snapshot_generation
	camera.global_position+=Vector3(20,0,0)
	check(await rr_ready(rt) and rt.stats.snapshot_generation>generation,"streaming promotes a freshly traced RR scene")
	GameData.options.pt_accumulation=1;await frames(24)
	check(rt._rr_effect==null and not rt.device.nrd_active and not rt.device.ray_reconstruction,"Still accumulation suspends RR and uses exact progressive lighting")
	GameData.options.pt_accumulation=0
	check(await rr_ready(rt),"returning to Responsive restores RR")
	# Suppress one callback without changing the selected setting. The engine
	# must not consume last frame's borrowed guide RIDs.
	rt._rr_effect.enabled=false;await frames(3);before=native_status();await frames(6)
	check(int(native_status().rr_evaluations)==int(before.rr_evaluations) and int(native_status().dlss_evaluations)>int(before.dlss_evaluations),"missing current-frame guides select SR instead of stale RR inputs")
	rt._rr_effect.enabled=true
	check(await rr_ready(rt),"current-frame guide resumption restores RR")
	retired_images.assign(rt._rr_effect._images)
	var retired_effect:=weakref(rt._rr_effect)
	GameData.options.pt_ray_reconstruction=0;GameData.options.pt_target_fps=0;GameData.options.pt_denoiser=1
	await frames(45)
	check(rt._rr_effect==null and camera.compositor==null and not rt.device.ray_reconstruction,"RR Off detaches its callback and releases the camera override")
	check(rt.device.nrd_active and rt.device.nrd.directional and int(native_status().rr_last_error)==0,"Off returns to selected directional NRD")
	RenderingServer.call_on_render_thread(inspect_retirement);await inspected
	check(retirement_ok and retired_effect.get_ref()==null,"RR Off releases every guide texture and the compositor owner")
	before=native_status();await frames(20)
	check(int(native_status().dlss_evaluations)>int(before.dlss_evaluations) and int(native_status().rr_evaluations)==int(before.rr_evaluations),"ordinary DLSS resumes without stale RR guides")
	check(RtxGraphics.facts().rr and RtxGraphics.sr_active(),"switching reconstruction retains native RR and SR capabilities")
	await record_rr(rt,"rr-off-directional")
	await finish_rr(context,rt)

func finish_rr(context: Array,rt: Node) -> void:
	FileAccess.open(out.path_join("rr-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"status":native_status(),"stages":rr_stages,"stats":rt.stats if rt!=null else {}},"\t"))
	if context.size()==2:context[1].queue_free();context[0].queue_free()
	await frames(16);TexUpscale.shutdown()
	print("PT_RR_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
