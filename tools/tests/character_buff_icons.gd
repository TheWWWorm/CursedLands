extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=5)->void:
	for i in n:await get_tree().process_frame
func _ready()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-lang="): RemakeText.lang=arg.get_slice("=",1)
	await frames(24)
	check(GameData.option("character_buff_icons")==1,"compact effects enabled in a fresh profile")
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0},true)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED
	await frames()
	get_window().position=Vector2i(100,100)
	var background:=ColorRect.new();background.color=Color("283126");background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var s:=Session.new();s.state=CampaignState.new();s.world=w
	var g:=Game.new();g.world=w;g.session=s
	var u:=w.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(1,1,0),"complexion":Vector3(0.0,0.55,0.9)})
	u.controller=0;u.set_meta("hero",{"prototype":"Human Hero"});u.set_process(false);u.set_physics_process(false)
	u.buffs={"strength":{"_effect_ticks":2400,"hp_mul":1.4},"regeneration":{"_effect_ticks":73}}
	u.refresh_figure(true)
	check(u.model._detail!=null,"world hero uses portrait head")
	var scale_:Vector3=u.model._detail.basis.get_scale()
	check(absf(scale_.x-scale_.y)<.00001 and absf(scale_.x-scale_.z)<.00001,"world face retains portrait proportions")
	var panel:=UnitPanel.new();panel.game=g;panel.examine=u;add_child(panel)
	await frames(12)
	check(panel._doll._model._detail.mesh==u.model._detail.mesh,"HUD and world share the authored face mesh")
	for size_:Vector2i in [Vector2i(1280,800),Vector2i(720,1280),Vector2i(1920,1080)]:
		get_window().size=size_;await frames(8)
		check(get_window().size==size_,"physical window matches requested layout")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var image:=get_viewport().get_texture().get_image()
			image.get_region(Rect2i(Vector2i.ZERO,Vector2i(panel.size).min(image.get_size()))).save_png("user://buff-icons-%dx%d.png"%[size_.x,size_.y])
	GameData.options.character_buff_icons=0;await frames()
	check(not u.buffs.is_empty(),"hiding the overlay retains active effects")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().get_region(Rect2i(Vector2i.ZERO,Vector2i(panel.size))).save_png("user://buff-icons-off.png")
	GameData.options.character_buff_icons=1
	u.buffs={};await frames()
	check(panel._unit==u,"empty effects retain the selected character")
	panel.free();w.free();g.free();s.free()
	var options:=OptionsPanel.new();add_child(options)
	options.open();options._show_group(OptionsPanel.INTERFACE_GROUP)
	var row:Dictionary=options._rows[10]
	check(row.name=="character_buff_icons" and row.label==RemakeText.t("Character buff icons"),"localized option is on the Interface page")
	check(row.tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS.character_buff_icons[1])),"localized help describes the overlay")
	for value in [0,1]:
		options._toggle(10)
		check(options._values.character_buff_icons==value,"option control toggles the overlay")
		check(options._switch_text(row)==RemakeText.t("Off" if value==0 else "On"),"localized option choice")
		get_window().size=Vector2i(1280,800);await frames(8)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://buff-option-%d.png"%value)
	if DisplayServer.get_name()!="headless":
		get_window().grab_focus()
		Input.warp_mouse(Vector2(20,20))
		await frames(6)
		GameData._tips.delay=0.1
		var pointer:=options._origin()+Vector2(400,168+24*10)*options.kv()
		Input.warp_mouse(pointer)
		var motion:=InputEventMouseMotion.new();motion.position=pointer;Input.parse_input_event(motion)
		await get_tree().create_timer(0.3,true,false,true).timeout
		check(GameData._tips._panel.visible and GameData._tips._text.contains(RemakeText.t(GameData.REMAKE_OPTIONS.character_buff_icons[1])),"option help appears")
		check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"option help fits the viewport")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://buff-option-help.png")
	options._toggle(10)
	options._accept()
	var config:=ConfigFile.new()
	check(config.load(GameData.CONFIG_PATH)==OK and config.get_value("options","character_buff_icons",-1)==0,"option persists on acceptance")
	options.free();TexUpscale.shutdown()
	print("CHARACTER_BUFF_ICONS ", JSON.stringify({"checks":checks,"failures":failures}));get_tree().quit(1 if failures else 0)
