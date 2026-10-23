extends "res://tools/tests/path_trace_performance.gd"
## The production campaign controller, actual internal raster buffers and PT
## images must agree through render-scale, temporal-upscaler and resize changes.
const Controller = preload("res://src/game/fx/scene_raytrace.gd")

class RenderSizeProbe extends CompositorEffect:
	var internal_size := Vector2i.ZERO
	var projection_changes := 0
	var _projection := Projection()
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_kind: int,data: RenderData) -> void:
		var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
		internal_size = buffers.get_internal_size()
		var projection := data.get_render_scene_data().get_cam_projection()
		if projection != _projection: projection_changes += 1
		_projection = projection

var probe: RenderSizeProbe
var resolution_rows := []
var sdk_readiness := []

func configure_resolution_game() -> Array:
	var context := await setup()
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,
		"gfx_foliage_light":1,"gfx_terrain_cliffs":1,"rt_shadows":0,"rt_gi":0,
		"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,"render_scale":4,
		"q_aa":0,"fsr_upscaling":0,"fsr_frame_generation":0},true)
	var window_size:=Vector2i(1280,720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pt-bench-resolution="):
			var dimensions:=arg.trim_prefix("--pt-bench-resolution=").split("x")
			if dimensions.size()==2:window_size=Vector2i(int(dimensions[0]),int(dimensions[1])).max(Vector2i(128,128))
	GameData.resolution_size="%dx%d"%[window_size.x,window_size.y]
	GameData.options.resolution=maxi(0,GameData.resolutions().find(window_size))
	GameData._apply_window();t.apply_gfx();Gfx.apply_env(context[1]._env)
	get_window().min_size=Vector2i(1,1);get_window().borderless=true;get_window().size=window_size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	probe=RenderSizeProbe.new()
	var compositor:=Compositor.new();compositor.compositor_effects=[probe];camera.compositor=compositor
	var owner: Node=context[1].get_node("SceneRaytrace")
	check(await ready_snapshot(owner),"resolution fixture prepares the real campaign PT snapshot")
	return context

func apply_resolution_settings(aa: int,render_scale: int,fsr:=0,fsr_quality:=1) -> void:
	GameData.options.merge({"q_aa":aa,"render_scale":render_scale,"fsr_upscaling":fsr,
		"fsr_quality":fsr_quality,"fsr_frame_generation":0},true)
	GameData._apply_window()

func upscaler_snapshot() -> Dictionary:
	var bridge:=FsrGraphics.bridge()
	var state: Dictionary=bridge.call("get_status") if bridge!=null else {}
	state["viewport_mode"]=int(camera.get_viewport().scaling_3d_mode)
	state["viewport_scale"]=camera.get_viewport().scaling_3d_scale
	state["requested_upscaling"]=GameData.option("fsr_upscaling")
	state["requested_quality"]=GameData.option("fsr_quality")
	return state

func sdk_status_ready(state: Dictionary) -> bool:
	if GameData.option("fsr_upscaling")<=0 or not FsrGraphics.sr_active():return false
	var sdk_mode:=ClassDB.class_get_integer_constant("Viewport","SCALING_3D_MODE_FSR_SDK")
	var version:="3.1." if GameData.option("fsr_upscaling")==1 else "4."
	return state.viewport_mode==sdk_mode \
		and is_equal_approx(float(state.viewport_scale),FsrGraphics.SCALES[GameData.option("fsr_quality")]) \
		and not state.get("temporal_shaders_initializing",true) \
		and not state.get("upscaler_initializing",true) and not state.get("frame_generation_initializing",true) \
		and int(state.get("last_error",-1))==0 \
		and String(state.get("upscaler_provider","")).begins_with(version)

func wait_for_sdk(label: String) -> bool:
	# A selected mode and smaller raster buffers do not prove the SDK is
	# running: cold advanced shaders can compile behind ordinary raster frames.
	var before:=upscaler_snapshot();var started:=Time.get_ticks_msec();var state:=before
	var ready:=false;var rendered:=0
	while Time.get_ticks_msec()-started<180_000:
		await RenderingServer.frame_post_draw
		rendered+=1;state=upscaler_snapshot()
		ready=sdk_status_ready(state) and int(state.get("upscale_evaluations",0))-int(before.get("upscale_evaluations",0))>=3
		if ready:break
	var row:={"case":label,"ready":ready,"wait_ms":Time.get_ticks_msec()-started,
		"rendered_frames":rendered,"before":before,"after":state}
	sdk_readiness.append(row)
	FileAccess.open(out.path_join("sdk-readiness.json"),FileAccess.WRITE).store_string(JSON.stringify(sdk_readiness,"\t"))
	check(ready,label+": SDK provider, active mode and successful upscaling settle before measurement")
	print("PATH_RESOLUTION_SDK_READY ",JSON.stringify(row))
	return ready

func check_sdk_measurement(label: String,before: Dictionary,after: Dictionary,minimum_frames: int) -> void:
	check(sdk_status_ready(before) and sdk_status_ready(after),label+": SDK stays ready in the requested mode throughout sampling")
	check(int(after.get("upscale_evaluations",0))-int(before.get("upscale_evaluations",0))>=minimum_frames,
		label+": measured successful SDK upscaling evaluations")

func expected_trace_size(quality: int) -> Vector2i:
	# Input comes from RenderSceneBuffersRD, not the controller's size helper.
	return Vector2i((Vector2(probe.internal_size)*[0.5,0.75,1.0][quality]).round()).max(Vector2i(2,2))

func check_targets(owner: Node,label: String,quality: int) -> Dictionary:
	var expected:=expected_trace_size(quality)
	var guide: Image=owner.device.guide.get_image()
	var light: Image=owner.device.output.get_image()
	check(owner.stats.get("active",false) and owner.stats.get("path_tracing",false),label+": production PT remains active")
	check(owner.stats.size==[expected.x,expected.y],label+": controller agrees with actual raster resolution and quality")
	check(owner.stats.render_size==[probe.internal_size.x,probe.internal_size.y],label+": reported render size agrees with the compositor")
	check(guide.get_size()==expected and light.get_size()==expected,label+": real GPU guide and lighting textures match")
	check(owner.stats.path_samples==[1,2,4][quality],label+": quality retains its sample count")
	var hits:=0;var finite:=true;var total:=0.0
	for y in range(0,guide.get_height(),13):
		for x in range(0,guide.get_width(),13):
			var g:=guide.get_pixel(x,y);var c:=light.get_pixel(x,y)
			finite=finite and is_finite(g.a) and is_finite(c.r) and is_finite(c.g) and is_finite(c.b)
			if g.a>0.0:hits+=1;total+=c.r+c.g+c.b
	check(finite and hits>20 and total>0.01,label+": scaled GPU buffers contain finite lit receivers")
	var row:={"case":label,"actual_render_size":[probe.internal_size.x,probe.internal_size.y],
		"texture_size":[guide.get_width(),guide.get_height()],"raster_projection_changes":probe.projection_changes,
		"lit_guide_samples":hits,"stats":owner.stats.duplicate(),"upscaler_status":upscaler_snapshot()}
	resolution_rows.append(row)
	return row

func image_comparison(reference: Image,current: Image) -> Dictionary:
	var delta:=0.0;var old_energy:=0.0;var new_energy:=0.0;var count:=0
	# Exclude the FPS HUD and retain the foreground geometry and terrain.
	for y in range(150,mini(reference.get_height(),current.get_height()),3):
		for x in range(0,mini(reference.get_width(),current.get_width()),3):
			var a:=reference.get_pixel(x,y);var b:=current.get_pixel(x,y)
			delta+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
			old_energy+=a.r+a.g+a.b;new_energy+=b.r+b.g+b.b;count+=3
	return {"mean_absolute_error":delta/maxi(count,1),"reference_mean":old_energy/maxi(count,1),
		"scaled_mean":new_energy/maxi(count,1),"energy_ratio":new_energy/maxf(old_energy,0.00001)}

func run() -> void:
	# Odd widths expose the engine's truncation before quality rounding.
	for row in [[Vector2(1280,720),0,1.0,Vector2i(640,360)],
		[Vector2(1280,720),1,1.0,Vector2i(960,540)],
		[Vector2(1280,720),2,1.0,Vector2i(1280,720)],
		[Vector2(1280,720),0,2.0/3.0,Vector2i(427,240)],
		[Vector2(1280,720),2,2.0/3.0,Vector2i(853,480)],
		[Vector2(1279,719),1,0.5,Vector2i(479,269)],
		[Vector2(720,1280),2,0.5,Vector2i(360,640)],
		[Vector2(1280,720),1,1.25,Vector2i(1200,675)],
		[Vector2.ZERO,0,0.5,Vector2i(2,2)]]:
		check(Controller.target_size(row[0],row[1],row[2])==row[3],"trace sizing contract "+str(row))
	var context:=await configure_resolution_game();var game: Game=context[1]
	var owner: Node=game.get_node("SceneRaytrace")
	if not owner.stats.get("active",false):get_tree().quit(1);return
	var device: Object=owner.device;var scene_handle: RID=device._tlas
	var handles:=[device.output.get_rid(),device.guide.get_rid(),device.shadow0.get_rid(),device.shadow1.get_rid()]
	var projection:=camera.get_camera_projection()
	# label, AA, ordinary render scale, SDK upscaler, SDK quality, PT quality.
	var cases:=[["native-low",0,4,0,1,0],["native-medium",0,4,0,1,1],["native-high",0,4,0,1,2],
		["render-half",0,0,0,1,0],["supersampled",0,5,0,1,1],
		["fsr2-low",5,4,0,1,0],["fsr2-medium",5,4,0,1,1],["fsr2-high",5,4,0,1,2]]
	var sdk:=FsrGraphics.facts()
	if sdk.api and sdk.sr3:
		cases.append_array([["fsr31-native",0,4,1,0,0],["fsr31-quality",0,4,1,1,0],
			["fsr31-balanced",0,4,1,2,0],["fsr31-performance",0,4,1,3,0]])
	for choice: Array in cases:
		apply_resolution_settings(choice[1],choice[2],choice[3],choice[4])
		GameData.options.q_rt_lighting=choice[5]
		if choice[3]>0 and not await wait_for_sdk(choice[0]):
			get_tree().quit(1);return
		await frames(35)
		var changed:=probe.projection_changes
		var sdk_before:=upscaler_snapshot()
		await frames(12)
		var sdk_after:=upscaler_snapshot()
		if choice[3]>0:check_sdk_measurement(choice[0],sdk_before,sdk_after,10)
		var row:=check_targets(owner,choice[0],choice[5])
		row["upscaler_before"]=sdk_before;row["upscaler_after"]=sdk_after
		row["upscale_evaluations"]=int(sdk_after.get("upscale_evaluations",0))-int(sdk_before.get("upscale_evaluations",0))
		check(owner.device==device and device._tlas==scene_handle,choice[0]+": scaling retains acceleration structures")
		check(handles==[device.output.get_rid(),device.guide.get_rid(),device.shadow0.get_rid(),device.shadow1.get_rid()],choice[0]+": output handles stay stable across reallocations")
		check(camera.get_camera_projection()==projection,choice[0]+": PT keeps the unjittered camera projection")
		if choice[1]==5 or choice[3]>0:
			check(probe.projection_changes>changed,choice[0]+": temporal raster jitter is active beside the stable PT lattice")
		row["capture"]=choice[0]+".png";await shot(choice[0])
	# Compare the old and new PT lattices under identical raster upscaling.
	apply_resolution_settings(5,4);GameData.options.q_rt_lighting=1
	owner._window_resolution_reference=true;await frames(80)
	var reference:=await capture("fsr2-window-reference")
	owner._window_resolution_reference=false;await frames(80)
	var scaled:=await capture("fsr2-render-resolution")
	var comparison:=image_comparison(reference,scaled)
	check(comparison.mean_absolute_error<0.04 and absf(comparison.energy_ratio-1.0)<0.1,
		"render-resolution PT retains the same scene lighting under matched FSR2 raster settings: "+str(comparison))
	# A small camera motion must reproject at the new lattice, then a resize
	# must restart progressive history without replacing the scene snapshot.
	var pose:=camera.global_transform;camera.rotate_y(0.008);await frames(3)
	check(owner.stats.get("history_reused",false),"responsive scaled PT reprojects through camera motion")
	camera.global_transform=pose;GameData.options.pt_accumulation=1;await frames(45)
	check(owner.stats.accumulation_frames>30,"scaled stationary scene accumulates progressively")
	apply_resolution_settings(0,2);await frames(2);await RenderingServer.frame_post_draw
	check(owner.stats.accumulation_frames<=3,"render-scale change restarts progressive accumulation")
	await frames(12);check_targets(owner,"progressive-rescaled",1)
	get_window().size=Vector2i(961,541);await frames(2);await RenderingServer.frame_post_draw
	check(owner.stats.accumulation_frames<=3,"odd-size window resize restarts progressive accumulation")
	await frames(12);check_targets(owner,"odd-window",1)
	GameData.options.pt_mode=0;GameData.options.rt_gi=1;GameData.options.pt_accumulation=0
	Gfx.apply_env(game._env);check(await ready_scene(owner),"switching to scene RT still prepares its pipeline")
	check(owner.stats.size==[721,406] and not owner.stats.path_tracing,"scene RT retains window-relative quality at a reduced render scale")
	FileAccess.open(out.path_join("path-resolution.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rows":resolution_rows,"matched_fsr2_comparison":comparison,
		"sdk_readiness":sdk_readiness,
		"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name()},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
