extends Node
## Native diagnostic/regression for actual main-menu utility glyph density.
## No production font, style, size or scale is replaced. A separate font copy
## draws offscreen from each control's draw signal, inheriting that exact draw's
## sampling state. Its isolated cache cannot be populated by another control.
const MainMenu = preload("res://src/ui/main_menu.gd")
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var out := "user://menu-utility-glyphs"
var captures := 0
var original_options: Dictionary

class GlyphProbe extends RefCounted:
	var control: Control
	var font: Font
	var source_font: Font
	var fs := 0
	var calls := 0
	func _init(value: Control) -> void:
		control = value
		source_font = control.get_theme_font("font")
		font = source_font.duplicate(true)
		fs = control.get_theme_font_size("font_size")
	func draw() -> void:
		calls += 1
		# Offscreen geometry does not change the real label. Font rasterization
		# still occurs in TextServer before the GPU clips the draw command.
		control.draw_string(font, Vector2(-16384, -16384), control.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	func info() -> Dictionary:
		var caches: Array[Dictionary] = []
		var max_density := 0.0
		var max_size := 0
		for rid: RID in font.get_rids():
			for item: Dictionary in TextServerManager.get_primary_interface().font_get_size_cache_info(rid):
				var px: Vector2i = item.get("size_px", Vector2i.ZERO)
				var density := float(item.get("viewport_oversampling", 1.0))
				caches.append({"size_px":[px.x,px.y], "viewport_oversampling":density,
					"glyphs":int(item.get("glyphs",0)), "textures":int(item.get("textures",0))})
				if int(item.get("textures",0)) > 0 and int(item.get("glyphs",0)) > 0:
					max_density = maxf(max_density, density)
					max_size = maxi(max_size, px.x)
		var scale := control.get_global_transform().get_scale().abs()
		var expected := maxf(scale.x,scale.y) * control.get_viewport().get_oversampling()
		return {"text":control.text, "font_name":font.get_font_name(), "font_style":font.get_font_style_name(),
			"logical_font_size":fs, "scale":[scale.x,scale.y], "viewport_oversampling":control.get_viewport().get_oversampling(),
			"expected_density":expected, "raster_density":max_density, "raster_size_px":max_size,
			"draw_calls":calls, "font_rids_independent":font.get_rids()[0] != source_font.get_rids()[0],
			"production_font_unchanged":control.get_theme_font("font") == source_font,
			"font_is_msdf":font.is_multichannel_signed_distance_field(), "caches":caches}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ",message)

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func resize_native(dimensions: Vector2i) -> void:
	GameData._window_gen += 1
	get_window().size = dimensions
	for i in 60:
		await get_tree().process_frame
		if i >= 5 and get_window().size == dimensions and get_viewport().get_visible_rect().size == Vector2(dimensions): break
	await frames(8)
	check(get_window().size == dimensions and get_viewport().get_visible_rect().size == Vector2(dimensions),
		"settled native window and content extent " + str(dimensions))

func new_menu() -> Control:
	var menu := MainMenu.new()
	menu.detect_graphics = false
	add_child(menu)
	await frames(16)
	check(menu._scene != null, "fixture uses the real signpost menu")
	if menu._scene: menu._scene.process_mode = Node.PROCESS_MODE_DISABLED
	Input.warp_mouse(Vector2(12,12))
	GameData._tips._hide()
	return menu

func rect_data(control: Control) -> Array:
	var rect := control.get_global_rect()
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func capture_footer(menu: Control, name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var rect: Rect2 = menu._utility_bar.get_global_rect().merge(menu._wiki_hint.get_global_rect()).grow(6)
	var region := Rect2i(rect).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	check(region.has_area() and image.get_size() == get_window().size, "native utility capture " + name)
	if region.has_area():
		image.get_region(region).save_png(out.path_join(name + ".png"))
		captures += 1
	if name == "en-cold-3840-natural":
		image.save_png(out.path_join("en-cold-3840-context.png"))
		captures += 1

func observe(menu: Control, tag: String) -> void:
	var controls: Array[Control] = [menu._mods_button,menu._arena_pve_button,menu._wiki_hint]
	var names := ["mods", "trials", "wiki"]
	var probe_rows: Array[Dictionary] = []
	var rects: Array = []
	var probes: Array[GlyphProbe] = []
	check(menu._utility_bar.is_visible_in_tree() and menu._wiki_hint.is_visible_in_tree(), "normal utility controls visible " + tag)
	await capture_footer(menu,tag + "-natural")
	for control: Control in controls:
		rects.append(rect_data(control))
		var probe := GlyphProbe.new(control)
		probes.append(probe)
		control.draw.connect(probe.draw)
		control.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	for i in controls.size():
		var row := probes[i].info()
		row.control = names[i]
		row.rect = rects[i]
		row.stage = "natural"
		probe_rows.append(row)
		check(row.draw_calls > 0 and row.font_rids_independent and row.production_font_unchanged,
			"isolated draw-time probe uses the unchanged production font " + tag + " " + names[i])
		check(rect_data(controls[i]) == rects[i], "glyph observer preserves actual control geometry " + tag + " " + names[i])
		check(float(row.raster_density) >= float(row.expected_density)-0.02,
			"natural glyph raster density resolves displayed scale " + tag + " " + names[i]
			+ " actual=" + str(row.raster_density) + " required=" + str(row.expected_density))
		controls[i].draw.disconnect(probes[i].draw)
	# Diagnostic positive control. Only the sampling flag is re-propagated;
	# geometry, font, colors and style stay unchanged. Natural assertions above
	# still fail on an unfixed build. The control proves the proposed mechanism.
	menu.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
	menu.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	probes.clear()
	for control: Control in controls:
		var probe := GlyphProbe.new(control)
		probes.append(probe)
		control.draw.connect(probe.draw)
		control.queue_redraw()
	await frames(3)
	await RenderingServer.frame_post_draw
	for i in controls.size():
		var row := probes[i].info()
		row.control = names[i]
		row.rect = rect_data(controls[i])
		row.stage = "sampling-refresh-control"
		probe_rows.append(row)
		check(row.draw_calls > 0 and float(row.raster_density) >= float(row.expected_density)-0.02,
			"explicit sampling refresh resolves the same control " + tag + " " + names[i])
		check(rect_data(controls[i]) == rects[i] and row.production_font_unchanged,
			"sampling control preserves geometry and font " + tag + " " + names[i])
		controls[i].draw.disconnect(probes[i].draw)
	await capture_footer(menu,tag + "-refreshed")
	observations.append({"tag":tag,"window_size":[get_window().size.x,get_window().size.y],
		"menu_rect":rect_data(menu),"utility_rect":rect_data(menu._utility_bar),
		"upscaling_option":GameData.option("rtx_upscaling"),"scale_3d":get_viewport().scaling_3d_scale,
		"scaling_mode_3d":get_viewport().scaling_3d_mode,"probes":probe_rows})
	print("UTILITY_GLYPHS ",tag," ",JSON.stringify(probe_rows))

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	original_options = GameData.options.duplicate(true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"display_mode":0,"pad_enabled":0},true)
	Engine.max_fps = 30
	await frames(24)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	await frames(12)
	GameData._window_gen += 1
	get_window().borderless = true
	get_window().wrap_controls = false
	get_window().min_size = Vector2i.ONE
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().position = Vector2i.ZERO
	await frames(4)
	check(DisplayServer.get_name() != "headless", "native rendered fixture, not dummy headless font evidence")
	check(GameData.campaign_id == CampaignProfile.ORIGINAL, "original campaign exposes both reported utility labels")
	for language in ["en","ru","de"]:
		RemakeText.lang = language
		await resize_native(Vector2i(3840,2160))
		var menu := await new_menu()
		await observe(menu,language + "-cold-3840")
		menu.queue_free(); await frames(6)
		await resize_native(Vector2i(1280,720))
		menu = await new_menu()
		await observe(menu,language + "-cold-1280")
		for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(3840,2160)]:
			await resize_native(dimensions)
			await observe(menu,language + "-resized-" + str(dimensions.x))
		menu.queue_free(); await frames(6)
		# A normal options round trip can resize while the menu labels are hidden.
		await resize_native(Vector2i(1280,720))
		menu = await new_menu()
		menu._on_board("options")
		await frames(12)
		check(menu._options.visible and not menu._utility_bar.is_visible_in_tree(), "real Options hides utility labels " + language)
		await resize_native(Vector2i(3840,2160))
		menu._options._close()
		await frames(12)
		await observe(menu,language + "-options-return-3840")
		menu.queue_free(); await frames(6)
	check(captures <= 31, "bounded native evidence captures")
	var result := {"checks":checks,"failures":failures,"captures":captures,"observations":observations,
		"method":"Offscreen glyphs drawn through each unchanged production control; independent same-font caches measure actual draw-time oversampling. Natural captures precede observer installation.",
		"performance_qualification":false,"production_files_changed":false}
	FileAccess.open(out.path_join("menu-utility-glyphs.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	GameData.options = original_options
	print("MENU_UTILITY_GLYPHS ",checks," checks ",failures.size()," failures")
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
