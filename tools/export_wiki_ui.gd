extends Node
## Original camp workbench frames, shared by the native and static planners.
func _ready() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-ui-output="): output=arg.trim_prefix("--wiki-ui-output=")
	if output.is_empty():get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	for asset: String in ["panel","weapon","quick","spell","bag","stock","button"]:
		WikiCampArt.texture(asset).get_image().save_webp(output.path_join("camp-"+asset+".webp"),true)
	for family: String in ["constrspell","constritem","camp"]:
		var board := Image.create(400,400,false,Image.FORMAT_RGBA8)
		for quadrant in 4:
			var image := WikiCampArt.crop(family+str(quadrant+1),Rect2i(28,28,200,200))
			if image==null:get_tree().quit(1);return
			board.blit_rect(image,Rect2i(0,0,200,200),Vector2i((quadrant%2)*200,(quadrant/2)*200))
		board.save_webp(output.path_join("workbench-"+family+".webp"),true)
	var slots := GameData.load_image("campslots")
	if slots:
		slots.flip_y()
		slots.get_region(Rect2i(14,14,100,100)).save_webp(output.path_join("slot-weapon.webp"),true)
		slots.get_region(Rect2i(142,14,100,100)).save_webp(output.path_join("slot-quick.webp"),true)
	for row: Dictionary in GameData.db.table("spell_prototypes"):
		var code := String(row.code).to_lower()
		var look := Items.look("keystone:"+code)
		var icon := GameData.load_image(look.get("texture",""))
		if icon:
			icon.flip_y();icon.save_webp(output.path_join("keystone-"+GameData.campaign_id+"-"+code.uri_encode()+".webp"),true)

	print("WIKI_UI exported original camp frames")
	get_tree().quit()
