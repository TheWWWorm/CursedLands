extends Node
var faces: Array[Portrait]=[]
func _ready()->void:
	DisplayServer.window_set_size(Vector2i(1000,540))
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var u:=w.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(1,1,0)})
	u.set_process(false);u.set_physics_process(false)
	for i in 3:
		var p:=Portrait.new();add_child(p)
		var small:=i==2
		var rect:=Rect2(378,525,34,57) if small else Rect2(375,513,50,69)
		p.size=rect.size*4;p.position=Vector2(120+i*300,80)
		p.set_exe_place(rect,395 if small else 400,0.2 if small else 0.3,557 if small else 548)
		p.show_unit(u);p.selected=i==0;p.set_process(false)
		p._head_motion=0;p._update_head(0);p._selection_q=Quaternion(Vector3.LEFT,PI/14) if p.selected else Quaternion.IDENTITY;p._update_head(0)
		faces.append(p)
	for i in 12:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://portrait-proportions.png")
	for i in 3:
		print("PORTRAIT ",i," viewport ",faces[i]._vp.size," display ",faces[i].size," pivot scale ",faces[i]._pivot.scale," model scale ",faces[i]._model.scale)
		faces[i]._vp.get_texture().get_image().save_png("user://portrait-%d.png"%i)
	get_tree().quit()
