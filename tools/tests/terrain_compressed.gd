extends "mmp_texture.gd"
## Exercise production raw-array loading, not just the MMP decoder. Authored
## blocks/pixels are the oracle; the old regenerated mips are not equivalent.
var rows := []
var total_bytes := 0
var total_rgba_bytes := 0
var compressed_maps := 0

func payload_size(texture: TextureLayered) -> int:
	var w := texture.get_width(); var h := texture.get_height(); var bytes := 0
	while true:
		if texture.get_format() in [Image.FORMAT_DXT1,Image.FORMAT_DXT3]:
			bytes += ((w+3)/4)*((h+3)/4)*(8 if texture.get_format() == Image.FORMAT_DXT1 else 16)
		else: bytes += w*h*4
		if w == 1 and h == 1: break
		w = maxi(1,w>>1); h = maxi(1,h>>1)
	return bytes*texture.get_layers()

func frames(count: int) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func archive_for(layers: Array) -> EIResArchive:
	var archive := EIResArchive.new()
	for i in layers.size():
		if layers[i] == null: continue
		var data: PackedByteArray = layers[i]
		archive.entries["probe%03d.mmp" % i] = Vector2i(archive._bytes.size(),data.size())
		archive._bytes.append_array(data)
	return archive

func verify_array(terrain: EITerrain, sources: Array, label: String, expected_format: Image.Format) -> void:
	var texture := terrain._atlases as Texture2DArray
	check(texture != null,label+": regular texture array")
	if texture == null: return
	check(texture.get_width() == terrain.texture_size and texture.get_height() == terrain.texture_size,
		label+": original dimensions")
	check(texture.get_layers() == sources.size(),label+": all layers retained")
	check(texture.get_format() == expected_format,label+": expected uniform format")
	check(texture.has_mipmaps(),label+": full-chain texture")
	await frames(2)
	var actual_bytes := 0
	var exact_readback := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	if DisplayServer.get_name() != "headless":
		for i in sources.size():
			var pixels := texture.get_layer_data(i)
			check(pixels != null,label+": read layer "+str(i))
			if pixels == null: continue
			actual_bytes += pixels.get_data_size()
			var data: PackedByteArray = sources[i] if sources[i] != null else PackedByteArray()
			var valid := data.size() >= 76 and data.decode_u32(4) == terrain.texture_size and data.decode_u32(8) == terrain.texture_size
			if valid:
				# GLES get_layer_data() renders mip zero to RGBA and generates
				# new mips. Explicit shader LODs in terrain_compressed_upload
				# verify its real authored levels instead of that reconstruction.
				if exact_readback: check_pixels(pixels,data,label+" layer "+str(i))
				elif texture.get_format() == Image.FORMAT_RGBA8:
					check(pixels.get_data().slice(0,terrain.texture_size*terrain.texture_size*4) == EIMmp.decode(data).get_data(),
						label+": RGBA base level unchanged "+str(i))
				if pixels.is_compressed():
					check(pixels.get_data().slice(0,authored_bytes(data)) == data.slice(76,76+authored_bytes(data)),
						label+": authored compressed payload unchanged "+str(i))
			else:
				var magenta := Image.create(terrain.texture_size,terrain.texture_size,false,Image.FORMAT_RGBA8)
				magenta.fill(Color.MAGENTA); magenta.generate_mipmaps()
				check(pixels.get_data() == magenta.get_data(),label+": missing/invalid layer is magenta at every mip")
	var rgba := Image.create(terrain.texture_size,terrain.texture_size,true,Image.FORMAT_RGBA8).get_data_size()*sources.size()
	var payload := payload_size(texture)
	if exact_readback and DisplayServer.get_name() != "headless":
		check(actual_bytes == payload,label+": full uploaded payload size")
	rows.append({"name":label,"layers":sources.size(),"format":texture.get_format(),"bytes_read_back":actual_bytes,
		"exact_mip_readback":exact_readback and DisplayServer.get_name() != "headless","payload_bytes":payload,"rgba_bytes":rgba})
	if not label.begins_with("fixture "):
		total_bytes += payload; total_rgba_bytes += rgba
		if texture.get_format() in [Image.FORMAT_DXT1,Image.FORMAT_DXT3]: compressed_maps += 1

func test_arrays() -> void:
	var saved := GameData.textures
	var bc1 := fixture(8,8,4)
	var bc2 := fixture(8,8,4,true)
	var alpha := fixture(8,8,4,false,true)
	var supported := RenderingServer.has_os_feature("s3tc")
	var cases := [
		["opaque BC1",[bc1,bc1],Image.FORMAT_DXT1],
		["single layer",[bc1],Image.FORMAT_DXT1],
		["opaque BC2",[bc2,bc2],Image.FORMAT_DXT3],
		["mixed BC1/BC2",[bc1,bc2],Image.FORMAT_RGBA8],
		["transparent first",[alpha,bc1],Image.FORMAT_RGBA8],
		["transparent last",[bc1,alpha],Image.FORMAT_RGBA8],
		["missing first",[null,bc1],Image.FORMAT_RGBA8],
		["missing last",[bc1,null],Image.FORMAT_RGBA8],
		["invalid payload",[bc1,PackedByteArray([1,2,3])],Image.FORMAT_RGBA8],
		["wrong height",[bc1,fixture(8,4,4)],Image.FORMAT_RGBA8],
		["large missing tail",[fixture(128,128,8),fixture(128,128,1)],Image.FORMAT_RGBA8],
	]
	for entry: Array in cases:
		GameData.textures = archive_for(entry[1])
		var terrain := EITerrain.new(); terrain.resource_prefix = "probe"
		terrain.texture_size = 128 if entry[0] == "large missing tail" else 8
		terrain.tile_size = terrain.texture_size/2; terrain.set_meta("textures_count",entry[1].size())
		terrain._load_atlases()
		await verify_array(terrain,entry[1],"fixture "+entry[0],entry[2] if supported else Image.FORMAT_RGBA8)
		if entry[0] == "opaque BC1":
			# Lazy detail continues to transform the decoded top level. Loading
			# compressed originals must not change its format, pixels or latch.
			GameData.options["gfx_hd_textures"] = 1
			terrain._ensure_detail_atlases()
			var expected := EITerrain.padded_atlas(EIMmp.decode(bc1),terrain.tile_size,EITerrain.TERRAIN_GUTTER)
			expected.generate_mipmaps()
			check(terrain._detail_atlases.get_format() == Image.FORMAT_RGBA8,"detail stays RGBA")
			check(terrain._detail_atlases.get_width() == expected.get_width(),"lazy detail uses latched HD-off")
			await frames(2)
			if DisplayServer.get_name() != "headless":
				check(terrain._detail_atlases.get_layer_data(0).get_data() == expected.get_data(),"padded detail every byte/mip unchanged")
			GameData.options["gfx_hd_textures"] = 0
		terrain.free(); await frames(2)
	GameData.textures = saved

func real_map(map_name: String) -> void:
	var archive := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % map_name))
	var prefix := EITerrain.resolve_map_prefix(archive,map_name)
	var header := archive.read(prefix+".mp")
	check(header.size() >= 38,map_name+": original map header")
	if header.size() < 38: return
	var terrain := EITerrain.new(); terrain.resource_prefix = prefix
	terrain.texture_size = header.decode_u32(20); terrain.tile_size = header.decode_u32(28)
	terrain.set_meta("textures_count",header.decode_u32(16))
	var sources := []
	var eligible := true
	for i in int(terrain.get_meta("textures_count")):
		var data := GameData.textures.read("%s%03d.mmp" % [prefix,i])
		var pixels := EIMmp.decode_texture(data,true)
		check(pixels != null,map_name+": decode layer "+str(i))
		if pixels == null: eligible = false; continue
		check_pixels(pixels,data,map_name+" CPU layer "+str(i))
		if pixels.get_format() != Image.FORMAT_DXT1: eligible = false
		sources.append(data)
	var started := Time.get_ticks_usec()
	terrain._load_atlases()
	var loading_us := Time.get_ticks_usec()-started
	await verify_array(terrain,sources,map_name,Image.FORMAT_DXT1 if eligible and RenderingServer.has_os_feature("s3tc") else Image.FORMAT_RGBA8)
	rows[-1]["load_us"] = loading_us
	rows[-1]["prefix"] = prefix
	rows[-1]["compressed_eligible"] = eligible
	terrain.free(); await frames(2)

func _ready() -> void:
	GameData.options["gfx_hd_textures"] = 0; GameData.options["confine_mouse"] = 0
	Engine.max_fps = 120
	RenderingServer.set_render_loop_enabled(true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await test_arrays()
	var names := GameData.map_names() if OS.get_cmdline_user_args().has("--all-maps") else \
		PackedStringArray(["zone1","zone3dun1","zonefinal"] if GameData.campaign_id == CampaignProfile.ASTRAL else ["bz2g","bz13h"])
	for map_name: String in names: await real_map(map_name)
	TexUpscale.shutdown(); await frames(12)
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"s3tc":RenderingServer.has_os_feature("s3tc"),"headless":DisplayServer.get_name()=="headless",
		"campaign":GameData.campaign_id,"maps":names.size(),"compressed_maps":compressed_maps,"payload_bytes":total_bytes,"rgba_bytes":total_rgba_bytes,"rows":rows}
	FileAccess.open("user://terrain-compressed.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TERRAIN_COMPRESSED ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
