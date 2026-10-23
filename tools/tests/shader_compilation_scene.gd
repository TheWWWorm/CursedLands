extends "res://tools/tests/path_trace_resolution.gd"
## Actual campaign RT/PT preparation, including a lazy same-device variant.
## The two stale acknowledgments and one failure notification are explicit
## contract injections; all snapshots, pipelines and successful renders are real.
const Screen = preload("res://src/ui/shader_compilation_screen.gd")
var controller: Node
var campaign: Game
var progress_rows: Array[Dictionary] = []
var presented_rows: Array[Dictionary] = []
var preparation_screens := {}
var seen_presentations := {}
var cover_captures := {}
var preparation_cases: Array[Dictionary] = []
var case_name := "setup"
var old_observer := Callable()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func observe_progress(value: Dictionary) -> void:
	if not is_instance_valid(controller): return
	var screen_id: int=Screen._current.get_instance_id() if Screen.active() else 0
	if screen_id!=0 and Screen._current._owners.has(controller._preparation_owner):
		if not preparation_screens.has(case_name): preparation_screens[case_name]={}
		preparation_screens[case_name][screen_id]=true
	var row := value.duplicate(true)
	row.merge({"case":case_name,"owner":String(controller._preparation_owner),
		"token":controller._preparation_token,"waiting_id":controller._preparation_waiting_id,
		"completed_id":controller._preparation_completed_id,"drawn_frames":Engine.get_frames_drawn(),
		"screen_id":screen_id,"screen_active":Screen.active(),
		"screen_pause":Screen.owns_pause(get_tree()),"paused":get_tree().paused})
	if progress_rows.size()<4000: progress_rows.append(row)

func case_screen_active(label: String) -> bool:
	return Screen.active() and preparation_screens.get(label,{}).has(Screen._current.get_instance_id())

func capture_cover(label: String,source: String) -> void:
	if cover_captures.has(label) or not case_screen_active(label): return
	var image := get_viewport().get_texture().get_image()
	var valid: bool=image!=null and not image.is_empty()
	check(valid,label+": preparation cover has actual rendered pixels")
	var covered := false;var saved := false
	if valid:
		var pixel := image.get_pixel(8,8)
		covered=absf(pixel.r-Screen.BACKGROUND.r)<0.08 and absf(pixel.g-Screen.BACKGROUND.g)<0.08 \
			and absf(pixel.b-Screen.BACKGROUND.b)<0.08
		check(covered,label+": preparation covers the campaign view")
		saved=image.save_png(out.path_join(label+".png"))==OK
		check(saved,label+": preparation capture saved")
	cover_captures[label]={"source":source,"screen_id":Screen._current.get_instance_id(),
		"drawn_frames":Engine.get_frames_drawn(),"pixels_valid":valid,"covered":covered,"saved":saved}

func observe_post_draw() -> void:
	if not is_instance_valid(controller) or not case_screen_active(case_name): return
	# The controller may release its owner before this coroutine's next poll.
	# Observe the same actual screen through finishing, not just owner lifetime.
	var screen_id: int=Screen._current.get_instance_id()
	var drawn_frames := Engine.get_frames_drawn()
	var key := "%s:%d:%d"%[case_name,screen_id,drawn_frames]
	var new_frame := not seen_presentations.has(key)
	seen_presentations[key]=true
	if presented_rows.size()<8000:
		presented_rows.append({"case":case_name,"screen_id":screen_id,"drawn_frames":drawn_frames,
			"new_frame":new_frame,"phase":Screen._current._phase,"owner":String(controller._preparation_owner),
			"screen_pause":Screen.owns_pause(get_tree()),"paused":get_tree().paused})
	capture_cover(case_name,"frame_post_draw")

func save_preparation_report() -> void:
	FileAccess.open(out.path_join("shader-compilation-scene.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"cases":preparation_cases,"progress":progress_rows,
		"presentations":presented_rows,
		"driver":RenderingServer.get_current_rendering_driver_name(),"device":RenderingServer.get_video_adapter_name(),
		"profile":OS.get_user_data_dir(),"stats":controller.stats if is_instance_valid(controller) else {},
		"note":"Native campaign builds and renders. Stale acknowledgments, invalid render arguments and a pipeline-failure notification are explicitly injected; successful readiness is never fabricated."},"\t"))

func wait_preparation(label: String,previous_id := 0,expect_cover := true,allow_retry := false) -> bool:
	var started := Time.get_ticks_msec()
	var cover_frames := 0;var pause_frames := 0;var waiting_with_old_output := 0
	var success := false
	# Explicit synchronous processing may already have presented the cover and
	# queued a fast render acknowledgment before the first await below.
	if expect_cover: capture_cover(label,"before_wait_after_present")
	while Time.get_ticks_msec()-started<90_000:
		await frames(1)
		await RenderingServer.frame_post_draw
		var held: bool=not controller._preparation_owner.is_empty()
		if held:
			cover_frames+=1
			if Screen.owns_pause(get_tree()) and get_tree().paused: pause_frames+=1
			if controller.device!=null and controller.device.output_ready() and controller._preparation_completed_id==0:
				waiting_with_old_output+=1
		if controller._failed and not allow_retry: break
		success=controller.device!=null and controller.device.get_instance_id()!=previous_id and controller.device.output_ready() \
			and controller.stats.get("active",false) and not controller.stats.get("rebuilding",false) \
			and not held and not Screen.active()
		if success: break
	var events := progress_rows.filter(func(row: Dictionary): return row.case==label and not String(row.owner).is_empty())
	var presentations := presented_rows.filter(func(row: Dictionary): return row.case==label and row.new_frame)
	var paused_presentations := presentations.filter(func(row: Dictionary): return row.screen_pause and row.paused)
	check(success,label+": real output is bound and the compilation cover settles within its deadline")
	check(not events.is_empty() if expect_cover else events.is_empty(),label+": explicit requests alone create a scene preparation owner")
	if expect_cover:
		check(not presentations.is_empty() and not paused_presentations.is_empty(),
			label+": controller progresses while its visible single-player cover owns the pause")
		check(cover_captures.has(label) and cover_captures[label].covered and cover_captures[label].saved,
			label+": actual presented cover was captured before removal")
	preparation_cases.append({"case":label,"success":success,"elapsed_ms":Time.get_ticks_msec()-started,
		"cover_frames":cover_frames,"owned_pause_frames":pause_frames,"waiting_with_old_output_frames":waiting_with_old_output,
		"presented_cover_frames":presentations.size(),"presented_pause_frames":paused_presentations.size(),
		"owner_progress_events":events.size(),"capture":cover_captures.get(label,{}),"allow_retry":allow_retry,
		"device_id":controller.device.get_instance_id() if controller.device!=null else 0,
		"completed_renders":controller.device.completed_renders if controller.device!=null else 0,
		"token":controller._preparation_token,"stats":controller.stats.duplicate(true)})
	save_preparation_report()
	return success

func wait_cover_removed(label: String) -> void:
	var started := Time.get_ticks_msec()
	while Screen.active() and Time.get_ticks_msec()-started<5000:
		await frames(1);await RenderingServer.frame_post_draw
	check(not Screen.active(),label+": canceled scene preparation releases the shared cover")

func change_mode(path: int,quality: int,scene := 0) -> void:
	GameData.options.merge({"pt_mode":path,"q_rt_lighting":quality,"rt_shadows":scene,"rt_gi":scene},true)
	Gfx.apply_env(campaign._env)

func run() -> void:
	GameData.options.merge({"pt_mode":0,"rt_shadows":0,"rt_gi":0,"fsr_upscaling":0,"fsr_frame_generation":0},true)
	var context := await setup();campaign=context[1]
	# Keep the fixed regression view, but make it the actual CameraRig view so
	# the shared screen exercises production single-player pause ownership.
	campaign.rig.camera=camera
	controller=campaign.get_node("SceneRaytrace")
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,
		"gfx_foliage_light":1,"gfx_terrain_cliffs":1,"pt_accumulation":0,"render_scale":4},true)
	GameData._apply_window();t.apply_gfx();Gfx.apply_env(campaign._env)
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await wait_cover_removed("initial material preparation")
	old_observer=Screen.on_progress;Screen.on_progress=observe_progress
	RenderingServer.frame_post_draw.connect(observe_post_draw)
	check(controller.process_mode==Node.PROCESS_MODE_ALWAYS,"scene/PT controller continues during a screen-owned pause")

	case_name="initial-path"
	change_mode(1,0)
	if not await wait_preparation(case_name): await finish(context);return
	var phases := progress_rows.filter(func(row: Dictionary): return row.case==case_name).map(func(row: Dictionary): return row.phase)
	check(phases.has(Screen.GEOMETRY) and phases.has(Screen.PATH_TRACE) and phases.has(Screen.FIRST_FRAME),
		"initial PT request reports actual geometry, pipeline and first-frame stages")
	var device_id: int=controller.device.get_instance_id()
	var tlas: RID=controller.device._tlas
	# An invalid request must not be acknowledged by a previously valid image.
	controller.set_process(false)
	Controller.Device.dispatch(controller.device,&"render_preparation",[-7,Vector2i.ZERO,PackedByteArray()])
	var rejected: Array=await controller.device.rendered
	check(rejected==[-7,false] and controller.device.output_ready(),
		"render preparation rejects an unrendered request even when old output remains ready")

	case_name="same-device-deep"
	var previous_token: int=controller._preparation_token
	change_mode(2,0);controller._process(1.0/60.0)
	var requested_token: int=controller._preparation_token
	check(not controller._preparation_owner.is_empty() and controller._preparation_completed_id==0 and controller.device.output_ready(),
		"same-device deep PT keeps its cover pending despite valid shallow output")
	controller._rendered(previous_token,true,device_id)
	controller._rendered(requested_token,true,device_id+1)
	check(controller._preparation_completed_id==0 and not controller._preparation_owner.is_empty(),
		"stale request and wrong-device acknowledgments cannot release the current cover")
	controller.set_process(true)
	if not await wait_preparation(case_name): await finish(context);return
	check(controller.device.get_instance_id()==device_id and controller.device._tlas==tlas and controller.device._deep_paths,
		"deep PT lazily selects its real variant while retaining the device and acceleration structures")

	case_name="quality-resize"
	change_mode(2,1)
	if not await wait_preparation(case_name): await finish(context);return
	check(controller.device.get_instance_id()==device_id and controller.device._tlas==tlas \
		and controller.device.output.get_size()==Vector2(960,540),"quality apply waits for real resized output while retaining the scene")

	case_name="explicit-render-scale"
	var revision: int=GameData.graphics_revision
	GameData.set_options({"render_scale":0})
	if not await wait_preparation(case_name): await finish(context);return
	check(GameData.graphics_revision==revision+1 and controller.device.get_instance_id()==device_id \
		and controller.device.output.get_size()==Vector2(480,270),
		"graphics settings revision covers a real PT resize without changing its mode key")

	case_name="explicit-material-topology"
	var extra := Node3D.new();extra.name="ShaderPreparationTopology";campaign.world.add_child(extra)
	extra.global_position=camera.global_position+Vector3(0,-2,-5)
	var mesh := MeshInstance3D.new();mesh.mesh=BoxMesh.new();mesh.material_override=StandardMaterial3D.new();extra.add_child(mesh)
	campaign.world.objects["shader-preparation-topology"]=extra
	revision=GameData.graphics_revision
	GameData.set_options({"gfx_materials":0})
	if not await wait_preparation(case_name,device_id): await finish(context);return
	check(GameData.graphics_revision==revision+1 and controller._scene._nodes.has(mesh.get_instance_id()),
		"explicit material apply survives same-frame topology retirement and waits for the new real scene")
	device_id=controller.device.get_instance_id()

	case_name="routine-recenter"
	var quiet_token: int=controller._preparation_token
	camera.global_position+=Vector3(20,0,0)
	if not await wait_preparation(case_name,device_id,false): await finish(context);return
	check(controller._preparation_token==quiet_token,"routine camera recenter does not reopen a shader-preparation request")
	device_id=controller.device.get_instance_id()

	case_name="failed-request"
	controller.set_process(false);change_mode(2,0);controller._process(1.0/60.0)
	check(not controller._preparation_owner.is_empty(),"failure case begins an explicit quality request")
	controller._prepared(false,device_id)
	check(controller._preparation_owner.is_empty() and controller.device==null and controller._failed,
		"injected active pipeline failure releases the preparation owner and enters fallback")
	controller.set_process(true)
	case_name="automatic-retry"
	if not await wait_preparation(case_name,device_id,false,true): await finish(context);return

	case_name="scene-raytracing"
	change_mode(0,0,1)
	if not await wait_preparation(case_name): await finish(context);return
	phases=progress_rows.filter(func(row: Dictionary): return row.case==case_name).map(func(row: Dictionary): return row.phase)
	check(not controller.stats.path_tracing and phases.has(Screen.RAYTRACE),"scene RT uses its distinct preparation phase and actual output")

	case_name="disable-cancels"
	controller.set_process(false);change_mode(0,1,1);controller._process(1.0/60.0)
	check(not controller._preparation_owner.is_empty(),"disable case reaches a pending scene preparation")
	change_mode(0,1,0);controller._process(1.0/60.0)
	check(controller._preparation_owner.is_empty() and controller.device==null,"disabling scene lighting cancels its pending preparation")
	controller.set_process(true);await wait_cover_removed(case_name)
	case_name="exit-cancels"
	controller.set_process(false);change_mode(1,0);controller._process(1.0/60.0)
	check(not controller._preparation_owner.is_empty(),"exit case starts with a real pending PT preparation")
	await finish(context)

func finish(context: Array) -> void:
	Screen.on_progress=old_observer
	if RenderingServer.frame_post_draw.is_connected(observe_post_draw): RenderingServer.frame_post_draw.disconnect(observe_post_draw)
	context[1].queue_free();context[0].queue_free();await frames(16)
	check(not Screen.active(),"controller exit leaves no scene compilation cover")
	TexUpscale.shutdown();save_preparation_report()
	print("SHADER_COMPILATION_SCENE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)

func _exit_tree() -> void:
	Screen.on_progress=old_observer
	if RenderingServer.frame_post_draw.is_connected(observe_post_draw): RenderingServer.frame_post_draw.disconnect(observe_post_draw)
