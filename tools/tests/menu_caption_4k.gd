extends "menu_caption_quality.gd"
## Compare the actual displayed lettering with the old Lanczos-only path.
## A fixed content viewport also works on GPU Lab's smaller virtual monitor.
const SIZES := [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160)]

func legacy(source: Texture2D) -> Texture2D:
	if maxi(source.get_width(),source.get_height()) >= 1024: return source
	var image := source.get_image()
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps();image.fix_alpha_edges()
	var factor := minf(4.0,1024.0/maxi(image.get_width(),image.get_height()))
	image.resize(roundi(image.get_width()*factor),roundi(image.get_height()*factor),Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func pairs(figure: Node3D, model: String) -> Array:
	var skin := "mainmenu00" if model=="unmoco2" else "escmenu00"
	var textures := {}
	for name: String in [skin,skin+"labels"]:
		var source := GameData.get_texture(name)
		if source: textures[MenuCaptions.enlarged(source)]=legacy(source)
	var out := []
	var seen := {}
	for mesh: MeshInstance3D in figure.find_children("*","MeshInstance3D",true,false):
		var material := mesh.material_override
		if seen.has(material): continue
		seen[material]=true
		var texture: Texture2D
		if material is StandardMaterial3D: texture=material.albedo_texture
		elif material is ShaderMaterial: texture=material.get_shader_parameter("albedo_tex")
		if texture and textures.has(texture): out.append([material,texture,textures[texture]])
	return out

func install(materials: Array, index: int) -> void:
	for pair: Array in materials:
		if pair[0] is StandardMaterial3D: pair[0].albedo_texture=pair[index]
		else: pair[0].set_shader_parameter("albedo_tex",pair[index])

func dimensions(value: Vector2i) -> void:
	GameData._window_gen+=1
	get_window().wrap_controls=false
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size=value
	get_window().size=value
	await frames(8)
	check(get_viewport().get_visible_rect().size==Vector2(value),"actual content viewport is "+str(value))

func compare(materials: Array, areas: Dictionary, label: String, capture: bool) -> void:
	check(not materials.is_empty(),label+" compares the actual board materials")
	await frames(3);await RenderingServer.frame_post_draw
	var actual := get_viewport().get_texture().get_image()
	install(materials,2)
	await frames(3);await RenderingServer.frame_post_draw
	var before := get_viewport().get_texture().get_image()
	install(materials,1)
	for id: String in areas:
		var area: Rect2=areas[id]
		# Exclude the silhouette; measure the painted interior at display scale.
		var rect := Rect2i(area.grow(-area.size.y*0.12)).intersection(Rect2i(Vector2i.ZERO,actual.get_size()))
		check(rect.get_area()>100,label+" has a visible caption area "+id)
		var old_energy := energy(before,rect)
		var new_energy := energy(actual,rect)
		print("MENU_4K_EDGES ",label," ",id," gain=",new_energy/maxf(old_energy,0.00001)," rect=",rect)
		check(old_energy>0.01 and new_energy>old_energy*1.12,label+" strengthens displayed painted edges "+id)
	if capture:
		check(actual.save_png("user://"+label+".png")==OK,label+" native-pixel capture")
		check(before.save_png("user://"+label+"-legacy.png")==OK,label+" comparison capture")
	await frames(3)

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-locale="): locale=arg.trim_prefix("--menu-locale=")
	RemakeText.lang=locale
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"gfx_weather_surfaces":0},true)
	get_window().mode=Window.MODE_WINDOWED;get_window().borderless=true
	await dimensions(SIZES[-1])
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.detect_graphics=false;add_child(menu)
	menu._scene.set_hour(12);menu._scene.rain_bit=false
	menu._scene._sun.shadow_enabled=false
	await frames(25)
	menu._scene._player.pause()
	get_tree().paused=true
	var main_pairs := pairs(menu._scene._column,"unmoco2")
	for size: Vector2i in SIZES:
		await dimensions(size)
		var areas := {}
		for id: String in MenuScene.BOARDS:
			if not menu._scene._boards.has(id): continue
			var rect := menu._scene.board_rect(id)
			if rect.get_area()<100: continue # LiA has no multiplayer board.
			areas[id]=rect
			check(menu._scene.board_at(rect.get_center())==id,"main caption remains clickable "+id+" "+str(size))
		await compare(main_pairs,areas,"main-"+locale+"-"+str(size.x),size.x==3840)
		for button: Button in menu._campaigns.buttons.values()+[menu._mods_button,menu._arena_pve_button]:
			if button.is_visible_in_tree():
				check(Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),"localized extra button fits "+locale+" "+str(size))
		menu._scene._set_hover("button01_new_game")
		menu._scene._player.advance(0.25);menu._scene._player.pause()
		check(menu._scene.board_at(menu._scene.board_rect("button01_new_game").get_center())=="button01_new_game","hovered main caption remains clickable "+str(size))
		menu._scene._set_hover("");menu._scene._player.advance(0);menu._scene._player.pause()
	atlas(menu._scene._column,"4k-main-"+locale,"unmoco2","button01_new_game" if GameData.campaign_id==CampaignProfile.ASTRAL else "but01")
	menu.free();get_tree().paused=false;await frames()
	var session := Session.new();add_child(session)
	var game := Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0))
	await session.enter_zone("gz1g",1,false)
	session.world.vm.instances.clear();session.world.set_physics_process(false)
	game.hud._dialog.hide();await frames(12)
	game.hud.toggle_menu()
	await get_tree().create_timer(0.8,true,false,true).timeout
	await frames(8)
	var esc := game.hud._menu
	check(get_tree().paused and esc.is_visible_in_tree(),"4K Escape pauses the actual game")
	var esc_pairs := pairs(esc._fig,"unmoco1")
	for size: Vector2i in SIZES:
		await dimensions(size)
		var fitted := Interface800.fit_rect(Rect2(Vector2.ZERO,esc.size))
		check(esc._vp.size.y>=roundi(fitted.size.y),"Escape is rendered at its displayed height "+str(size))
		var areas := {}
		for i in esc._rects.size():
			var rect: Rect2=esc._rects[i]
			rect=Rect2(fitted.position+rect.position*fitted.size/Vector2(800,600),rect.size*fitted.size/Vector2(800,600))
			areas[EscSignpost.REG[i][1]]=rect
			check(esc.board_at(rect.get_center())==EscSignpost.REG[i][1],"Escape caption remains clickable "+EscSignpost.REG[i][1]+" "+str(size))
		await compare(esc_pairs,areas,"escape-"+locale+"-"+str(size.x),size.x==3840)
	atlas(esc._fig,"4k-escape-"+locale,"unmoco1","save" if GameData.campaign_id==CampaignProfile.ASTRAL else "savelabel")
	var retained := texture_for(esc._fig,"save" if GameData.campaign_id==CampaignProfile.ASTRAL else "savelabel")
	game.hud.toggle_menu();await frames(3);game.hud.toggle_menu()
	await get_tree().create_timer(0.8,true,false,true).timeout
	check(texture_for(esc._fig,"save" if GameData.campaign_id==CampaignProfile.ASTRAL else "savelabel")==retained,"4K caption texture survives close and reopen")
	game.hud._on_esc_board("options")
	await get_tree().create_timer(0.8,true,false,true).timeout
	check(game.hud._options.visible and not game.hud._options.hide_text,"4K Options opens with visible settings text")
	atlas(game.hud._options._board._fig,"4k-options-"+locale,"unmoco1","options" if GameData.campaign_id==CampaignProfile.ASTRAL else "optionslabel")
	await shot("options-"+locale+"-3840")
	game.hud._options._close();await frames(4)
	check(not get_tree().paused,"4K Options restores the pause state")
	game.free();session.free();await frames(4)
	print("MENU_CAPTION_4K ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
