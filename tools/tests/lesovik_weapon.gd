extends Node
## Authored creature attachments must survive world and portrait construction.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(n:=8)->void:
	for i in n:await get_tree().process_frame
func _ready()->void:_run.call_deferred()
func _run()->void:
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"display_mode":0},true)
	var count:=0
	for proto:Dictionary in GameData.db.table("monster_prototypes"):
		if proto.get("base_race","")!="Driad":continue
		count+=1
		for preview:bool in [false,true]:
			var model:=EIUnitModel.create({"prototype":proto.name},preview)
			add_child(model)
			var tube:=model.find_child("rh3_tube00",true,false) as EIAnimPart
			var box:=model.find_child("bd_box00",true,false) as EIAnimPart
			check(tube!=null and box!=null,"authored blowpipe and dart box exist: %s preview=%s"%[proto.name,preview])
			if tube:
				check(tube.animation_parent!=null and tube.animation_parent.name=="rh3" and not tube.get_children().is_empty(),"blowpipe mesh retains its original animated hand mount")
			model.free()
	check(count>=19,"all original lesovik clans and roles covered")
	var records:=0
	var mob:=EIMob.load_bytes(GameData.read_file("maps/zone11.mob"))
	for record:Dictionary in mob.objects:
		if record.get("template","")!="unmodr":continue
		var model:=EIUnitModel.create(record)
		check(model!=null and model.find_child("rh3_tube00",true,false)!=null,"original Ingos map record retains the blowpipe")
		if model:model.free()
		records+=1
	check(records>0,"original Ingos creature records covered")
	if DisplayServer.get_name()!="headless":
		RenderingServer.set_render_loop_enabled(true);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,720)
		var bg:=ColorRect.new();bg.color=Color(.08,.075,.06);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
		for i in 3:
			var prototype:String=["DriadDarkA9","DriadGreenA9","DriadSnowA9"][i]
			var doll:=Paperdoll.new();doll.position=Vector2(30+i*410,80);doll.size=Vector2(380,620);doll.view_size=Vector2i(380,620);add_child(doll);doll.show_info({"prototype":prototype})
			var label:=Label.new();label.position=Vector2(30+i*410,35);label.text=GameUnit.unit_title(prototype);label.add_theme_font_size_override("font_size",18);add_child(label)
		await frames(15);await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://lesovik-blowpipes.png")
	TexUpscale.shutdown();print("LESOVIK_WEAPON ",checks," checks ",failures," failures");get_tree().quit(int(failures>0))
