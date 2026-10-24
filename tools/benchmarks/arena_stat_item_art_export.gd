extends Node
## Reproducible 256px transparent icons, rendered from the original game models.
const SOURCES := {"vitality": "dragonamulet", "blade": "long sword.iron", "haste": "gipat high boots.thin", "mail": "kania highest shirt.iron", "prism": "rightcrystal", "focus": "wand 3", "fang": "graywolfskin", "venom": "dragonpoison", "greatblade": "saber.steel", "ironheart": "elementallava00", "quicksilver": "gipat high gloves.thin", "runemail": "kania high plate.steel", "opal": "willowisp00", "staff": "wand 4", "ward": "cryptrune00", "thorn": "dragonshell00", "warhammer": "stone axe.rock", "bulwark": "kania highest plate.steel", "sage": "dcbook", "windrunner": "hadagan high boots.troll blue", "storm": "elementalice00", "guardian": "toy", "echo": "bansheerune00", "berserker": "ogrestuff", "bloodblade": "lizardclaw00", "stormheart": "beholderbigeye", "plague": "spidersting", "aegis": "golemcenterkey00", "mirror": "bansheerobe01", "archmage": "wand 6", "titan": "hadagan highest shirt.steel", "duelist": "unique sword.steel", "sunblade": "ancientsword", "worldheart": "driadidol00", "crown": "dragonwand", "starweave": "bansheerobe00", "bloodmoon": "zombie00", "thunderbolt": "palantir", "covenant": "unicornhorn00", "chronicle": "orcannals00"}
var output := "user://tier-item-art/"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--art-output="): output = arg.trim_prefix("--art-output=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 16: await get_tree().process_frame
	GameData._window_gen += 1
	Engine.max_fps = 30
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 720)
	get_tree().root.position = Vector2i.ZERO
	RemakeText.lang = "en"
	var manifest := {"source":"Original Cursed Lands figures.res and textures.res via Items.look and WikiPreview/ItemView", "renderer":"Godot 4.7 / OpenGL compatibility; unlit original item materials; 4x MSAA", "orientation":"Original ItemView camp orientation, zero WikiPreview turn; default fit_slot framing; no repainting or recoloring", "size":[256,256], "items":{}}
	var keys := SOURCES.keys()
	for page in ceili(keys.size() / 8.0):
		var sheet := Control.new()
		add_child(sheet)
		sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color("142027")
		sheet.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var previews := {}
		for index in mini(8, keys.size() - page * 8):
			var kind: String = keys[page * 8 + index]
			var preview := WikiPreview.new()
			preview.fit_slot = true
			preview.position = Vector2(80 + (index % 4) * 288, 28 + (index / 4) * 350)
			preview.size = Vector2(256, 256)
			sheet.add_child(preview)
			var look := Items.look(SOURCES[kind])
			if look.has("layer") and not GameData.redress.has("unhuma" + look.layer + ".mmp"):
				printerr("MISSING SKIN ", kind); get_tree().quit(1); return
			if look.is_empty() or not preview.show_model({"kind":"item", "value":SOURCES[kind]}):
				printerr("FAILED ", kind, " ", SOURCES[kind]); get_tree().quit(1); return
			preview.item._vp.msaa_3d = Viewport.MSAA_4X
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			previews[kind] = preview
			var label := Label.new()
			label.text = ArenaItems.title(kind) + "\n" + SOURCES[kind]
			label.position = preview.position + Vector2(0, 264)
			label.size = Vector2(256, 50)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", Color("d6c9ab"))
			label.add_theme_font_size_override("font_size", 17)
			sheet.add_child(label)
			await get_tree().process_frame
		for frame in 24: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		for kind: String in previews:
			var view: ItemView = previews[kind].item
			var image := view._vp.get_texture().get_image()
			if image.get_size() != Vector2i(256, 256) or image.get_used_rect().size == Vector2i.ZERO:
				printerr("BAD IMAGE ", kind); get_tree().quit(1); return
			if image.save_png(output + kind + ".png") != OK: get_tree().quit(1); return
			var q := view._model.quaternion
			var cam := view._fit_camera
			manifest.items[kind] = {"item_id":SOURCES[kind], "authored_title":Items.title(SOURCES[kind]), "look":Items.look(SOURCES[kind]), "model_quaternion_xyzw":[q.x,q.y,q.z,q.w], "wiki_turn_radians":0, "camera_size":cam.size, "camera_position":[cam.position.x,cam.position.y,cam.position.z], "camera_rotation_degrees":[cam.rotation_degrees.x,cam.rotation_degrees.y,cam.rotation_degrees.z], "transparent":view._vp.transparent_bg}
		get_viewport().get_texture().get_image().save_png("user://native-item-tier-%d.png" % (page + 1))
		print("NATIVE_ITEM_EXPORT tier=", page + 1)
		sheet.queue_free()
		await get_tree().process_frame
	FileAccess.open(output + "manifest.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("NATIVE_ITEM_EXPORT complete=", manifest.items.size(), " output=", output)
	get_tree().quit()
