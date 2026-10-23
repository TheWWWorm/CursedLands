extends Node
## Rendered UI contract only. Progress values below are deliberate test inputs,
## not observations of completed shader compilation or SDK readiness.
## Run through --tool with an isolated muted, free-cursor development profile.

class CameraShell extends Game:
	func _ready() -> void:
		# Keep the real CameraRig/input guard without a world, HUD, simulation,
		# warm-up, render effects or a multiplayer worker.
		simulation_only = true
		add_to_group("fsr_campaign_view")
		rig = CameraRig.new()
		add_child(rig)
		rig.set_process(false)
		rig.camera.current = true
		set_process(false)
		set_process_unhandled_input(false)
	func _exit_tree() -> void: pass

class DirectCameraProbe extends DirectControl:
	var camera_calls := 0
	func active() -> bool: return true
	func apply_camera(_dt: float = 0.0) -> void:
		camera_calls+=1
		game.rig.camera.position.x+=1.0

const Screen = preload("res://src/ui/shader_compilation_screen.gd")
const PHASES := [Screen.SCENE, Screen.MATERIALS, Screen.GRAPHICS, Screen.TEMPORAL,
	Screen.UPSCALER, Screen.FRAMES, Screen.FINISHING, Screen.GEOMETRY, Screen.RAYTRACE,
	Screen.PATH_TRACE, Screen.WATER, Screen.FIRST_FRAME, Screen.TERRAIN]
var out := "user://shader-compilation-screen"
var checks := 0
var failures: Array[String] = []
var progress: Array[Dictionary] = []
var layouts: Array[Dictionary] = []
var lifecycle: Array[Dictionary] = []
var contracts: Array[Dictionary] = []
var pad_events: Array[Dictionary] = []
var saved_input := {}
var saved_sdk := {}
var started_ms := 0
var running := false
var game: CameraShell
var session: Session
var old_language := "en"
var old_progress := Callable()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func _write(status: String) -> void:
	var file := FileAccess.open(out.path_join("shader-compilation-screen.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"status":status,"checks":checks,"failures":failures,
		"elapsed_seconds":float(Time.get_ticks_msec()-started_ms)/1000.0,
		"driver":RenderingServer.get_current_rendering_driver_name(),"display":DisplayServer.get_name(),
		"user_data":OS.get_user_data_dir(),"layouts":layouts,"progress":progress,"lifecycle":lifecycle,"contracts":contracts,
		"profile":{"confine_mouse":GameData.option("confine_mouse"),"show_fps":GameData.option("show_fps"),
			"volume_sfx":GameData.option("volume_sfx"),"volume_stream":GameData.option("volume_stream"),"volume_voice":GameData.option("volume_voice")},
		"note":"Deterministic screen API/ownership/input tests with simulated progress counts. Captures use the real canvas and camera input guard. This fixture does not validate actual shader or SDK compilation completion."}, "\t"))
	file.flush();file.close()

func _process(_dt: float) -> void:
	if running and Time.get_ticks_msec()-started_ms>120_000:
		check(false,"screen fixture finishes inside its wall-time limit")
		_write("timeout");running=false;get_tree().quit(1)

func _frames(count := 3) -> void:
	for i in count: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _observe(row: Dictionary) -> void:
	if progress.size()<1000:
		var sample := row.duplicate(true)
		sample["language"]=RemakeText.lang
		sample["input_kind"]="simulated-ui-progress"
		progress.append(sample)

func _state(label: String) -> void:
	var screen := Screen._current
	lifecycle.append({"case":label,"active":Screen.active(),"paused":get_tree().paused,
		"owns_pause":Screen.owns_pause(get_tree()),"screen_instance":screen.get_instance_id() if is_instance_valid(screen) else 0,
		"presentations":screen._presentations if is_instance_valid(screen) else 0,
		"owners":screen._owners.keys() if is_instance_valid(screen) else [],
		"drawn_frames":Engine.get_frames_drawn()})
	_write("running")

func _wheel() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_WHEEL_UP;event.pressed=true;event.position=Vector2(80,80)
	return event

func _pad_action(action: String, phase: String) -> void:
	if action=="shader_fixture_hold":pad_events.append({"action":action,"phase":phase})

func _seed_cached_input() -> void:
	# Seed the same caches as a held physical action without emitting a click
	# or triggering a gameplay command in this UI-only test.
	for key: String in ["_down","_held","_route","_repeat","_axes","_trig","_last_tap","_double","_back_pending_ms"]:
		var value: Variant=PadInput.get(key)
		saved_input["pad:"+key]=value.duplicate(true) if value is Dictionary else value
	for key: String in ["fingers","_primary","_panning","_dragging","_cancelled","_tap_time"]:
		var value: Variant=TouchInput.get(key)
		saved_input["touch:"+key]=value.duplicate(true) if value is Dictionary else value
	PadInput.action.connect(_pad_action)
	PadInput._down["shader_fixture_hold"]=Time.get_ticks_msec()
	PadInput._held["shader_fixture_hold"]=false
	PadInput._route["shader_fixture_hold"]="field"
	PadInput._repeat["shader_fixture_hold"]=0.4
	PadInput._axes[JOY_AXIS_RIGHT_X]=0.75;PadInput._trig["RT"]=true
	PadInput._back_pending_ms=Time.get_ticks_msec()
	TouchInput.fingers={41:Vector2(12,34)};TouchInput._primary=41
	TouchInput._panning=true;TouchInput._dragging=false;TouchInput._cancelled=false
	TouchInput._tap_time=Time.get_ticks_msec()

func _check_cancelled_input() -> void:
	check(PadInput._down.is_empty() and PadInput._held.is_empty() and PadInput._route.is_empty() \
		and PadInput._repeat.is_empty() and PadInput._axes.is_empty() and PadInput._trig.is_empty() \
		and PadInput._back_pending_ms==-1,"begin cancels cached controller actions, axes, triggers and delayed Back")
	check(pad_events.size()==1 and pad_events[0].phase=="up","cancelled quick controller press emits release without a synthetic tap")
	check(TouchInput.fingers.is_empty() and TouchInput._primary==-1 and not TouchInput._panning \
		and not TouchInput._dragging and TouchInput._cancelled and TouchInput._tap_time==-1000,
		"begin cancels the pending touch gesture and double-tap history")
	contracts.append({"case":"cached-input-cancellation","input_kind":"simulated-ui-contract","events":pad_events.duplicate(true)})
	_restore_input()

func _restore_input() -> void:
	if PadInput.action.is_connected(_pad_action):PadInput.action.disconnect(_pad_action)
	for key: String in saved_input:
		if key.begins_with("pad:"):PadInput.set(key.trim_prefix("pad:"),saved_input[key])
		else:TouchInput.set(key.trim_prefix("touch:"),saved_input[key])
	saved_input.clear()

func _camera_process_guards() -> void:
	var rig := game.rig
	var before := rig.camera.transform
	var yaw := rig.yaw;var distance := rig.distance
	rig.pad_turn=1.0;rig.pad_zoom=1.0;rig._yaw_v=1.0;rig._zoom_v=1.0
	rig._drag_button=MOUSE_BUTTON_RIGHT;rig.edge=Vector2i.ONE
	for i in 12:rig._process(1.0/60.0)
	check(rig.camera.transform.is_equal_approx(before) and is_equal_approx(rig.yaw,yaw) \
		and is_equal_approx(rig.distance,distance) and rig._yaw_v==0 and rig._zoom_v==0 \
		and rig._drag_button==0 and rig.edge==Vector2i.ZERO,
		"RTS camera processing stops motion and clears cached inertia during the cover")
	rig.pad_turn=0;rig.pad_zoom=0
	var direct := DirectControl.new()
	var field := PadField.new()
	check(not direct.usable() and not field.takes_input(),"direct and pad input reject the cover before accessing game state")
	direct.free();field.free()
	var probe := DirectCameraProbe.new();probe.game=game;game.direct=probe
	for i in 12:rig._process(1.0/60.0)
	check(probe.camera_calls==0 and rig.camera.transform.is_equal_approx(before),
		"CameraRig blocks direct-camera delegation while shader preparation is active")
	game.direct=null;probe.free()

func _restore_sdk() -> void:
	if saved_sdk.is_empty():return
	Screen.end(&"fsr")
	FsrExperiment._preparation_key=saved_sdk.key
	FsrExperiment._preparation_pending=saved_sdk.pending
	FsrExperiment._preparation_started_ms=saved_sdk.started_ms
	FsrExperiment._preparation_sr_base=saved_sdk.sr_base
	FsrExperiment._preparation_fg_base=saved_sdk.fg_base
	GameData.options.merge(saved_sdk.options,true)
	FsrExperiment.set_process(saved_sdk.processing)
	saved_sdk.clear()

func _sdk_preparation_contract() -> void:
	# Invoke the real state machine with explicit synthetic SDK observations.
	# Never change the native bridge or claim these counts are real evaluations.
	saved_sdk={"key":FsrExperiment._preparation_key.duplicate(true),"pending":FsrExperiment._preparation_pending,
		"started_ms":FsrExperiment._preparation_started_ms,
		"sr_base":FsrExperiment._preparation_sr_base,"fg_base":FsrExperiment._preparation_fg_base,
		"processing":FsrExperiment.is_processing(),"options":{"fsr_upscaling":GameData.option("fsr_upscaling"),
			"fsr_quality":GameData.option("fsr_quality"),"fsr_frame_generation":GameData.option("fsr_frame_generation")}}
	FsrExperiment.set_process(false)
	FsrExperiment._preparation_key=[];FsrExperiment._preparation_pending=false
	GameData.options.merge({"fsr_upscaling":1,"fsr_quality":1,"fsr_frame_generation":0},true)
	var stale := {"temporal_shaders_initializing":false,"upscaler_initializing":false,
		"frame_generation_initializing":false,"upscale_evaluations":10,"frame_generation_dispatches":4,"last_error":37}
	FsrExperiment._update_preparation(stale,true,false)
	check(FsrExperiment._preparation_pending and not Screen.active(),
		"a fresh SR request waits quietly before showing a modal cover")
	await get_tree().create_timer(0.6, true, false, true).timeout
	FsrExperiment._update_preparation(stale,true,false)
	check(FsrExperiment._preparation_pending and Screen.active() and Screen._current._owners.has(&"fsr"),
		"a slow SR request shows progress despite an unrelated sticky error")
	await _frames(12)
	FsrExperiment._update_preparation(stale,true,false)
	check(FsrExperiment._preparation_pending and Screen.active() and Screen._current._owners.has(&"fsr"),
		"unchanged simulated evaluations retain the SR cover after initializing flags are clear")
	var ready := stale.duplicate();ready.upscale_evaluations=11
	FsrExperiment._update_preparation(ready,true,false)
	check(not FsrExperiment._preparation_pending and Screen.active() and not Screen._current._owners.has(&"fsr"),
		"a fresh simulated SR evaluation releases its owner despite an unrelated sticky error")
	contracts.append({"case":"sdk-sticky-error","input_kind":"simulated-ui-contract","pending_status":stale,
		"ready_status":ready,"native_bridge_called":false})
	await _wait_removed("simulated-sdk-complete")
	# Ordinary UI gates and replacement cameras do not mean new shader work.
	GameData.options.fsr_frame_generation=1
	FsrExperiment._update_preparation(ready,true,true)
	var warm := ready.duplicate();warm.upscale_evaluations=12;warm.frame_generation_dispatches=5
	FsrExperiment._update_preparation(warm,true,true)
	check(not Screen.active(),"cached FSR activation finishing immediately never shows progress")
	var progress_before := progress.size()
	for i in 3:
		FsrExperiment._update_preparation(warm,true,false)
		check(not Screen.active(),"opening a tutorial/menu or pausing does not create a shader cover")
		warm.upscale_evaluations+=1
		FsrExperiment._update_preparation(warm,true,true)
		check(not Screen.active(),"closing a tutorial/menu or resuming does not create a shader cover")
		warm.frame_generation_dispatches+=1
	var replacement := Camera3D.new();add_child(replacement);replacement.current=true
	FsrExperiment._update_preparation(warm,true,true)
	check(not Screen.active(),"a replacement load/menu camera alone does not create a shader cover")
	replacement.queue_free();game.rig.camera.current=true
	await _frames(3)
	check(progress.size()==progress_before and not get_tree().paused,
		"warm UI transitions produce no progress presentation or stolen pause")
	var preparing := warm.duplicate();preparing.temporal_shaders_initializing=true
	FsrExperiment._update_preparation(preparing,true,true)
	check(not Screen.active(),"brief SDK preparation also starts quietly")
	await get_tree().create_timer(0.6, true, false, true).timeout
	FsrExperiment._update_preparation(preparing,true,true)
	check(Screen.active() and Screen._current._owners.has(&"fsr"),
		"prolonged SDK initialization status still shows progress with unchanged settings")
	warm.upscale_evaluations+=1;warm.frame_generation_dispatches+=1
	FsrExperiment._update_preparation(warm,true,true)
	await _wait_removed("sdk-reinitialization-complete")
	GameData.options.fsr_upscaling=0
	FsrExperiment._update_preparation(warm,false,true)
	warm.frame_generation_dispatches+=1
	FsrExperiment._update_preparation(warm,false,true)
	FsrExperiment._update_preparation(warm,false,false)
	FsrExperiment._update_preparation(warm,false,true)
	check(not Screen.active(),"standalone frame generation resumes silently after a UI gate")
	_restore_sdk()

func _exit_tree() -> void:
	_restore_input();_restore_sdk()
	if started_ms>0:Screen.on_progress=old_progress;RemakeText.lang=old_language

func _wait_removed(label: String) -> bool:
	var began := Time.get_ticks_msec()
	var presentations := Screen._current._presentations if Screen.active() else 0
	while Screen.active() and Time.get_ticks_msec()-began<5000:
		await _frames(1)
	check(not Screen.active(),label+": final owner releases the cover after presented frames settle")
	lifecycle.append({"case":label,"wait_ms":Time.get_ticks_msec()-began,
		"starting_presentations":presentations,"removed":not Screen.active()})
	return not Screen.active()

func _translations() -> void:
	for key: String in [Screen.TITLE,Screen.SETTINGS_TITLE,Screen.SCENE_TITLE,Screen.FIRST_USE,Screen.COUNT,Screen.ELAPSED]+PHASES:
		var translations: Array=RemakeText.TEXTS.get(key,[])
		check(translations.size()==2,"EN/RU/DE catalogue includes "+key)
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			var value := RemakeText.t(key)
			check(not value.strip_edges().is_empty() and (language=="en" or value!=key),language+": localized screen text "+key)
			if key==Screen.COUNT:
				check((value%[7,24]).contains("7") and (value%[7,24]).contains("24"),language+": material-count placeholders format")
			elif key==Screen.ELAPSED:
				check((value%"1:23").contains("1:23"),language+": elapsed-time placeholder formats")

func _layout(screen: ShaderCompilationScreen, label: String) -> Dictionary:
	var viewport := Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size)
	var texts := [RemakeText.t(screen._title),RemakeText.t(screen._phase),
		RemakeText.t(Screen.COUNT)%[screen._completed,screen._total] if screen._total>0 else RemakeText.t(Screen.FIRST_USE),
		RemakeText.t(Screen.ELAPSED)%"0:00"]
	var fonts: Array[Font]=[Screen.HEADING,Screen.BODY,Screen.BODY,Screen.BODY]
	var sizes := [32,20,18,16]
	var rects := [];var fits := screen._text_rects.size()==4;var glyphs := true;var previous_bottom := 0.0
	for i in mini(screen._text_rects.size(),texts.size()):
		var rect: Rect2=screen._text_rects[i]
		var measured := fonts[i].get_multiline_string_size(texts[i],HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,sizes[i])
		fits= fits and viewport.encloses(rect) and rect.size.x>0 and rect.size.y>0 \
			and measured.x<=rect.size.x+1.0 and measured.y<=rect.size.y+1.0 and rect.position.y>=previous_bottom
		previous_bottom=rect.end.y
		for character in texts[i].length():
			if texts[i].unicode_at(character)>32 and not fonts[i].has_char(texts[i].unicode_at(character)):glyphs=false
		rects.append({"text":texts[i],"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],
			"measured":[measured.x,measured.y]})
	check(fits,label+": all rendered text fits the viewport without overlap or clipping")
	check(glyphs,label+": fonts contain every localized glyph")
	return {"case":label,"language":RemakeText.lang,"phase":screen._phase,"completed":screen._completed,
		"total":screen._total,"viewport":[viewport.size.x,viewport.size.y],"fits":fits,"glyphs":glyphs,"text":rects}

func _capture(label: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image!=null and not image.is_empty(),label+": actual presented canvas is readable")
	if image==null or image.is_empty():return {}
	var opaque := true;var samples := []
	for position: Vector2i in [Vector2i(8,8),Vector2i(image.get_width()-9,8),
		Vector2i(8,image.get_height()-9),Vector2i(image.get_width()-9,image.get_height()-9),
		Vector2i(8,image.get_height()/2),Vector2i(image.get_width()-9,image.get_height()/2),
		Vector2i(image.get_width()/2,8),Vector2i(image.get_width()/2,image.get_height()-9)]:
		var pixel := image.get_pixelv(position)
		opaque=opaque and pixel.a>0.99 and absf(pixel.r-Screen.BACKGROUND.r)<0.08 \
			and absf(pixel.g-Screen.BACKGROUND.g)<0.08 and absf(pixel.b-Screen.BACKGROUND.b)<0.08
		samples.append([position.x,position.y,pixel.r,pixel.g,pixel.b,pixel.a])
	check(opaque,label+": opaque cover hides the red underlying view at every screen edge")
	var path := out.path_join(label+".png")
	check(image.save_png(path)==OK,label+": screenshot is saved")
	return {"path":path,"size":[image.get_width(),image.get_height()],"opaque":opaque,"edge_pixels":samples}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	started_ms=Time.get_ticks_msec();running=true
	old_language=RemakeText.lang;old_progress=Screen.on_progress
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"camera_style":0,"scroll_border":0,"power_mouse":50},true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	check(DisplayServer.get_name()!="headless","rendered screen qualification requires an actual display")
	if DisplayServer.get_name()=="headless":_write("failed");running=false;get_tree().quit(1);return
	await _frames(4)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED;get_window().borderless=true;get_window().min_size=Vector2i.ONE
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size=Vector2i.ZERO;get_window().content_scale_factor=1.0
	get_window().size=Vector2i(1280,720)
	var underlay := CanvasLayer.new();underlay.layer=1090;add_child(underlay)
	var red := ColorRect.new();red.color=Color.RED;red.mouse_filter=Control.MOUSE_FILTER_IGNORE
	red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);underlay.add_child(red)
	session=Session.new() # Data shell only: intentionally never starts a game/worker.
	game=CameraShell.new();game.session=session;session.game=game;add_child(game)
	await _frames(3)
	game.rig._window_focused=true
	var distance := game.rig.distance
	game.rig._unhandled_input(_wheel())
	check(not is_equal_approx(game.rig.distance,distance),"real camera wheel handler responds before the cover")
	game.rig.distance=distance
	var direct_probe := DirectCameraProbe.new();direct_probe.game=game;game.direct=direct_probe
	var camera_before := game.rig.camera.transform
	game.rig._process(1.0/60.0)
	check(direct_probe.camera_calls==1,"direct-camera probe responds to CameraRig processing before the cover")
	game.rig.camera.transform=camera_before;game.direct=null;direct_probe.free()
	_translations();RemakeText.lang="en"
	Screen.on_progress=_observe
	# Every producer shares the same quiet window, including without FSR.
	for kind in ["materials:brief", "pipeline:scene:brief", "pipeline:water:brief", "settings:brief"]:
		var short_screen := Screen.begin(get_tree(),StringName(kind),Screen.SCENE)
		short_screen.present()
		check(Screen.active() and not Screen.displayed(),kind+": readiness is gated without a visible flash")
		Screen.end(StringName(kind))
		await _wait_removed(kind)
		check(not short_screen._shown if is_instance_valid(short_screen) else true,kind+": completed cached work stays quiet")
	var owner: StringName=&"materials:fixture-primary"
	_seed_cached_input()
	var screen := Screen.begin(get_tree(),owner,Screen.MATERIALS,0,24)
	check(screen!=null,"first owner creates the real compilation canvas")
	if screen==null:_write("failed");running=false;get_tree().quit(1);return
	_check_cancelled_input()
	_camera_process_guards()
	screen.present();await get_tree().create_timer(0.6,true,false,true).timeout;await _frames(4)
	check(Screen.owns_pause(get_tree()) and get_tree().paused,"visible single-player camera owns a temporary compilation pause")
	game.rig._window_focused=true;distance=game.rig.distance
	game.rig._unhandled_input(_wheel())
	check(game.rig._input_blocked() and is_equal_approx(game.rig.distance,distance),"production camera guard blocks wheel motion while the cover is active")
	get_viewport().push_input(_wheel(),true)
	check(get_viewport().is_input_handled(),"compilation canvas consumes viewport input")
	await _frames(12)
	check(Screen.active() and screen._completed==0 and screen._total==24,"draws alone cannot advance simulated material completion or dismiss an active owner")
	Screen.update(owner,Screen.MATERIALS,7,24);screen.present()
	check(screen._completed==7 and screen._total==24 and progress.back().completed==7,"explicit material completion input appears in the real canvas progress callback")
	await _frames(8)
	check(screen._completed==7,"elapsed time does not invent additional material completion")
	_state("held-progress")
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language
		for size: Vector2i in [Vector2i(1280,720),Vector2i(640,480)]:
			get_window().size=size;await _frames(3)
			check(Vector2i(get_viewport().get_visible_rect().size)==size,language+": actual viewport size is "+str(size))
			for phase: String in PHASES:
				var counted := phase==Screen.MATERIALS
				var title := Screen.SETTINGS_TITLE if phase==Screen.GRAPHICS else Screen.SCENE_TITLE if phase==Screen.GEOMETRY else Screen.TITLE
				Screen.begin(get_tree(),owner,phase,0,0,title)
				Screen.update(owner,phase,124 if counted else 0,240 if counted else 0)
				screen.present();await _frames(1)
				var label := "%s-%dx%d-%s"%[language,size.x,size.y,"materials" if counted else str(PHASES.find(phase))]
				var row := _layout(screen,label)
				if counted or phase in [Screen.TEMPORAL,Screen.GRAPHICS,Screen.GEOMETRY]:row["capture"]=await _capture(label)
				layouts.append(row);_write("running")
	RemakeText.lang="en"
	Screen.update(owner,Screen.MATERIALS,24,24);await _frames(12)
	check(Screen.active(),"even a complete material count cannot remove a still-active owner")
	Screen.begin(get_tree(),&"settings",Screen.GRAPHICS)
	var second := Screen.begin(get_tree(),&"materials:fixture-secondary",Screen.MATERIALS,1,3)
	check(second==screen and screen._completed==1 and screen._total==3,"newest unique material owner shares the cover and supplies its progress")
	Screen.end(owner);await _frames(10)
	check(Screen.active() and screen._completed==1 and screen._total==3,"ending an older material owner preserves the replacement batch")
	Screen.update(owner,Screen.MATERIALS,24,24);Screen.end(owner)
	check(screen._completed==1 and screen._total==3,"stale updates and duplicate completion cannot overwrite a replacement owner")
	Screen.end(&"materials:fixture-secondary")
	check(Screen.active() and screen._phase==Screen.GRAPHICS and screen._total==0,"settings owner remains visible with indeterminate progress after materials finish")
	_state("settings-retained")
	Screen.end(&"settings")
	check(Screen.active(),"last completion queues removal rather than exposing the scene synchronously")
	Screen.begin(get_tree(),&"materials:fixture-replacement",Screen.MATERIALS,0,2)
	await _frames(12)
	check(Screen.active() and Screen._current==screen,"new hold survives older queued completion and stable frames")
	Screen.end(&"materials:fixture-replacement")
	await _wait_removed("owned-pause-complete")
	check(not get_tree().paused and not Screen.owns_pause(get_tree()),"completion restores the unpaused player state it acquired")
	await _frames(2)
	var exposed := get_viewport().get_texture().get_image()
	check(exposed.get_pixel(8,8).r>0.9 and exposed.get_pixel(8,8).g<0.1,"completed cover releases the actual red underlying view")
	game.rig._window_focused=true;distance=game.rig.distance;game.rig._unhandled_input(_wheel())
	check(not game.rig._input_blocked() and not is_equal_approx(game.rig.distance,distance),"camera input resumes after completion")
	# Exercise delayed destruction of an old canvas without simulating shader
	# completion: explicit retirement is solely a UI replacement stress input.
	var previous := Screen.begin(get_tree(),&"materials:fixture-retired",Screen.MATERIALS,0,1)
	previous._remove()
	var replacement := Screen.begin(get_tree(),&"materials:fixture-new",Screen.MATERIALS,0,2)
	get_window().size+=Vector2i(1,0);await _frames(12)
	check(Screen.active() and Screen._current==replacement,"queued deletion and resize of an older canvas cannot clear a newer screen")
	Screen.end(&"materials:fixture-new");await _wait_removed("replacement-complete")
	get_tree().paused=true
	screen=Screen.begin(get_tree(),&"materials:fixture-player-pause",Screen.MATERIALS,0,1)
	await _frames(8)
	check(get_tree().paused and not Screen.owns_pause(get_tree()),"pre-existing player pause is never claimed by the screen")
	Screen.end(&"materials:fixture-player-pause");await _wait_removed("player-pause-complete")
	check(get_tree().paused,"completion preserves the player's pre-existing pause")
	_state("player-pause-preserved")
	get_tree().paused=false
	session.online=true
	Screen.begin(get_tree(),&"materials:fixture-multiplayer",Screen.MATERIALS,0,1)
	await _frames(8)
	check(session.multiplayer_game and not get_tree().paused and not Screen.owns_pause(get_tree()),
		"multiplayer compilation cover never acquires a global simulation pause")
	Screen.end(&"materials:fixture-multiplayer");await _wait_removed("multiplayer-complete")
	session.online=false
	await _sdk_preparation_contract()
	Screen.on_progress=old_progress;RemakeText.lang=old_language
	game.queue_free();session.free();underlay.queue_free();await _frames(3)
	running=false;_write("passed" if failures.is_empty() else "failed")
	print("SHADER_COMPILATION_SCREEN ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
