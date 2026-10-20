extends Node
## Real controls, original meshes and captured images for the October UI fixes.
var checks := 0
var failures: Array = []
var lang := "en"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func frames(n:=4) -> void:
	for i in n: await get_tree().process_frame
func shot(label: String) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://issues-"+lang+"-"+label+".png")==OK,"capture "+label)
func _ready() -> void:
	await frames(12)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-language="): lang=arg.get_slice("=",1)
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"display_mode":0,"pad_enabled":0},true)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1920,1080)
	RemakeText.lang=lang; await frames()
	var options := OptionsPanel.new(); add_child(options); options.open()
	options._show_group(OptionsPanel.INTERFACE_GROUP)
	await frames()
	for key in ["cursor_size","show_player_status","item_icon_fit"]:
		var rows: Array=options._rows.values().filter(func(row): return row.get("name","")==key)
		check(rows.size()==1,key+" is reachable from interface settings")
		if rows.is_empty(): continue
		var row: Dictionary=rows[0]
		check(options.text_width(row.label)<=260.0,key+" label fits its actual row")
		for value in int(row.max):
			options._values[key]=value
			check(options.text_width(options._switch_text(row))<=160.0,key+" choice fits its actual row")
			check(options._switch_text(row)==RemakeText.t(GameData.DISPLAY_CHOICES[key][value]),key+" choice uses the selected UI language")
		check(not row.tip.is_empty(),key+" has help")
	options._values.cursor_size=1
	options.queue_redraw()
	await shot("options")
	options.free(); await frames()
	var s := Session.new(); add_child(s); var g := Game.new(); g.session=s
	s.online=true
	s.players={1:{"index":0,"name":"Local player"},2:{"index":1,"name":"Guest"}}
	var status := PlayerList.new(); status.game=g; add_child(status)
	GameData.options.show_player_status=1; status._process(0)
	check(status.visible,"player status is visible when enabled")
	GameData.options.show_player_status=0; status._process(0)
	check(not status.visible,"player status can be hidden immediately")
	GameData.options.show_player_status=1; status._process(0)
	check(status.visible,"player status can be restored")
	status.free();g.free();s.free()
	GameData.options.item_icon_fit=1
	var panel := MpCharPanel.new(); add_child(panel); panel.open()
	panel._press(["new"]); await frames(10)
	check(panel.state==MpCharPanel.CREATE and panel._cells.size()==14,"real character creation shows both face strips")
	await shot("creation-fit")
	# Visit every authored head, including extreme builds, in the real cells.
	for gender in 2:
		for first in range(0,panel.faces[gender].size(),MpCharPanel.CELLS):
			panel.face_top[gender]=first;panel._layout_faces();await frames(2)
			for cell in panel._cells.slice(gender*MpCharPanel.CELLS,(gender+1)*MpCharPanel.CELLS):
				if not cell.visible: continue
				var p: Portrait=cell
				p.set_process(false)
				check(p.fit_cell and p._face_cam!=null,"creation head uses the fitting camera")
				if p._face_cam==null: continue
				for pitch in [-.16,0.0,.36]:
					for yaw in [-.16,.16]:
						var q:=Quaternion(Vector3.RIGHT,pitch)*Quaternion(Vector3.UP,yaw)
						p._model.quaternion=EISpace.quat(q.w,q.x,q.y,q.z)
						var inside:=true
						for mesh: MeshInstance3D in p._model.find_children("*","MeshInstance3D",true,false):
							for vertex: Vector3 in mesh.mesh.get_faces():
								if not Rect2(Vector2.ONE,Vector2(p._vp.size)-Vector2.ONE*2).has_point(p._face_cam.unproject_position(mesh.global_transform*vertex)):
									inside=false;break
						check(inside,"whole head fits while turning: "+p._key)
	panel._close(false);panel.free();await frames()
	# Fixed authored pixel scale is a ceiling, not a request to fill the cell.
	var ids: Array[String]=["bp:battle axe","battle axe.adamantium","material.bronze"]
	for row: Dictionary in GameData.db.table("weapons"):
		if row.type=="bow":
			var materials:=Items.materials_for("bp:"+String(row.name).to_lower())
			if not materials.is_empty():
				ids.append(String(row.name).to_lower()+"."+String(materials[0].name).to_lower());break
	var views: Array[ItemView]=[]
	for i in ids.size():
		var v:=ItemView.new();v.camp=true;v.fit_slot=true;v.unit_px=67.5
		v.size=Vector2(144,144);v.position=Vector2(240+i*300,300)
		add_child(v);v.show_item(ids[i]);v.set_process(false);views.append(v)
		check(v._model!=null and v._fit_camera!=null,"original preview loads: "+ids[i])
		if v._fit_camera==null:continue
		var zoom:=v._fit_camera.size
		check(zoom>=v.size.y/v.unit_px,"fit never enlarges a small authored item: "+ids[i])
		v.spin=true
		for sample in 48:
			v._process(.1)
			var inside:=true
			for point: Vector3 in v._fit_points:
				if not Rect2(Vector2.ZERO,Vector2(v._vp.size)).has_point(v._fit_camera.unproject_position(v._model.global_transform*point)):
					inside=false;break
			check(inside,"rotating item stays inside cell: "+ids[i])
		check(is_equal_approx(v._fit_camera.size,zoom),"turning does not pulse the item scale: "+ids[i])
	await shot("items")
	for v in views: v.free()
	print("ISSUE_UI_RENDERED ",JSON.stringify({"checks":checks,"failures":failures,"language":lang}))
	TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
