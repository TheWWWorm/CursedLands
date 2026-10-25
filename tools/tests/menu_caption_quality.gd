extends Node
## Preserve the original painted glyphs while reducing magnification blur,
## then exercise the real in-game Escape signpost and Options board.
var checks := 0
var failures := 0
var locale := "en"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",message)
func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame
func texture_for(figure: Node3D, part: String) -> Texture2D:
	var node := figure.find_child(part,true,false)
	if node == null: return null
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var material := mesh.material_override
		if material is StandardMaterial3D: return material.albedo_texture
		if material is ShaderMaterial: return material.get_shader_parameter("albedo_tex")
	return null
func energy(image: Image, rect: Rect2i) -> float:
	var total := 0.0
	for y in range(rect.position.y+1,rect.end.y-1):
		for x in range(rect.position.x+1,rect.end.x-1):
			var c := image.get_pixel(x,y).get_luminance()
			var dx := c-image.get_pixel(x+1,y).get_luminance()
			var dy := c-image.get_pixel(x,y+1).get_luminance()
			total += dx*dx+dy*dy
	return total
func atlas(figure: Node3D, label: String, model: String, part: String) -> void:
	var baked := GameData.campaign_id == CampaignProfile.ASTRAL
	var name := "mainmenu00" if model == "unmoco2" else "escmenu00"
	if not baked: name += "labels"
	var original := GameData.load_image(name)
	var texture := texture_for(figure,part)
	var actual := texture.get_image() if texture else null
	check(actual != null,label+" has native caption artwork")
	if actual == null: return
	check(actual.get_width() >= mini(original.get_width()*4,1024),label+" avoids bilinear enlargement of low-resolution glyphs")
	check(actual.has_mipmaps(),label+" retains mip filtering for moving boards")
	var regions: Array[Rect2i]
	if baked:
		regions = [Rect2i(138,132,108,20),Rect2i(136,160,110,20),Rect2i(138,190,108,20),Rect2i(138,219,108,20)]
		regions.append(Rect2i(60,176,69,19) if model == "unmoco2" else Rect2i(62,128,23,122))
	else:
		# Native UV regions, including the vertically authored base lettering.
		var prefix := "but" if model == "unmoco2" else ""
		for mesh: MeshInstance3D in figure.find_children("*","MeshInstance3D",true,false):
			var id := String(mesh.get_parent().name)
			if not (id.ends_with("label") or (id.begins_with(prefix) and prefix != "" and not id.begins_with("button"))): continue
			var uv: PackedVector2Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
			var rect := Rect2(uv[0]*Vector2(original.get_size()),Vector2.ZERO)
			for v: Vector2 in uv: rect = rect.expand(v*Vector2(original.get_size()))
			regions.append(Rect2i(rect).intersection(Rect2i(Vector2i.ZERO,original.get_size())))
	var reduced := actual.duplicate() as Image
	reduced.clear_mipmaps()
	reduced.resize(original.get_width(),original.get_height(),Image.INTERPOLATE_LANCZOS)
	var linear := original.duplicate() as Image
	linear.clear_mipmaps()
	linear.resize(actual.get_width(),actual.get_height(),Image.INTERPOLATE_BILINEAR)
	var factor := Vector2(actual.get_size())/Vector2(original.get_size())
	for region: Rect2i in regions:
		var error := 0.0
		var samples := 0
		for y in range(region.position.y,region.end.y):
			for x in range(region.position.x,region.end.x):
				var c := original.get_pixel(x,y)
				var d := reduced.get_pixel(x,y)
				if c.a < 0.99: continue
				error += absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)
				samples += 3
		var mae := error/maxi(1,samples)
		var high := Rect2i(Vector2(region.position)*factor,Vector2(region.size)*factor)
		var before := energy(linear,high)
		var after := energy(actual,high)
		print("CAPTION_ART ",label," region=",region," native_error=",mae," edge_gain=",after/maxf(0.00001,before))
		check(samples > 0 and mae < 0.035,label+" preserves original glyphs, bevels, colors and background: "+str(region))
		check(after > before*1.05,label+" restores caption edge contrast lost to bilinear scaling: "+str(region))
	check(actual.save_png("user://"+label+"-atlas.png") == OK,label+" atlas captured")
func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://"+id+".png") == OK,id+" captured")
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-locale="): locale = arg.trim_prefix("--menu-locale=")
	RemakeText.lang = locale
	GameData._window_gen += 1
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"gfx_weather_surfaces":0},true)
	GameData.options.resolution = GameData.resolutions().find(Vector2i(1600,900))
	GameData._apply_window()
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600,900)
	await frames()
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.detect_graphics = false;add_child(menu)
	menu._scene.set_hour(12);menu._scene.rain_bit = false
	await frames(60)
	atlas(menu._scene._column,"main-"+locale,"unmoco2","button01_new_game" if GameData.campaign_id == CampaignProfile.ASTRAL else "but01")
	await shot("main-menu-"+locale)
	var first_board := "button01_new_game"
	menu._scene._set_hover(first_board)
	await frames(20)
	atlas(menu._scene._column,"main-hover-"+locale,"unmoco2","button01_new_game" if GameData.campaign_id == CampaignProfile.ASTRAL else "but01")
	check(menu._scene.board_at(menu._scene.board_rect(first_board).get_center()) == first_board,"native lettering retains main-menu hit area")
	await shot("main-menu-hover-"+locale)
	menu.free();await frames()
	var session := Session.new();add_child(session)
	var game := Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0))
	await session.enter_zone("gz1g",1,false)
	session.world.vm.instances.clear()
	session.world.set_physics_process(false)
	game.hud._dialog.hide()
	await frames(30)
	game.hud.toggle_menu()
	await get_tree().create_timer(0.8,true,false,true).timeout
	await frames(12)
	var esc := game.hud._menu
	check(get_tree().paused and esc.is_visible_in_tree(),"actual single-player Escape screen pauses the game")
	atlas(esc._fig,"escape-"+locale,"unmoco1","save" if GameData.campaign_id == CampaignProfile.ASTRAL else "savelabel")
	await shot("ingame-escape-"+locale)
	var caption_part := "save" if GameData.campaign_id == CampaignProfile.ASTRAL else "savelabel"
	var retained := texture_for(esc._fig,caption_part)
	game.hud.toggle_menu();await frames(3)
	game.hud.toggle_menu()
	await get_tree().create_timer(0.8,true,false,true).timeout
	await frames(8)
	check(texture_for(esc._fig,caption_part) == retained and retained != null,"reopening Escape retains original caption artwork")
	for part: String in EscSignpost.BOARDS:
		var i := 0
		for row: Array in EscSignpost.REG:
			if row[1] == part: break
			i += 1
		var fitted := Interface800.fit_rect(Rect2(Vector2.ZERO,esc.size))
		var point := fitted.position+esc._rects[i].get_center()*fitted.size/Vector2(800,600)
		check(esc.board_at(point) == part,"Escape board stays clickable: "+part)
	game.hud._on_esc_board("options")
	var options := game.hud._options
	var started := Time.get_ticks_msec()
	while options.hide_text and Time.get_ticks_msec()-started < 3000:
		await get_tree().process_frame
	await frames(4)
	check(not options.hide_text,"Options slide completes and settings text appears")
	check(game.hud._options.visible,"Escape Options opens normally")
	atlas(game.hud._options._board._fig,"options-"+locale,"unmoco1","options" if GameData.campaign_id == CampaignProfile.ASTRAL else "optionslabel")
	await shot("ingame-options-"+locale)
	game.hud._options._close()
	await frames()
	check(not get_tree().paused,"closing Options restores the original pause state")
	game.free();session.free();await frames()
	print("MENU_CAPTION_QUALITY ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
