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
	GameData.options.merge({"auto_graphics":0,"display_mode":0},true)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED
	await frames()
	get_window().position=Vector2i(100,100)
	var panel:=WikiPanel.new();add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.open();await frames()
	var target:="";var map_key:=""
	for key:String in panel.catalog.knowledge.pins:
		var pins:Array=panel.catalog.knowledge.pins[key]
		if not key.begins_with("map/"):continue
		for pin:Dictionary in pins:
			if pin.kind=="inhabitant" and String(pin.key).contains("toad"):
				target=pin.key;map_key=key;break
		if not target.is_empty():break
	check(not target.is_empty(),"authored toad locations found")
	panel.navigate(target);await frames()
	panel.follow_link("wiki://"+map_key);await frames()
	check(panel.current==map_key and panel._map_kinds.inhabitant,"creature link opens map with creatures enabled")
	check(panel._map_checks.inhabitant.button_pressed,"creature toggle agrees with visible markers")
	check(panel._preview.map_highlight==target,"linked creature is highlighted")
	var highlighted:=0;var plain:=0
	for pin in panel._preview.map_view.get_children():
		if pin is WikiPreview.MapPin:
			if pin.highlighted:highlighted+=pin.count
			else:plain+=1
	var expected:=panel._map_pins.filter(func(pin):return pin.kind=="inhabitant" and pin.key==target).size()
	check(highlighted==expected and plain>0,"every linked creature is highlighted without tinting unrelated markers")
	var term:=String(panel.catalog.entries[target].title)
	panel._map_search.text=term.to_upper();panel._map_search.text_changed.emit(panel._map_search.text);await frames()
	check(panel._preview._pins.all(func(pin):return pin.kind!="inhabitant" or term.to_lower() in String(pin.title).to_lower()),"name search filters translated names case-insensitively")
	var non_creatures:=panel._preview._pins.filter(func(pin):return pin.kind!="inhabitant").size()
	panel._map_search.text="no such creature 192847";panel._map_search.text_changed.emit(panel._map_search.text);await frames()
	check(panel._preview._pins.size()==non_creatures,"unmatched search preserves exits and quests")
	panel._map_search.text="";panel._map_search.text_changed.emit("");await frames()
	check(panel._preview._pins.size()==panel._map_pins.size(),"clearing the filter restores creature markers")
	panel.navigate("home");await frames();await panel.history(-1);await frames()
	check(panel._preview.map_highlight==target,"Back restores the creature highlight")
	if DisplayServer.get_name()!="headless":
		for size_:Vector2i in [Vector2i(1280,800),Vector2i(720,1280)]:
			get_window().size=size_;await frames(8);await RenderingServer.frame_post_draw
			check(get_window().size==size_,"physical window matches requested layout")
			get_viewport().get_texture().get_image().save_png("user://wiki-creature-map-%dx%d.png"%[size_.x,size_.y])
	panel.navigate("home");panel.navigate(map_key);await frames()
	check(panel._preview.map_highlight.is_empty(),"unrelated map navigation clears previous highlight")
	panel.queue_free();await frames();TexUpscale.shutdown()
	print("WIKI_CREATURE_MAP ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
