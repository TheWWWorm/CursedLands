extends Node
## Readback is deliberately test-only: compare every generated GPU mip against
## the established local-device upscale followed by Image.generate_mipmaps.
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func fixture(size: Vector2i) -> Image:
	var bytes := PackedByteArray()
	for y in size.y:
		for x in size.x:
			bytes.append_array([(x*71+y*19)%256,(x*37+y*89)%256,(x*13+y*113)%256,(x*83+y*43)%256])
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)

func specimen(label: String, source: Image, wrap: bool) -> void:
	check(source != null,"loaded " + label)
	if source == null: return
	var original := source.get_data()
	var expected := TexUpscale.up2(source,wrap); expected.generate_mipmaps()
	var candidate := TexUpscaleTexture.create(source,wrap)
	check(candidate != null,label + " creates resident output")
	if candidate == null: return
	check(candidate.get_width() == source.get_width()*2 and candidate.get_height() == source.get_height()*2,label + " dimensions immediately available")
	await frames(4)
	var actual := candidate.get_image()
	check(actual != null,label + " test readback available")
	if actual:
		check(actual.get_size() == expected.get_size() and actual.get_format() == expected.get_format() and actual.get_mipmap_count() == expected.get_mipmap_count(),label + " layout and complete mip chain")
		var a := actual.get_data(); var b := expected.get_data()
		var changed := 0; var peak := 0
		if a.size() == b.size():
			for i in a.size():
				changed += int(a[i] != b[i]); peak = maxi(peak,absi(a[i]-b[i]))
		else: changed = -1; peak = 255
		check(a == b,label + " every output byte equals legacy upscale/mips")
		rows.append({"name":label,"wrap":wrap,"source_size":str(source.get_size()),"output_bytes":b.size(),"changed_bytes":changed,"peak_delta":peak})
	check(source.get_data() == original,label + " source remains immutable")
	candidate = null
	await frames(4)
	check(TexUpscaleTexture._live.is_empty(),label + " released backing texture")

func production_entry() -> void:
	GameData.options["gfx_hd_textures"] = 1
	Gfx._hd.clear(); TexUpscale._shutdown_local()
	var start_count := TexUpscale.count
	var texture := Gfx.texture_3d("govenorhouse00")
	check(texture is Texture2DRD,"production scenery selects resident texture")
	check(TexUpscale._rd == null,"production resident path does not initialize a local device")
	check(TexUpscale.count == start_count+1,"load report counts resident output once")
	check(Gfx.texture_3d("GOVENORHOUSE00") == texture,"HD cache remains case insensitive")
	check(Gfx.texture_3d("missing_hd_fixture") == null,"missing texture keeps null fallback")
	await frames(4)
	# Terrain/local-device cleanup must never invalidate scenery output.
	var pixels := texture.get_image().get_data()
	TexUpscale.up2(fixture(Vector2i(8,8)),false)
	TexUpscale._shutdown_local()
	check(texture.get_image().get_data() == pixels,"local-device teardown preserves resident scenery")
	Gfx._hd.clear()
	check(texture.get_width() > 0,"a live material reference survives cache eviction")
	texture = null
	await frames(4)
	check(TexUpscaleTexture._live.is_empty(),"last material reference releases evicted scenery")

func fallback_fixture() -> void:
	var source := fixture(Vector2i(3,5))
	var expected := TexUpscale.up2(source,false); expected.generate_mipmaps()
	var candidate := TexUpscale.texture_2d(source,false)
	check(candidate is ImageTexture,"unsupported resident path retains ImageTexture fallback")
	check(candidate.get_size() == Vector2(expected.get_size()),"fallback dimensions unchanged")
	if DisplayServer.get_name() != "headless":
		await frames(4)
		check(candidate.get_image().get_data() == expected.get_data(),"fallback output/mips equal established image path")
	check(TexUpscaleTexture._live.is_empty(),"fallback does not own main-device textures")

func _ready() -> void:
	GameData.options["confine_mouse"] = 0
	Engine.max_fps = 120
	check(TexUpscale.texture_2d(null) == null,"null source declines texture creation")
	check(TexUpscale.texture_2d(Image.new()) == null,"empty source declines texture creation")
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		check(TexUpscaleTexture.create(fixture(Vector2i(4,4))) == null,"unsupported backend declines resident path")
		RenderingServer.set_render_loop_enabled(true)
		await fallback_fixture()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.set_render_loop_enabled(true)
		for size: Vector2i in [Vector2i(1,1),Vector2i(1,7),Vector2i(7,1),Vector2i(3,5),Vector2i(32,64)]:
			for wrap in [false,true]: await specimen(str(size),fixture(size),wrap)
		for name: String in ["govenorhouse00","tree02","rikarrowsmoke"]:
			await specimen(name,GameData.load_image(name),true)
		await production_entry()
		# Emulate a main-device capability/pipeline decline on a supported GPU.
		# The independent local-device fallback must remain usable.
		TexUpscaleTexture.shutdown(); TexUpscaleTexture._tried = true
		await fallback_fixture()
		TexUpscaleTexture.shutdown()
		# Explicit shutdown also releases a still-owned result, then allows reuse.
		var held := TexUpscaleTexture.create(fixture(Vector2i(8,8)))
		await frames(4)
		TexUpscaleTexture.shutdown()
		check(held != null and held.get_width() == 0 and TexUpscaleTexture._live.is_empty(),"shutdown detaches live material textures")
		held = null
		await specimen("after restart",fixture(Vector2i(4,4)),true)
	TexUpscaleTexture.shutdown(); TexUpscale.shutdown()
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	FileAccess.open("user://hd-resident-texture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("HD_RESIDENT_TEXTURE ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
