extends Node
## Real map hit testing and original localized unit previews.
var checks:=0
var failures:=[]
var chosen:={}
var text_roots:={}
class PreviewPanel extends UnitPanel:
	var subject:GameUnit
	func _pick() -> GameUnit:return subject
	func _k() -> float:return 2.0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func frames(n:=4) -> void:
	for i in n:await get_tree().process_frame
func capture(name:String) -> void:
	await frames(5);await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://"+name+".png")
func _ready() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--texts-"):
			text_roots[arg.trim_prefix("--texts-").get_slice("=",0)]=arg.get_slice("=",1)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"display_mode":0,"control_mode":1,"gfx_detailed_heads":0},true)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1000,750);Engine.max_fps=60
	var s:=Session.new();add_child(s);s.state=CampaignState.new();s.zone_id="bz2g"
	for id:String in s.campaign.zones:s.state.set_var(0,"z."+id,2)
	var options:=s._route_options("gz2g_bz2g")
	check(options.any(func(o):return o.zone=="gz2g") and options.any(func(o):return o.zone=="bz2g"),"original route graph offers field and healer cave")
	var map:=TravelMap.new();map.setup(s,options,true,"gz2g_bz2g");add_child(map);await frames(8)
	var piece:=map._piece_of("gz2g");var cave:=-1
	for i in map._briefs.size():
		if map._briefs[i].id=="bz2g":cave=i
	check(piece>=0 and cave>=0,"original map loads healer field and cave figures")
	var field_point:=Vector2.INF;var cave_point:=Vector2.INF
	if piece>=0 and cave>=0:
		check(map._pieces[piece].link<0,"completed healer field stays independent of the cave")
		var bounds:Rect2=map._screen_rect(map._pieces[piece].node)
		for y in range(int(bounds.position.y),int(bounds.end.y),3):
			for x in range(int(bounds.position.x),int(bounds.end.x),3):
				var p:=Vector2(x,y)
				if map._button_at(p)==cave+3:cave_point=p
				elif map._button_at(p)<0 and map._piece_at(p)==piece:field_point=p
				if field_point!=Vector2.INF and cave_point!=Vector2.INF:break
			if field_point!=Vector2.INF and cave_point!=Vector2.INF:break
		check(field_point!=Vector2.INF and cave_point!=Vector2.INF,"both destinations have distinct clickable pixels")
		if field_point!=Vector2.INF:
			map._on_move(field_point);check(not map._hover_brief and map._last_name=="gz2g","field hover names the outdoor area")
			map._on_press(field_point)
			check(map.objectives!=null and map.objectives.zone=="gz2g" and map.objectives.entrance>=0,"field click opens its usable outdoor entrance")
			map.close_objectives()
		if cave_point!=Vector2.INF:
			map.picked.connect(func(o):chosen=o)
			map._on_press(cave_point);check(chosen.get("zone","")=="bz2g","cave click selects the healer directly")
		await capture("healer-destinations")
	map.free();s.queue_free();await frames()
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false)
	for lang:String in ["en","ru","de"]:
		check(text_roots.has(lang),"original text archive supplied: "+lang)
		if not text_roots.has(lang):continue
		GameData.texts=EIResArchive.open_path(text_roots[lang]);GameData._text_cache.clear();EIText.code_page=EIText.detect_code_page(GameData.texts);RemakeText.lang=RemakeText.detect(GameData.texts)
		for proto:String in ["DragonBlueM14","TrollBlackSlowF16","Human Hero"]:
			var u:=GameUnit.new();world.add_child(u);check(u.setup(world,{"nid":123,"prototype":proto}),"load "+proto+" / "+lang)
			u.set_process(false);u.set_physics_process(false);u.model.set_process(false);u.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;u.model.player.seek(0,true);u.model.flush_pending_pose()
			var panel:=PreviewPanel.new();panel.subject=u;add_child(panel);await frames(8)
			var doll:Paperdoll=panel._doll
			var scale:=float(u.proto.info_scale)
			check(is_equal_approx(doll._pivot.basis.get_scale().x,1.0/scale),"native info_scale preserved: "+proto+" / "+lang)
			var pose:=doll._pivot.transform
			for phase:float in [.1,.7]:
				u.model.player.seek(phase*u.model.player.current_animation_length,true);u.model.flush_pending_pose();await frames(3)
				check(doll._pivot.transform.is_equal_approx(pose),"animation does not shrink preview: "+proto+" / "+lang)
			var width:=Interface800.font().get_string_size(u.display_name,HORIZONTAL_ALIGNMENT_LEFT,-1,panel._name_fit_size).x
			check(width<=300 and not u.display_name.is_empty(),"localized full name fits: "+u.display_name)
			await capture("preview-"+lang+"-"+proto.replace(" ","_"))
			panel.free();u.free()
	world.free();TexUpscale.shutdown()
	FileAccess.open("user://travel-preview.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("TRAVEL_PREVIEW ",checks," checks ",failures.size()," failures ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
