extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:_run.call_deferred()
func _run()->void:
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"confine_mouse":0,"show_tutorial":0},true)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1280,720);RenderingServer.set_render_loop_enabled(true)
	var bg:=ColorRect.new();bg.color=Color(.08,.075,.06);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false)
	var unit:=GameUnit.new();world.add_child(unit)
	var sword:="unique sword.bronze|litnwall{it}@0~7"
	check(unit.setup(world,{"nid":123,"prototype":"Human Hero","weapons":[sword]}),"original hero equips existing bronze Ancient Sword")
	var doll:=Paperdoll.new();doll.position=Vector2(50,20);doll.size=Vector2(430,650);doll.view_size=Vector2i(430,650);add_child(doll);doll.show_unit(unit)
	var ids:=[sword,"unique spear.bronze|weak{it}","uniquegipathadagan plate.steel|strength{ic}","uniqueingos helm.bronze|healing{ic}"]
	for i in ids.size():
		var id:String=ids[i]
		var cell:=ItemView.new();cell.position=Vector2(510+(i%2)*360,30+(i/2)*330);cell.size=Vector2(230,240);cell.camp=true;cell.fit_slot=true;add_child(cell);cell.show_item(id)
		var label:=Label.new();label.position=cell.position+Vector2(-5,245);label.size=Vector2(335,90);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",19);label.text=Items.title(id);add_child(label)
		check(cell._model!=null and not "unique" in label.text.to_lower(),"localized special equipment preview "+str(i))
		var texture:=EIUnitModel._compose("unhuma",[String(Items.look(id).layer)] as Array[String])
		check(texture!=null,"special equipment has textured pixels "+str(i))
	for i in 20:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://special-equipment.png")
	world.queue_free()
	for i in 6:await get_tree().process_frame
	print("SPECIAL_EQUIPMENT_VISUALS ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(int(failures>0))
