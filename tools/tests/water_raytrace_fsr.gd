extends "res://tools/tests/water_raytrace_artifact.gd"
## Real river RT and production FSR autoload, with presentation telemetry and HUD.
var fg_rows := []

func status() -> Dictionary:
	return FsrGraphics.bridge().call("get_status")

func sample(label: String, expect_fg: bool, expect_rt: bool) -> void:
	# A rebuilt engine with an empty shader cache can still be compiling the
	# temporal variants at 90 seconds. Keep a finite cold-start allowance;
	# functional assertions below still require actual generated presents.
	var deadline := Time.get_ticks_msec()+180_000
	while Time.get_ticks_msec() < deadline:
		get_tree().root.grab_focus()
		await frames(1)
		if bool(status().frame_generation_active) == expect_fg and (not expect_rt or t._reflection.rt_stats.get("active",false)): break
	await frames(35)
	var before := status()
	for i in 90:
		get_tree().root.grab_focus()
		await RenderingServer.frame_post_draw
	var after := status()
	var generated := int(after.generated_frames)-int(before.generated_frames)
	var presented := int(after.presented_frames)-int(before.presented_frames)
	check(after.frame_generation_active == expect_fg,label+": normal FG gate")
	check(generated >= 80 if expect_fg else generated == 0,label+": measured generated-frame count")
	check(presented >= 160 and presented <= 195 if expect_fg else presented >= 80 and presented <= 105,label+": measured presentation count")
	check(int(after.last_error) == 0,label+": FSR SDK reports no error")
	check(t._reflection.rt_stats.get("active",false) == expect_rt,label+": expected reflection backend is active")
	if expect_rt:
		check(t._reflection.rt_stats.get("samples_per_pixel",0) == 4,label+": four-sample RT is actually running")
	var fps := GameData._fps_layer.get_child(0) as Label
	var meter_deadline := Time.get_ticks_msec()+2000
	while expect_fg and fps.get("rates").get("presented_fps",-1.0) < 0 and Time.get_ticks_msec() < meter_deadline:
		get_tree().root.grab_focus()
		await frames(1)
	check(fps.visible and ("\n" in fps.text) == expect_fg,label+": FPS overlay includes the measured FG line only when active")
	if expect_fg: check(fps.get("rates").get("presented_fps",-1.0) > 0,label+": presented FPS settles to a measured number")
	fg_rows.append({"case":label,"generated":generated,"presented":presented,"status":after,"rt":t._reflection.rt_stats.duplicate(),"fps_text":fps.text})
	await shot(label)

func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var facts := FsrGraphics.facts()
	check(facts.fg3,"this DX12 build exposes FSR frame generation")
	if not facts.fg3: get_tree().quit(1); return
	var context := await setup()
	# Use the campaign's real camera: the production FG gate deliberately
	# rejects a free-standing capture camera outside the gameplay rig.
	var capture_camera := camera
	camera = context[1].rig.camera
	camera.fov = capture_camera.fov
	camera.global_transform = capture_camera.global_transform
	camera.current = true
	capture_camera.queue_free()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,false)
	context[1].hud.process_mode = Node.PROCESS_MODE_INHERIT
	context[1].hud.show(); context[1].hud._dialog.hide()
	check(FsrGraphics.campaign_gate(get_tree(),camera).allowed,"production campaign camera permits frame generation")
	get_tree().root.grab_focus()
	GameData.options.merge({"fsr_upscaling":1,"fsr_quality":1,"fsr_frame_generation":1,"gfx_water_reflections":3},true)
	GameData._apply_window(); t.apply_gfx()
	get_tree().root.borderless = true; get_tree().root.size = Vector2i(1280,720)
	await sample("rt-and-fg",true,true)
	GameData.options.fsr_frame_generation=0
	await sample("rt-native-frames",false,true)
	GameData.options.fsr_frame_generation=1
	GameData.options.gfx_water_reflections=2; t.apply_gfx()
	await sample("mirror-and-fg",true,false)
	GameData.options.gfx_water_reflections=3; t.apply_gfx()
	await sample("rt-restored-with-fg",true,true)
	get_tree().root.size=Vector2i(960,540)
	await sample("rt-and-fg-resized",true,true)
	get_tree().paused=true
	await sample("rt-paused",false,true)
	get_tree().paused=false
	await sample("rt-and-fg-resumed",true,true)
	FileAccess.open(out.path_join("rt-fsr.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":fg_rows},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
