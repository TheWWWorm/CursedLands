extends "terrain_compressed.gd"
## Mixed-resolution legacy texture packs through the actual terrain loader.

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"):
		get_tree().quit(2); return
	GameData.options["confine_mouse"] = 0
	RenderingServer.set_render_loop_enabled(true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var original := GameData.textures
	var high := fixture(256, 256, 9)
	var low := fixture(128, 128, 8)
	for hd in [0, 1]:
		GameData.options["gfx_hd_textures"] = hd
		GameData.textures = archive_for([high, low])
		var terrain := EITerrain.new()
		terrain.resource_prefix = "probe"
		terrain.texture_size = 128; terrain.tile_size = 64
		terrain.set_meta("textures_count", 2)
		var uv := terrain._tile_uv(0, 0, 0)
		terrain._load_atlases()
		check(terrain._atlas_source_size == 256 and not terrain._atlas_hd, "authored HD resolution avoids double upscale")
		check(terrain.texture_size == 128 and terrain.tile_size == 64 and terrain._tile_uv(0, 0, 0) == uv, "map layout and UVs unchanged")
		check(terrain._atlases.get_width() == 256 and terrain._atlases.get_layers() == 2, "mixed resolutions share one texture array")
		var pixels := terrain._atlas_image(0, true)
		check(pixels.get_data() == EIMmp.decode_texture(high, RenderingServer.has_os_feature("s3tc")).get_data(), "authored HD mip chain retained")
		var expected := EIMmp.decode(low)
		expected.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		check(terrain._atlas_image(1).get_data() == expected.get_data(), "only smaller layers resampled")
		terrain._ensure_detail_atlases()
		check(terrain._detail_atlases.get_width() == 320, "padding scales with source resolution")
		var detail := EITerrain.padded_atlas(EIMmp.decode(high), 128, 16)
		detail.generate_mipmaps()
		await frames(2)
		if DisplayServer.get_name() != "headless":
			var uploaded := terrain._atlases.get_layer_data(0)
			if uploaded.is_compressed(): uploaded.decompress()
			uploaded.convert(Image.FORMAT_RGBA8)
			check(uploaded.get_data().slice(0, 256 * 256 * 4) == EIMmp.decode(high).get_data(), "GPU terrain layer retains source pixels")
			check(terrain._detail_atlases.get_layer_data(0).get_data() == detail.get_data(), "GPU padded layer retains all pixels and mips")
		terrain.free()
	GameData.textures = original
	TexUpscale.shutdown()
	print("TERRAIN_MOD_ATLAS ", JSON.stringify({"checks":checks, "failures":failures, "headless":DisplayServer.get_name() == "headless"}))
	get_tree().quit(1 if failures else 0)
