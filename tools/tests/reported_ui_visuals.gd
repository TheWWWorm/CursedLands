extends Node
## Real network selector at desktop scales plus native Brissen/item previews.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(n:=8)->void:
	for i in n:await get_tree().process_frame
func capture(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://"+label+".png")
func _ready()->void:_run.call_deferred()
func _run()->void:
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"confine_mouse":0,"net_lan":0,"net_directory":0,"net_upnp":0,"show_tutorial":0},true)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED
	RenderingServer.set_render_loop_enabled(true)
	var panel:=NetworkPanel.new();add_child(panel)
	for locale in [RemakeText.lang]:
		RemakeText.lang=locale
		for shape:Vector2i in [Vector2i(1280,720),Vector2i(3840,2160)]:
			get_window().size=shape;await frames()
			panel.open();panel.show_page(NetworkPanel.HOST_COOP);await frames()
			var choice:=panel._save_choice
			for value:String in [RemakeText.t("Loading…"),RemakeText.t("A new game (the beginning of the story)")]:choice.add_item(value)
			choice.show_popup();await frames()
			var scale:=choice.get_global_transform_with_canvas().get_scale().x
			check(choice._popup_font.oversampling>=scale-.001 and choice._display_font.oversampling>=scale-.001,"selector fonts rasterize at actual scale %s %s"%[locale,shape])
			check(choice._popup_font!=Interface800.font() and choice._display_font!=Interface800.font(),"oversampling does not mutate the shared original font")
			await capture("network-dropdown-%s-%d"%[locale,shape.x]);choice.get_popup().hide()
	panel.free();get_window().size=Vector2i(1280,720);await frames()
	var background:=ColorRect.new();background.color=Color(.08,.075,.06);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var u:=GameUnit.new();w.add_child(u)
	check(u.setup(w,{"nid":123,"prototype":"Human Mercenary Kania Paladin"}),"Brissen uses his original authored model and equipment")
	var doll:=Paperdoll.new();doll.position=Vector2(70,30);doll.size=Vector2(480,650);doll.view_size=Vector2i(480,650);add_child(doll);doll.show_unit(u)
	var kit:=CampaignState.merc_kit({},u.proto)
	var index:=0
	for id:String in kit.armors:
		if not "[" in id:continue
		var cell:=ItemView.new();cell.position=Vector2(600,40+index*325);cell.size=Vector2(200,230);cell.camp=true;cell.fit_slot=true;add_child(cell);cell.show_item(id)
		var label:=Label.new();label.position=Vector2(820,100+index*325);label.size=Vector2(420,180);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",22);label.text=Items.title(id)+"\n"+Items.title(Items.plain(id));add_child(label)
		check(cell._model!=null and not label.text.contains("{"),"enchanted armor has a native item preview and clean description")
		index+=1
	await capture("brissen-armor")
	check("pl_01.st.2" in str(doll._model.get_meta("layers",[])),"character preview composes Brissen's steel plate layer")
	print("REPORTED_UI_VISUALS ",checks," checks ",failures," failures")
	w.queue_free();await frames();TexUpscale.shutdown();get_tree().quit(int(failures>0))
