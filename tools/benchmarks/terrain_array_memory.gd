extends Node
## Observe engine-reported live texture allocations around production loads.
## Run unchanged against baseline/candidate; this is not total physical VRAM.
var rows := []
var checks := 0
var failures := 0

func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func memory() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)

func _ready() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	GameData.options["gfx_hd_textures"] = 0; GameData.options["confine_mouse"] = 0; Engine.max_fps = 120
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.set_render_loop_enabled(true)
	await frames(16)
	for map_name: String in (["zone1","zone3dun1","zonefinal"] if GameData.campaign_id == CampaignProfile.ASTRAL else ["bz2g","bz1g","zone20"]):
		var archive := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % map_name))
		var prefix := EITerrain.resolve_map_prefix(archive,map_name)
		var header := archive.read(prefix+".mp")
		var terrain := EITerrain.new(); terrain.resource_prefix = prefix
		terrain.texture_size = header.decode_u32(20); terrain.tile_size = header.decode_u32(28)
		terrain.set_meta("textures_count",header.decode_u32(16))
		var before := memory()
		var start := Time.get_ticks_usec(); terrain._load_atlases(); var raw_us := Time.get_ticks_usec()-start
		await frames(4); var raw := memory()
		start = Time.get_ticks_usec(); terrain._ensure_detail_atlases(); var detail_us := Time.get_ticks_usec()-start
		await frames(4); var detail := memory()
		var row := {"map":map_name,"layers":terrain._atlases.get_layers(),"raw_format":terrain._atlases.get_format(),
			"baseline_bytes":before,"raw_added_bytes":raw-before,"detail_added_bytes":detail-raw,"both_added_bytes":detail-before,
			"raw_load_us":raw_us,"detail_load_us":detail_us}
		terrain.free(); await frames(8)
		row["released_bytes"] = memory()-before
		checks += 1
		if row.released_bytes != 0: failures += 1; printerr("FAIL atlas allocation remains after release ",row)
		rows.append(row)
	await frames(16)
	var report := {"checks":checks,"failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"campaign":GameData.campaign_id,"measurement":"engine-reported texture allocation delta, not physical VRAM or FPS"}
	FileAccess.open("user://terrain-array-memory.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TERRAIN_ARRAY_MEMORY ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
