extends "res://tools/tests/path_trace_stability.gd"
## Sustained live campaign qualification. Every cycle returns to the same zone,
## view and native Low setting before comparing engine allocation counters.
## Actors, animation, saves and asynchronous thumbnails use production paths.
var cycles:=6
var completed_cycles:=0
var require_sdk:=false
var cycle_rows:=[]
var transition_rows:=[]
var save_rows:=[]
var retirement_rows:=[]
var memory_trends:={}
var sdk_rows:=[]
var mode_wait:={}
const RECOVERY_MS:=30_000
const HOLD_MIN_FRAMES:=12

func _sdk_snapshot() -> Dictionary:
	var bridge:=FsrGraphics.bridge()
	var state: Dictionary=bridge.call("get_status") if bridge!=null else {}
	state["viewport_mode"]=int(get_viewport().scaling_3d_mode)
	state["viewport_scale"]=get_viewport().scaling_3d_scale
	state["requested_upscaling"]=GameData.option("fsr_upscaling")
	state["requested_quality"]=GameData.option("fsr_quality")
	return state

func _sdk_ready(state: Dictionary) -> bool:
	return FsrGraphics.sr_active() and GameData.option("fsr_upscaling")==1 \
		and state.get("viewport_mode",-1)==ClassDB.class_get_integer_constant("Viewport","SCALING_3D_MODE_FSR_SDK") \
		and is_equal_approx(float(state.get("viewport_scale",0)),FsrGraphics.SCALES[GameData.option("fsr_quality")]) \
		and not state.get("temporal_shaders_initializing",true) and not state.get("upscaler_initializing",true) \
		and not state.get("frame_generation_initializing",true) and int(state.get("last_error",-1))==0 \
		and String(state.get("upscaler_provider","")).begins_with("3.1.")

func _wait_sdk(label: String) -> bool:
	var before:=_sdk_snapshot();var began:=Time.get_ticks_msec();var state:=before;var ready:=false
	while running and Time.get_ticks_msec()-began<180_000:
		await RenderingServer.frame_post_draw
		state=_sdk_snapshot()
		ready=_sdk_ready(state) and int(state.get("upscale_evaluations",0))-int(before.get("upscale_evaluations",0))>=3
		if ready:break
	sdk_rows.append({"case":label,"ready":ready,"wait_ms":Time.get_ticks_msec()-began,"before":before,"after":state})
	check(ready,label+": actual SDK evaluations begin with the requested provider and settled shaders")
	_record("sdk-ready",sdk_rows.back())
	return ready

func _snapshot(reason: String,details: Dictionary={}) -> Dictionary:
	var row:=super._snapshot(reason,details)
	row["objects"]=_available(Performance.get_monitor(Performance.OBJECT_COUNT))
	row["resources"]=_available(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	row["nodes"]=_available(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	row["sdk"]=_sdk_snapshot()
	return row

func _persist(status: String) -> void:
	super._persist(status)
	var file:=FileAccess.open(out.path_join("path-sustained-results.json"),FileAccess.WRITE)
	if file==null:return
	file.store_string(JSON.stringify({"status":status,"checks":checks,"failures":failures,
		"requested_cycles":cycles,"completed_cycles":completed_cycles,"require_sdk":require_sdk,
		"elapsed_seconds":_elapsed(),"timeout_seconds":timeout_seconds,"phase_seconds":phase_seconds,
		"active_frames":active_frames,"instance_update_frames":instance_update_frames,"pose_update_frames":pose_update_frames,
		"active_zones":active_zones.keys(),"cycles":cycle_rows,"transitions":transition_rows,
		"saves":save_rows,"retirements":retirement_rows,"sdk_readiness":sdk_rows,"memory_trends":memory_trends,
		"last":last_row,"note":"Real campaign actors and ordinary hero movement; repeated native/temporal scale, PT bounce/quality/accumulation, scene RT and Off transitions. Engine allocated memory is not total driver residency. First two cycles warm caches; later same-state allocations have explicit growth budgets. No shader cache eviction or SDK shutdown workaround."},"\t"))
	file.flush();file.close()

func _current_device_weak() -> WeakRef:
	# Godot 4.7 add_temporary() can reuse packed-data slots without updating
	# can_contain_object, retaining rt.device across run()'s awaits. Keep this
	# read synchronous; path_trace_weakref_regression.gd reproduces the issue.
	var current: Object=rt.device if is_instance_valid(rt) else null
	return weakref(current) if is_instance_valid(current) else null

func _retired(old: WeakRef,label: String) -> void:
	var began:=Time.get_ticks_msec()
	while running and old.get_ref()!=null and Time.get_ticks_msec()-began<10_000:
		await RenderingServer.frame_post_draw
	var released:=old.get_ref()==null
	check(released,label+": previous PT device owner is released after render-thread work drains")
	retirement_rows.append({"case":label,"released":released,"wait_ms":Time.get_ticks_msec()-began})
	_record("retired-device",retirement_rows.back())

func _mode_snapshot(mode: int,quality_value: int,scale: float) -> Dictionary:
	# Return only values. Reading a device in an awaited function can retain a
	# hidden GDScript temporary and invalidate the subsequent retirement probe.
	var s: Dictionary=rt.stats if is_instance_valid(rt) else {}
	var current: Object=rt.device if is_instance_valid(rt) else null
	var published: bool=current!=null and current.output_ready()
	var output_size:=Vector2i(current.output.get_size()) if published else Vector2i.ZERO
	var guide_size:=Vector2i(current.guide.get_size()) if published else Vector2i.ZERO
	var display:=get_viewport().get_visible_rect().size
	var applied_scale:=get_viewport().scaling_3d_scale
	var raster:=Vector2i(display*applied_scale).max(Vector2i.ONE)
	var trace_input:=raster if mode>0 else Vector2i(display)
	var expected:=Vector2i((Vector2(trace_input)*[0.5,0.75,1.0][quality_value]).round()).max(Vector2i(2,2))
	var good: bool=is_equal_approx(applied_scale,scale)
	if mode<0:
		good=good and not s.get("active",false) and current==null
	else:
		good=good and s.get("active",false) and bool(s.get("path_tracing",false))==(mode>0) \
			and s.get("quality",-1)==quality_value and is_equal_approx(float(s.get("render_scale",0)),scale) \
			and published and output_size==expected and guide_size==expected and s.get("size",[])==[expected.x,expected.y]
		if mode>0:good=good and s.get("path_bounces",0)==mode*2
	return {"matches":good,"active":s.get("active",false),"output_ready":published,
		"failed":rt._failed if is_instance_valid(rt) else true,"rebuilding":s.get("rebuilding",false),
		"fallback":s.get("fallback",""),"device_instance":_id(current),"generation":s.get("snapshot_generation",-1),
		"expected_size":[expected.x,expected.y],"output_size":[output_size.x,output_size.y],
		"guide_size":[guide_size.x,guide_size.y],"stats_size":s.get("size",[]),
		"raster_size":[raster.x,raster.y],"applied_scale":applied_scale,"expected_scale":scale,
		"history_limit":s.get("history_limit",-1),"drawn_frames":Engine.get_frames_drawn()}

func _wait_mode(mode: int,quality_value: int,scale: float,timeout_ms:=90_000) -> bool:
	var began:=Time.get_ticks_msec();var stable:=0;var state:={}
	while running and Time.get_ticks_msec()-began<timeout_ms:
		await RenderingServer.frame_post_draw
		state=_mode_snapshot(mode,quality_value,scale)
		stable=stable+1 if state.matches else 0
		if state.failed or stable>=4:break
	mode_wait={"ready":stable>=4,"wait_ms":Time.get_ticks_msec()-began,"last":state}
	return stable>=4

func _observe_hold(mode: int,quality_value: int,scale: float) -> Dictionary:
	# A topology replacement may temporarily restore raster lighting. Demand a
	# complete interval of real published output afterwards, within a wall cap.
	var began:=Time.get_ticks_usec();var previous_usec:=began
	var previous:=_mode_snapshot(mode,quality_value,scale)
	var first:=previous.duplicate(true);var last:=previous
	var required_usec:=int(phase_seconds*1000000.0)
	var deadline:=began+required_usec+RECOVERY_MS*1000
	var stable_usec:=0;var stable_frames:=0;var ready_usec:=0;var ready_frames:=0
	var fallback_usec:=0;var fallback_frames:=0;var rebuilding_frames:=0;var resets:=0
	var no_new_frame_wakeups:=0;var no_new_frame_usec:=0
	var observed_frames:=0;var boundaries:=[];var passed:=false
	var history_min:=float(previous.history_limit) if previous.matches else INF
	var history_max:=float(previous.history_limit) if previous.matches else -INF
	while running and Time.get_ticks_usec()<deadline:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		last=_mode_snapshot(mode,quality_value,scale)
		var frames:=maxi(0,int(last.drawn_frames)-int(previous.drawn_frames))
		observed_frames+=frames
		if last.matches:
			history_min=minf(history_min,float(last.history_limit));history_max=maxf(history_max,float(last.history_limit))
		var same_output: bool=last.matches and previous.matches and last.device_instance==previous.device_instance \
			and last.generation==previous.generation
		if same_output:
			if frames>0:
				# A long compile/driver stall must not count as seconds of rendering.
				var credited_usec:=mini(now-previous_usec,frames*100_000)
				stable_usec+=credited_usec;stable_frames+=frames
				ready_usec+=credited_usec;ready_frames+=frames
			else:
				# Separate rendering can emit frame_post_draw before the main
				# thread increments Engine.frames_drawn. This is not a fallback;
				# preserve the ready interval, but award no rendering time.
				no_new_frame_wakeups+=1;no_new_frame_usec+=now-previous_usec
		else:
			if stable_frames>0:resets+=1
			stable_usec=0;stable_frames=0
			fallback_usec+=now-previous_usec;fallback_frames+=frames
		if last.rebuilding:rebuilding_frames+=frames
		if (last.matches!=previous.matches or last.device_instance!=previous.device_instance or last.generation!=previous.generation) and boundaries.size()<16:
			boundaries.append({"after_seconds":float(now-began)/1000000.0,"state":last})
		passed=now<=deadline and stable_usec>=required_usec and stable_frames>=HOLD_MIN_FRAMES
		previous=last;previous_usec=now
		if passed or last.failed:break
	var elapsed:=float(Time.get_ticks_usec()-began)/1000000.0
	return {"passed":passed,"requested_seconds":phase_seconds,"elapsed_seconds":elapsed,
		"recovery_seconds":maxf(0.0,elapsed-phase_seconds),"recovery_limit_seconds":float(RECOVERY_MS)/1000.0,
		"required_rendered_frames":HOLD_MIN_FRAMES,"rendered_frames":observed_frames,
		"matching_rendered_frames":ready_frames,"matching_rendered_seconds":float(ready_usec)/1000000.0,
		"stable_rendered_frames":stable_frames,"stable_rendered_seconds":float(stable_usec)/1000000.0,
		"fallback_or_mismatch_frames":fallback_frames,"fallback_or_mismatch_seconds":float(fallback_usec)/1000000.0,
		"no_new_frame_wakeups":no_new_frame_wakeups,"no_new_frame_seconds":float(no_new_frame_usec)/1000000.0,
		"rebuilding_frames":rebuilding_frames,"recovery_resets":resets,"boundaries":boundaries,
		"ready_history_min":history_min if is_finite(history_min) else null,
		"ready_history_max":history_max if is_finite(history_max) else null,
		"start":first,"end":last}

func _wait_save_thumbnail(slot: String) -> bool:
	# SaveInfo.write_shot may wait ten process frames for the loading screen,
	# followed by frame_post_draw. Await its output, not a guessed frame count.
	var path:=SaveInfo.path(slot,"shot.png")
	var began:=Time.get_ticks_msec()
	while running and not FileAccess.file_exists(path) and Time.get_ticks_msec()-began<10_000:
		await RenderingServer.frame_post_draw
	var thumbnail:=Image.load_from_file(path) if FileAccess.file_exists(path) else null
	var ready:=thumbnail!=null and not thumbnail.is_empty() and thumbnail.get_size()==SaveInfo.SHOT_SIZE
	generated_save["thumbnail_written"]=ready
	generated_save["thumbnail_wait_ms"]=Time.get_ticks_msec()-began
	generated_save["thumbnail_size"]=[thumbnail.get_width(),thumbnail.get_height()] if thumbnail!=null else []
	check(ready,"production asynchronous save thumbnail reaches disk at the expected size before loading")
	_record("generated-thumbnail-ready",generated_save.duplicate())
	return ready

func _transition(label: String,mode: int,quality_value: int,scale_index: int,aa:=0,sdk_quality:=-1,progressive:=0) -> bool:
	if not running or not failures.is_empty():return false
	_phase(label)
	path_mode=maxi(mode,0);quality=quality_value
	GameData.options.merge({"pt_mode":path_mode,"q_rt_lighting":quality_value,
		"rt_shadows":1 if mode==0 else 0,"rt_gi":1 if mode==0 else 0,"pt_accumulation":progressive,
		"render_scale":scale_index,"q_aa":aa,"fsr_upscaling":1 if sdk_quality>=0 else 0,
		"fsr_quality":maxi(sdk_quality,0),"fsr_frame_generation":0},true)
	GameData._apply_window();game._apply_options();_enforce_resolution()
	var expected_scale: float=FsrGraphics.SCALES[sdk_quality] if sdk_quality>=0 else \
		(minf(GameData.RENDER_SCALES[scale_index],GameData.FSR2_SCALE) if aa==5 else GameData.RENDER_SCALES[scale_index])
	var ready:=await _wait_mode(mode,quality_value,expected_scale)
	check(ready,label+": requested live renderer, bounce count, quality and correctly sized published output become effective")
	_record("transition-ready",mode_wait)
	if not ready:return false
	if sdk_quality>=0 and not await _wait_sdk(label):return false
	var before:=_sdk_snapshot();var updates:=instance_update_frames
	var observed:=await _observe_hold(mode,quality_value,expected_scale)
	check(observed.passed,label+": live hold completes uninterrupted ready rendering within its bounded recovery window")
	if not observed.passed:
		transition_rows.append(_snapshot(label,{"hold":observed,"sdk_before":before,"sdk_after":_sdk_snapshot()}))
		_record("transition-hold-failed",{"transition":transition_rows.size()-1,"hold":observed})
		return false
	var history_before:=float(observed.ready_history_min)
	var after:=_sdk_snapshot()
	var history_after:=float(observed.ready_history_max)
	if aa==5 and sdk_quality<0:
		check(before.viewport_mode==Viewport.SCALING_3D_MODE_FSR2 and after.viewport_mode==Viewport.SCALING_3D_MODE_FSR2,
			label+": actual FSR2 temporal mode remains applied throughout the live hold")
	if sdk_quality>=0:
		check(_sdk_ready(before) and _sdk_ready(after),label+": SDK remains active throughout the live hold")
		check(int(after.get("upscale_evaluations",0))-int(before.get("upscale_evaluations",0))>=3,label+": live hold includes successful upscaling evaluations")
	if mode>0:
		if progressive>0:
			check(is_equal_approx(history_before,256.0) and is_equal_approx(history_after,256.0),
				label+": production still-scene history policy is active on every ready hold frame")
		else:
			check(history_before>=1.0 and history_before<=8.0 and history_after>=1.0 and history_after<=8.0,
				label+": production responsive history policy stays within eight frames")
		check(observed.end.output_ready and observed.end.output_size==observed.end.expected_size \
			and observed.end.guide_size==observed.end.expected_size and observed.end.stats_size==observed.end.expected_size,
			label+": actual published PT output and guide follow applied render scale")
	var row:=_snapshot(label,{"sdk_before":before,"sdk_after":after,"ready_history_min":history_before,
		"ready_history_max":history_after,"instance_update_frames":instance_update_frames-updates,"hold":observed})
	transition_rows.append(row);_record("transition-complete",{"transition":transition_rows.size()-1})
	return failures.is_empty()

func _memory_report() -> void:
	# Compare samples after two complete warm cycles, with the same zone/view,
	# PT settings and live state. No unavailable GPU counter is reported as 0.
	var observed:=0
	for metric: String in ["static_bytes","video_allocated_bytes","texture_bytes","buffer_bytes","objects","resources","nodes"]:
		var values:=[]
		for row: Dictionary in cycle_rows.slice(1):
			if row.memory.get(metric)!=null:values.append(float(row.memory[metric]))
		if values.size()!=cycle_rows.size()-1:
			memory_trends[metric]={"available":false,"gate":"unavailable-counter","samples":values.size()}
			print("PT_STRESS_UNAVAILABLE_COUNTER ",metric)
			continue
		observed+=1
		var first: float=values.front();var last: float=values.back()
		var floor_bytes:=256.0*1024*1024 if metric in ["video_allocated_bytes","texture_bytes","buffer_bytes"] else 128.0*1024*1024
		if metric=="objects":floor_bytes=2000
		elif metric=="resources":floor_bytes=400
		elif metric=="nodes":floor_bytes=100
		var budget:=maxf(floor_bytes,first*(0.05 if metric in ["objects","resources","nodes"] else 0.25))
		var growth:=last-first
		memory_trends[metric]={"available":true,"first":first,"last":last,"growth":growth,
			"budget":budget,"slope_per_cycle":growth/maxi(values.size()-1,1),"samples":values,"passed":growth<=budget}
		check(growth<=budget,"same-state "+metric+" growth remains within the explicit warmed-cache budget")
	# Release templates can omit MEMORY_STATIC. Require observable allocation
	# evidence, preserve every missing counter explicitly, and independently
	# require retired owners to disappear on every device transition.
	check(observed>0,"at least one same-state allocation or object-lifetime trend is observable")

func run() -> void:
	phase_seconds=3.0;timeout_seconds=1050.0;quality=0;path_mode=1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		elif arg.begins_with("--pt-stress-cycles="):cycles=clampi(arg.trim_prefix("--pt-stress-cycles=").to_int(),4,30)
		elif arg.begins_with("--pt-stress-timeout="):timeout_seconds=clampf(arg.trim_prefix("--pt-stress-timeout=").to_float(),120.0,7200.0)
		elif arg.begins_with("--pt-stress-seconds="):phase_seconds=clampf(arg.trim_prefix("--pt-stress-seconds=").to_float(),1.0,12.0)
		elif arg=="--qualification-require-sdk":require_sdk=true
	DirAccess.make_dir_recursive_absolute(out)
	started_usec=Time.get_ticks_usec();running=true
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"autosave":0,"show_tutorial":0,"vsync":0,"fps_limit":0,"scroll_border":0,
		"net_lan":0,"net_upnp":0,"net_directory":0,"control_mode":1,"gfx_water_reflections":0,
		"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,"gfx_terrain_cliffs":1,
		"rt_shadows":0,"rt_gi":0,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,
		"q_aa":0,"render_scale":4,"fsr_upscaling":0,"fsr_frame_generation":0},true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_resolution_settings();get_window().min_size=Vector2i(1,1);_enforce_resolution()
	_phase("create-session")
	session=Session.new();add_child(session)
	game=Game.new();game.session=session;session.game=game;add_child(game)
	rt=game.get_node("SceneRaytrace");session.state.ensure_hero(0,"Human Hero")
	if require_sdk:
		var facts:=FsrGraphics.facts()
		check(facts.api and facts.sr3,"explicit SDK stress requires the qualified DX12 FSR 3.1 provider")
	if failures.is_empty() and await _enter(start_zone):
		for cycle in cycles:
			if not running or not failures.is_empty():break
			var updates:=instance_update_frames
			var label:="cycle-%d-"%(cycle+1)
			if not await _transition(label+"deep-high-half",2,2,0):break
			if not await _transition(label+"short-medium-progressive",1,1,1,0,-1,1):break
			if not await _transition(label+"deep-low-temporal",2,0,4,0 if require_sdk else 5,3 if require_sdk else -1):break
			await _move()
			if not running or not failures.is_empty():break
			var settled:=await _wait_mode(path_mode,quality,get_viewport().scaling_3d_scale,RECOVERY_MS)
			check(settled,label+"PT publishes correctly sized output after ordinary hero movement")
			_record("post-movement-ready",mode_wait)
			if not settled:break
			var old:=_current_device_weak()
			if not await _transition(label+"scene-rt",0,0,4):break
			await _retired(old,label+"pt-to-scene")
			if not running or not failures.is_empty():break
			old=_current_device_weak()
			if not await _transition(label+"off",-1,0,4):break
			await _retired(old,label+"scene-to-off")
			if not await _transition(label+"restored",1,0,4,0,1 if require_sdk else -1):break
			old=_current_device_weak()
			if not await _enter(next_zone):break
			await _retired(old,label+"zone-replacement")
			if not running or not failures.is_empty():break
			await _save_reload_destination()
			save_rows.append(generated_save.duplicate(true))
			check(generated_save.get("pt_active_after_load",false),label+"generated save/load resumes live PT")
			if not running or not failures.is_empty():break
			if require_sdk and not await _wait_sdk(label+"after-load"):break
			if not await _transition(label+"return-native",1,0,4):break
			if not await _enter(start_zone):break
			var observed:=await _observe_hold(1,0,1.0)
			check(observed.passed,label+"same-state memory sample follows uninterrupted ready native Low rendering")
			_record("same-state-ready",{"hold":observed})
			if not observed.passed:break
			check(instance_update_frames-updates>2,label+"visible actors submit real instance updates")
			if not running or not failures.is_empty():break
			completed_cycles+=1
			cycle_rows.append({"cycle":cycle+1,"instance_update_frames":instance_update_frames-updates,
				"memory":_snapshot("same-state-memory"),"hold":observed,"elapsed_seconds":_elapsed()})
			_record("cycle-complete",{"cycle":cycle+1})
	check(completed_cycles==cycles,"all requested live stress cycles completed")
	check(active_zones.has(start_zone) and active_zones.has(next_zone),"both live campaign zones rendered PT")
	check(save_rows.size()==cycles,"every cycle completed its generated save/load roundtrip")
	if cycle_rows.size()>=4:_memory_report()
	else:check(false,"at least four full cycles are required for warmed allocation trends")
	_phase("before-cleanup")
	var last_device:=_current_device_weak()
	game.queue_free();session.queue_free();await _frames(16)
	if last_device!=null:await _retired(last_device,"final-game-teardown")
	running=false;TexUpscale.shutdown()
	_persist("passed" if failures.is_empty() else "failed")
	print("PT_SUSTAINED_DONE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
