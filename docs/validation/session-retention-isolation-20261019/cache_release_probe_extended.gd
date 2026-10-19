extends "../repo/tools/benchmarks/coop_traversal_session.gd"
var cache_rows := []

func cache_sample(label: String) -> void:
	await frames_wait(30)
	await get_tree().create_timer(0.3,true,false,true).timeout
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
	Gfx.clear_clouds()
	await cache_sample("clouds")
	Gfx._noise_cache.clear()
	await cache_sample("noise")
	ShaderWarmup._keep.clear(); ShaderWarmup._warmed.clear(); ShaderWarmup._mms.clear(); ShaderWarmup._formats.clear()
	await cache_sample("shader-warmers")
	RenderingServer.directional_shadow_atlas_set_size(256,true)
	get_viewport().positional_shadow_atlas_size=0
	await cache_sample("shadow-atlases")
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	get_viewport().use_taa=false
	get_viewport().screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	await cache_sample("root-render-target")
	get_viewport().world_3d=World3D.new()
	await cache_sample("root-world")
	TexUpscale.shutdown()
	get_tree().quit()
