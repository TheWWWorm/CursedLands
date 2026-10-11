extends Node
var failures:=0
var checks:=0
var out:="user://feedback-visuals"
class InfoPreview extends CampView:
	var rects: Array[Rect2] = []
	var item := "spell:strength{d1;d1}"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.11,0.10,0.08))
		rects.clear()
		_draw_item_info(300,item)
		_t(Rect2(315,410,170,20),"Навыки/Заклинания")
	func _t(r: Rect2, txt: String, fi := 0, col := Interface800.TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		if not txt.is_empty(): rects.append(Rect2(r.position,Vector2(r.size.x,_lh(fi))))
		super._t(r,txt,fi,col,align)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(n:=4)->void:
	for i in n:await get_tree().process_frame
func shot(name:String)->void:
	await frames(8);await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(out.path_join(name+".png"))==OK,"capture "+name)
class RuneCards extends Control:
	func _draw()->void:
		for i in 4:
			var code: String=["healing{e0;m1}","strength{d1;d1}","fireball{e1;e1;r1;r1;a1;a1;m1;m1}","healing"][i]
			var rect:=Rect2(40+i*200,20,150,150)
			var p:=Spells.parse(code)
			var icon:=SpellSlots.icon("spell%04d"%int(p.proto.get("texture_type",0)))
			if icon:draw_texture_rect(icon,rect,false)
			SpellSlots.draw_runes(self,code,rect)
			draw_string(Interface800.font(),rect.position+Vector2(0,180)," ".join(Array(Spells.mods_of(code)).map(func(s):return Spells.mod_short_title(s))),HORIZONTAL_ALIGNMENT_LEFT,-1,22)
func _ready()->void:_run.call_deferred()
func _run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"confine_mouse":0,"vsync":0},true)
	GameData.resolution_size="1920x1080";GameData.options.resolution=GameData.resolutions().find(Vector2i(1920,1080))
	GameData._apply_window()
	Engine.max_fps=60;RenderingServer.set_render_loop_enabled(true)
	await frames(8)
	get_tree().root.mode=Window.MODE_WINDOWED;get_tree().root.size=Vector2i(1920,1080)
	await frames(4)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	RemakeText.lang="ru"
	var panel:=DifficultyPanel.new();add_child(panel);panel.open(false)
	await shot("setup-ru")
	panel._mods_button.pressed.emit();await frames(4)
	var stamina_row:Control
	for row:BoxContainer in panel._mods._rows:
		var label:Label=row.get_child(0).get_child(0)
		if label.text==RemakeText.t("Always regenerate stamina"):stamina_row=row
	check(stamina_row!=null,"localized stamina option appears in game setup")
	if stamina_row:
		panel._mods._scroll.ensure_control_visible(stamina_row)
		await shot("stamina-rule-ru")
		check(panel._mods._body.size.x<=panel._mods._scroll.size.x,"long translated rule descriptions fit the dialog")
	panel.queue_free();await frames()
	for locale in ["ru","de"]:
		RemakeText.lang=locale
		var rules:=ModPanel.new();add_child(rules);rules.open("rules")
		await shot("rules-"+locale)
		rules.free();await frames()
	RemakeText.lang="ru"
	var info:=InfoPreview.new();info.size=Vector2(1440,1080);info.position=Vector2(240,0);add_child(info)
	for item:String in ["spell:strength{d1;d1}","spell:fireball{e1;e1;r1;r1;a1;a1;m1;m1}","gipat medium plate.thin"]:
		info.item=item;info.queue_redraw();await frames()
		var bottom:=0.0;var fits:=true
		for rect:Rect2 in info.rects:
			if rect.position.y<bottom-0.01:fits=false
			bottom=rect.end.y
		check(fits,"all rendered item text rows remain separate: "+item)
		await shot("item-info-"+str(info.item.hash()))
	info.free()
	var cards:=RuneCards.new();cards.position=Vector2(200,35);add_child(cards)
	var ids: Array[String]=[]
	for row:Dictionary in GameData.db.table("weapons"):
		if String(row.name).to_lower().contains("bow"):
			var materials:=Items.materials_for("bp:"+String(row.name).to_lower())
			ids.append(String(row.name).to_lower()+("."+String(materials[0].name).to_lower() if not materials.is_empty() else ""))
			if ids.size()==3:break
	ids.append_array(["material.thin","material.bronze","tiny potion 1"])
	var views:Array[ItemView]=[]
	for i in ids.size():
		var cell:=ColorRect.new();cell.color=Color(.15,.13,.10);cell.position=Vector2(80+i*230,360);cell.size=Vector2(210,210);add_child(cell)
		var v:=ItemView.new();v.camp=true;v.fit_slot=true;v.size=Vector2(210,210);cell.add_child(v);v.show_item(ids[i]);views.append(v)
		var label:=Label.new();label.text=ids[i];label.position=cell.position+Vector2(0,218);label.add_theme_font_size_override("font_size",16);add_child(label)
		check(v._model!=null,"preview original item "+ids[i])
	await shot("runes-items")
	for v:ItemView in views:
		if v._model==null:continue
		v.spin=true;v.set_process(false)
		var camera_size:=v._fit_camera.size
		var camera_position:=v._fit_camera.position
		var stable:=true
		for i in 32:
			v._process(.055)
			stable=stable and is_equal_approx(camera_size,v._fit_camera.size) and camera_position.is_equal_approx(v._fit_camera.position)
			await frames(1)
			var rect:=Rect2(Vector2.ZERO,v._vp.size)
			for p:Vector3 in v._fit_points:
				if not rect.has_point(v._fit_camera.unproject_position(v._model.global_transform*p)):
					print("FIT_DETAIL ",v.item," view=",v._vp.size," camera=",v._fit_camera.size," position=",v._fit_camera.position," point=",v._model.global_transform*p," screen=",v._fit_camera.unproject_position(v._model.global_transform*p))
					check(false,"rotating item fits cell: "+v.item);break
		check(v._fit_camera.size>0,"rotating item has a valid fit: "+v.item)
		check(stable,"hover rotates without zoom pulsing: "+v.item)
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false)
	var human:=GameUnit.new();world.add_child(human)
	var human_ok:=human.setup(world,{"nid":124,"prototype":"Human Hero"})
	check(human_ok,"ordinary human preview model loads")
	if not human_ok: get_tree().quit(1); return
	var human_doll:=Paperdoll.new();human_doll.exe_rect=UnitPanel.FIG;human_doll.view_size=Vector2i(320,440);human_doll.position=Vector2(1220,610);human_doll.size=Vector2(320,440);add_child(human_doll);human_doll.show_unit(human)
	await frames()
	var native_scale:=1.0/float(GameData.db.find("monster_prototypes","Human Hero").get("info_scale",1.0))
	check(is_equal_approx(human_doll._pivot.basis.get_scale().x,native_scale),"ordinary character retains original authored preview scale")
	var names:Array[String]=[]
	for row:Dictionary in GameData.db.table("monster_prototypes"):
		if String(row.name).to_lower().contains("troll") and String(row.name).to_lower().contains("black"):names.append(row.name)
	check(not names.is_empty(),"original black troll prototype exists")
	if not names.is_empty():
		var unit:=GameUnit.new();world.add_child(unit)
		check(unit.setup(world,{"nid":123,"prototype":names[0]}),"black troll model loads")
		var doll:=Paperdoll.new();doll.exe_rect=UnitPanel.FIG;doll.view_size=Vector2i(320,440);doll.position=Vector2(820,610);doll.size=Vector2(320,440);add_child(doll);doll.show_unit(unit)
		await frames(4)
		var bounds:=Rect2(Vector2(0,0),Vector2(doll._vp.size))
		var inside:=true
		for mi:MeshInstance3D in doll._model.find_children("*","MeshInstance3D",true,false):
			if mi.mesh==null or not doll._shown_part(mi):continue
			for point:Vector3 in mi.mesh.get_faces():
				if not bounds.has_point(doll._cam.unproject_position(mi.global_transform*point)):inside=false
		check(inside,"large creature stays inside the preview")
		await shot("large-creature")
	world.queue_free()
	print("FEEDBACK_VISUALS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
