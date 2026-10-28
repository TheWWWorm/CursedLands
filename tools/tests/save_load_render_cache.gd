extends Node
## Production save/worker reloads must reuse immutable GPU work without
## retaining the previous world, materials, scene buffers or denoising history.
var checks := 0
var failures := []
var session: Session
var game: Game
var rows := []
var path_mode := 1

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func frames(count := 8) -> void:
	for i in count:await get_tree().process_frame

func settle() -> bool:
	var deadline:=Time.get_ticks_msec()+180000
	var stable:=0
	while Time.get_ticks_msec()<deadline and stable<5:
		await frames(1)
		var rt:Node=game.get_node("SceneRaytrace")
		var done:=not session.loading_game and not session._remote_loading \
			and not is_instance_valid(LoadingScreen._current) and not ShaderCompilationScreen.active()
		done=done and (path_mode==0 or (rt.stats.get("active",false) and not rt.stats.get("rebuilding",false)))
		stable=stable+1 if done else 0
	return stable>=5

func pages() -> Dictionary:
	var result:={}
	var cache:=game.world.terrain.color_cache
	if not is_instance_valid(cache):return result
	cache.prepare(game.rig.camera)
	for key:Vector2i in cache._resident:
		var material:ShaderMaterial=cache._resident[key].material
		result[key]={"texture":material.get_shader_parameter("baked_ground"),"material":material}
	return result

func programs(rt: Node) -> Dictionary:
	var result:={}
	if rt.device==null:return result
	result["trace"]=[rt.device._shader,rt.device._pipeline]
	for key:String in rt.device.nrd._programs:
		var pair:Dictionary=rt.device.nrd._programs[key]
		result[key]=[pair.shader,pair.pipeline]
	return result

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	if OS.get_cmdline_user_args().has("--cache-raster"):path_mode=0
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	GameData.options.merge({"pt_mode":path_mode,"pt_accumulation":0,"q_rt_lighting":0,"pt_sharc":0,"pt_restir":0,
		"pt_refraction":0,"pt_ray_reconstruction":0,"rt_shadows":0,"rt_gi":0,"gfx_water_reflections":2,
		"autosave":0,"auto_graphics":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"display_mode":0,"vsync":0,"fps_limit":0,"rtx_upscaling":0,"rtx_frame_generation":0,
		"fsr_upscaling":0,"fsr_frame_generation":0,"scroll_border":0,"pad_enabled":0},true)
	GameData._apply_window();Gfx.apply_quality(get_viewport());Engine.max_fps=30
	get_window().size=Vector2i(1280,720)
	await frames(3)
	TutorialPanel.auto_show=false
	session=Session.new();get_parent().add_child(session)
	game=Game.new();game.session=session;session.game=game;get_parent().add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	session._enter_zone("gz3g",1,false)
	check(await settle(),"initial world and lighting finish before reveal")
	check(session.save_game("render-cache-reload")==OK,"save created through the production serializer")
	var rt:Node=game.get_node("SceneRaytrace")
	for reload in 2:
		var old_terrain: WeakRef = weakref(game.world.terrain)
		var before:=pages()
		var immutable:=programs(rt)
		var old_device:RefCounted=rt.device
		var old_nrd:RefCounted=rt.device.nrd if rt.device!=null else null
		check(not before.is_empty(),"real visible terrain pages are baked")
		if path_mode>0:check(immutable.size()>1 and old_device.nrd_active,"actual ray tracing and NRD programs execute")
		var start:=Time.get_ticks_msec()
		check(await session.load_game_shown("render-cache-reload"),"normal save load succeeds")
		check(await settle(),"replacement world and lighting complete before reveal")
		rows.append({"reload":reload,"ms":Time.get_ticks_msec()-start,"pt":path_mode})
		check(game.world.terrain._cliffs != null and game.world.terrain._cliffs.get("reused") == true,
			"normal worker reload reuses derived cliff geometry")
		var after:=pages()
		var common:=0;var reused:=0;var private_materials:=true
		for key:Vector2i in before:
			if not after.has(key):continue
			common+=1
			if before[key].texture==after[key].texture:reused+=1
			private_materials=private_materials and before[key].material!=after[key].material
		check(common>0 and reused==common,"reload reuses every overlapping immutable terrain texture")
		check(private_materials,"reused colour pages have new world-owned materials")
		check(old_terrain.get_ref()==null,"reload releases the previous terrain node")
		check(game.world.terrain.color_cache.built==0,"identical visible terrain requires no new native bake")
		if path_mode>0:
			var after_programs:=programs(rt)
			var same:=immutable.size()==after_programs.size()
			for key:String in immutable:same=same and after_programs.get(key,[])==immutable[key]
			check(same,"reload reuses trace and NRD shaders and pipelines")
			check(rt.device!=old_device and rt.device.nrd!=old_nrd,"scene buffers and temporal denoiser are rebuilt")
			check(old_device._closed and old_nrd._textures.is_empty(),"previous scene and NRD history are released")
	if path_mode>0:
		var cache:RefCounted=rt._programs
		GameData.options.pt_mode=0;await frames(12)
		check(rt.device==null and cache._owned.is_empty(),"disabling path tracing releases its shared programs")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://save-load-cache.png")
	FileAccess.open("user://save-load-cache.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"loads":rows},"\t"))
	await session.local_host.stop()
	game.queue_free();session.queue_free();await frames()
	TexUpscale.shutdown()
	print("SAVE_LOAD_RENDER_CACHE ",checks," checks ",failures.size()," failures")
	get_tree().quit(int(not failures.is_empty()))
