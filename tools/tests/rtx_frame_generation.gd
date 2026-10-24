extends Node
## Hardware test: requires real DLSS SR and DLSS-G evaluation/presentation.
## Unsupported capability is blocked, never counted as a successful FG test.
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var scene: MenuScene
var hud: CanvasLayer

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func status() -> Dictionary:
	return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}

func save_result(blocked := false) -> void:
	var result := {"checks":checks,"failures":failures,"blocked":blocked,"rows":rows,
		"gpu":RenderingServer.get_video_adapter_name(),"facts":RtxGraphics.facts(),"status":status(),
		"fsr_status":FsrGraphics.bridge().call("get_status") if FsrGraphics.bridge() else {}}
	FileAccess.open("user://dlss-framegen.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("DLSS_FRAMEGEN ",JSON.stringify(result))

func settle(count: int) -> void:
	for i in count: await RenderingServer.frame_post_draw

func sample(label: String, enabled: bool, moving := false) -> void:
	GameData.options.rtx_frame_generation = 1 if enabled else 0
	get_tree().root.set("frame_generation",enabled)
	RtxGraphics.bridge().call("set_parameter",0,1.0 if enabled else 0.0)
	await settle(90)
	var before := status()
	var camera_start := scene.camera.transform
	var start := Time.get_ticks_usec()
	var start_utc_ms:=Time.get_unix_time_from_system()*1000.0
	for i in 180:
		if moving: scene.camera.position.x = camera_start.origin.x + sin(float(i)*0.04)*0.8
		await RenderingServer.frame_post_draw
	var elapsed_ms:=(Time.get_ticks_usec()-start)/1000.0
	var end_utc_ms:=Time.get_unix_time_from_system()*1000.0
	var after := status()
	var evaluated := int(after.get("dlss_evaluations",0))-int(before.get("dlss_evaluations",0))
	var presented := int(after.get("presented_frames",0))-int(before.get("presented_frames",0))
	var game_presents := int(after.get("game_presents",0))-int(before.get("game_presents",0))
	check(evaluated >= 175,label+": actual DLSS SR evaluations")
	check(game_presents >= 175 and game_presents <= 185,label+": one game present per rendered frame")
	check(int(after.get("last_error",-1)) == 0,label+": SDK reports no error")
	check(bool(after.get("frame_generation_active",false)) == enabled,label+": expected DLSS-G activity")
	if enabled:
		check(int(after.get("frame_generation_ui_alpha_frames",0))-int(before.get("frame_generation_ui_alpha_frames",0))>=175,label+": HUD mask captured for each rendered frame")
		check(bool(after.get("frame_generation_size_supported",false)),label+": full output mapping supported")
		check(after.get("frame_generation_output_size",Vector2i.ZERO)==get_window().size,label+": FG inputs use actual window output size")
		await inspect_alpha(label)
		check(after.get("present_count_available",false),label+": SDK presentation counter available")
		check(presented >= 330 and presented <= 390,label+": generated frames actually presented at 2x")
	var fsr: Dictionary = FsrGraphics.bridge().call("get_status") if FsrGraphics.bridge() else {}
	check(int(fsr.get("frame_generation_dispatches",0)) == 0,label+": no FSR frame-generation dispatch")
	rows.append({"label":label,"enabled":enabled,"frames":180,"dlss_evaluations":evaluated,
		"presented_frames":presented,"game_presents":game_presents,"elapsed_ms":elapsed_ms,"start_utc_ms":start_utc_ms,"end_utc_ms":end_utc_ms,"status":after})
	get_tree().root.get_texture().get_image().save_png("user://dlss-fg-"+label+".png")
	scene.camera.transform = camera_start
	save_result()

func _run() -> void:
	await settle(5)
	var f := RtxGraphics.facts()
	if not f.sr or not f.fg or not f.reflex:
		save_result(true)
		get_tree().quit(2)
		return
	get_tree().root.get_node("RtxExperiment").set_process(false)
	get_tree().root.get_node("FsrExperiment").set_process(false)
	GameData.options.merge({"rtx_upscaling":2,"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"q_aa":0,"render_scale":4,"display_mode":0,"vsync":0},true)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData._window_state.clear()
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	Engine.max_fps = 30
	Gfx.ensure_globals();Gfx.apply_surface_options();Gfx.set_foliage_wind(false)
	hud=CanvasLayer.new();hud.layer=100;add_child(hud)
	for i in 2:
		var rect:=ColorRect.new();rect.position=Vector2(32+i*160,32);rect.size=Vector2(96,96)
		rect.color=Color(0.2,0.7,0.3,1.0 if i==0 else 0.5);hud.add_child(rect)
	scene = MenuScene.create()
	check(scene != null,"real game scene created")
	if scene == null:
		save_result();get_tree().quit(1);return
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(scene);scene.set_hour(12);scene.camera.current = true
	await sample("off",false)
	await sample("on-motion",true,true)
	await sample("disabled",false,true)
	get_window().size = Vector2i(1600,900)
	await sample("resized",true,true)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=Vector2i(1920,1080)
	await sample("scaled-output",true,true)
	await sample("off-restored",false)
	hud.queue_free();scene.free();TexUpscale.shutdown();UnitWounds.shutdown()
	await settle(4)
	save_result();get_tree().quit(1 if not failures.is_empty() else 0)

func inspect_alpha(label: String) -> void:
	var texture:=Texture2DRD.new()
	texture.texture_rd_rid=status().get("frame_generation_ui_alpha_texture",RID())
	check(texture.texture_rd_rid.is_valid(),label+": readable UI alpha resource")
	if not texture.texture_rd_rid.is_valid():return
	var image:=texture.get_image()
	check(image!=null,label+": mask readback succeeds")
	if image==null:return
	# Streamline's D3D12 format resolver supports R16_FLOAT masks. R8_TYPELESS
	# allocations produce invalid SDK views on native Windows.
	check(image.get_format()==Image.FORMAT_RH,label+": Streamline-compatible floating-point HUD mask")
	check(image.get_size()==get_window().size,label+": UI mask matches actual swapchain extent")
	# These canvas rectangles are unchanged by camera motion or world shading.
	var mapping:=Vector2(image.get_size())/get_viewport().get_visible_rect().size
	var opaque:=image.get_pixelv(Vector2i(Vector2(80,80)*mapping)).r
	var half:=image.get_pixelv(Vector2i(Vector2(240,80)*mapping)).r
	var empty:=image.get_pixelv(Vector2i(Vector2(400,80)*mapping)).r
	check(opaque>0.98,label+": opaque HUD has full mask coverage")
	check(absf(half-0.5)<0.03,label+": translucent HUD retains its real opacity")
	check(empty<0.02,label+": scene outside HUD has zero mask coverage")
	image.save_png("user://dlss-fg-"+label+"-alpha.png")
	texture.texture_rd_rid=RID()
