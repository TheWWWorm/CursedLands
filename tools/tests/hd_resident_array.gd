extends Node
## Test-only layer readback compares the existing local upscale + CPU mips
## with the renderer-owned result, including real padded terrain atlases.
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count: int) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func fixture(size: Vector2i, layer: int) -> Image:
	var bytes := PackedByteArray()
	for y in size.y:
		for x in size.x:
			bytes.append_array([(x*71+y*19+layer*41)%256,(x*37+y*89+layer*61)%256,(x*13+y*113+layer*103)%256,(x*83+y*43+layer*53)%256])
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)

func specimen(label: String, sources: Array[Image], hd := true, wrap := false, forced_fallback := false) -> void:
	var original: Array[PackedByteArray] = []
	var expected: Array[Image] = []
	for source: Image in sources:
		original.append(source.get_data())
		var output := TexUpscale.up2(source,wrap) if hd else source.duplicate() as Image
		output.generate_mipmaps(); expected.append(output)
	TexUpscale._shutdown_local()
	var resident := hd and sources.size() > 1 and RenderingServer.get_rendering_device() != null and not forced_fallback
	var start_count := TexUpscale.count
	var candidate := TexUpscale.texture_array(sources,hd,wrap)
	check(candidate != null,label+" creates array")
	if candidate == null: return
	check(candidate is Texture2DArrayRD if resident else candidate is Texture2DArray,label+" expected backend")
	check(candidate.get_width() == expected[0].get_width() and candidate.get_height() == expected[0].get_height()
		and candidate.get_layers() == sources.size() and candidate.has_mipmaps(),label+" immediate dimensions/layer count/mips")
	check(candidate.get_layered_type() == TextureLayered.LAYERED_TYPE_2D_ARRAY,label+" array identity")
	check(TexUpscale.count == start_count+(sources.size() if hd else 0),label+" per-layer load count")
	if resident: check(TexUpscale._rd == null,label+" no local device initialized")
	await frames(4)
	var bytes := 0
	for layer in sources.size():
		check(sources[layer].get_data() == original[layer],label+" immutable source "+str(layer))
		bytes += expected[layer].get_data_size()
		if DisplayServer.get_name() != "headless":
			var actual := candidate.get_layer_data(layer)
			check(actual != null,label+" layer readback "+str(layer))
			if actual:
				check(actual.get_mipmap_count() == expected[layer].get_mipmap_count(),label+" complete mip count "+str(layer))
				var a := actual.get_data(); var b := expected[layer].get_data()
				check(a == b,label+" every byte/mip exact "+str(layer))
				rows.append({"name":label,"layer":layer,"source_size":str(sources[layer].get_size()),"bytes":b.size(),"equal":a == b})
	candidate = null
	await frames(4)
	check(TexUpscaleTexture._live.is_empty(),label+" last array reference releases backing")
	print("ARRAY_CASE ",JSON.stringify({"name":label,"layers":sources.size(),"resident":resident,"output_bytes":bytes}))

func real_atlases() -> void:
	for map_name: String in ["bz2g","bz4g","bz13h"]:
		var arc := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % map_name))
		var prefix := EITerrain.resolve_map_prefix(arc,map_name)
		var header := arc.read(prefix+".mp"); var layers := header.decode_u32(16); var tile := header.decode_u32(28)
		var sources: Array[Image] = []
		for layer in layers: sources.append(GameData.load_image("%s%03d" % [prefix,layer]))
		await specimen(map_name+" original",sources)
		var padded: Array[Image] = []
		for source: Image in sources: padded.append(EITerrain.padded_atlas(source,tile,EITerrain.TERRAIN_GUTTER))
		await specimen(map_name+" padded",padded)

func missing_atlases() -> void:
	var previous := GameData.option("gfx_hd_textures")
	GameData.options["gfx_hd_textures"] = 1
	var terrain := EITerrain.new(); terrain.resource_prefix = "__missing_hd_atlas__"
	terrain.texture_size = 4; terrain.tile_size = 2; terrain.set_meta("textures_count",2)
	terrain._load_atlases()
	check(terrain._atlases.get_width() == 8 and terrain._atlases.get_layers() == 2,"missing original atlases retain doubled size")
	# HD selection is latched at map load, including lazily prepared detail.
	GameData.options["gfx_hd_textures"] = 0
	terrain._ensure_detail_atlases()
	var expected_size := 2*(2+2*EITerrain.TERRAIN_GUTTER)*2
	check(terrain._detail_atlases.get_width() == expected_size,"lazy detail uses latched HD choice")
	var id := terrain._detail_atlases.get_instance_id()
	terrain._ensure_detail_atlases()
	check(terrain._detail_atlases.get_instance_id() == id,"detail preparation reuses existing array")
	await frames(4)
	check_magenta(terrain)
	terrain.free()
	await frames(4)
	check(TexUpscaleTexture._live.is_empty(),"terrain frees both array owners")
	GameData.options["gfx_hd_textures"] = previous

func check_magenta(terrain: EITerrain) -> void:
	# Drop the loop's texture references before the caller tests terrain release.
	if DisplayServer.get_name() != "headless":
		for texture: TextureLayered in [terrain._atlases,terrain._detail_atlases]:
			var expected := Image.create(texture.get_width(),texture.get_height(),false,Image.FORMAT_RGBA8)
			expected.fill(Color.MAGENTA); expected.generate_mipmaps()
			for layer in texture.get_layers():
				check(texture.get_layer_data(layer).get_data() == expected.get_data(),"missing atlas stays solid magenta at every mip")
func _ready() -> void:
	GameData.options["confine_mouse"] = 0; Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(TexUpscale.texture_array([]) == null,"empty input rejected")
	check(TexUpscale.texture_array([null]) == null,"null image rejected")
	check(TexUpscale.texture_array([Image.new()]) == null,"empty image rejected")
	check(TexUpscale.texture_array([fixture(Vector2i(3,5),0),fixture(Vector2i(4,5),1)]) == null,"unequal dimensions rejected")
	for size: Vector2i in [Vector2i(1,1),Vector2i(1,7),Vector2i(7,1),Vector2i(3,5),Vector2i(32,64)]:
		var sources: Array[Image] = [fixture(size,0),fixture(size,1),fixture(size,2)]
		await specimen(str(size)+" clamp",sources)
		await specimen(str(size)+" repeat",sources,true,true)
	await specimen("single layer fallback",[fixture(Vector2i(7,5),0)])
	await specimen("HD off",[fixture(Vector2i(7,5),0),fixture(Vector2i(7,5),1)],false)
	var missing := Image.create(4,4,false,Image.FORMAT_RGBA8); missing.fill(Color.MAGENTA)
	await specimen("missing magenta",[missing,missing])
	await missing_atlases()
	if OS.get_cmdline_user_args().has("--real-atlases"): await real_atlases()
	if RenderingServer.get_rendering_device() != null:
		TexUpscaleTexture.shutdown(); TexUpscaleTexture._tried = true
		await specimen("declined main device",[fixture(Vector2i(3,5),0),fixture(Vector2i(3,5),1)],true,false,true)
		TexUpscaleTexture.shutdown()
		var held := TexUpscale.texture_array([fixture(Vector2i(4,4),0),fixture(Vector2i(4,4),1)])
		await frames(4)
		TexUpscale.shutdown()
		check(held.get_width() == 0 and held.get_layers() == 0 and TexUpscaleTexture._live.is_empty(),"shutdown detaches live array owners")
		held = null
		await specimen("restart",[fixture(Vector2i(4,4),0),fixture(Vector2i(4,4),1)])
	TexUpscale.shutdown()
	await frames(24)
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	FileAccess.open("user://hd-resident-array.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("HD_RESIDENT_ARRAY ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
