extends "../repo/tools/benchmarks/coop_traversal_session.gd"
var cache_rows := []

func cache_sample(label: String) -> void:
	await frames_wait(30)
	var row := {"label":label,"ticks":Time.get_ticks_msec(),"pid":OS.get_process_id(),
		"video":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"texture":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"models":EIFigure._models.size(),"meshes":EIFigure._meshes.size(),
		"animations":EIAnim._libraries.size(),"unit_textures":EIUnitModel._textures.size(),
		"textures":GameData._texture_cache.size(),"hd":Gfx._hd.size()}
	cache_rows.append(row)
	print("CACHE_RELEASE ",JSON.stringify(row))
	FileAccess.open("user://cache-release-probe.json",FileAccess.WRITE).store_string(JSON.stringify(cache_rows,"\t"))

func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"display_mode":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"pad_enabled":0},true)
	Engine.max_fps=0
	await frames_wait(15)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await cache_sample("empty")
	await trial(0)
	await cache_sample("trials-freed")
	ArenaSurfaceCache._entries.clear(); ArenaSurfaceCache._shaders.clear()
	await cache_sample("arena-surface-cache")
	EIFigure.clear_cache()
	await cache_sample("figure-cache")
	EIUnitModel._textures.clear(); EIUnitModel._surface_textures.clear()
	await cache_sample("unit-textures")
	EIAnim._libraries.clear(); EIAnim._morphs.clear()
	await cache_sample("animations")
	Gfx._hd.clear()
	await cache_sample("hd-textures")
	GameData._texture_cache.clear()
	await cache_sample("archive-textures")
	DetailedHead._meshes.clear(); DetailedHead._materials.clear(); DetailedHead._fits.clear()
	await cache_sample("heads")
	UnitWounds.shutdown()
	await cache_sample("wounds")
	EIAudio.shutdown()
	await cache_sample("audio")
	TexUpscale.shutdown()
	get_tree().quit()
