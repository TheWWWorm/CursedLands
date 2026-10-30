extends Node
## Lost in Astral's signpost: the skull in the middle becomes the Multiplayer
## board as in the original, with a localized caption, a click area (the base
## game's menus.reg rectangle), hover and the network screen. The base game's
## own Multiplayer board and label artwork stay untouched.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ", message)

func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame

func caption_of(root: Node) -> Label3D:
	return root.find_child(MenuMultiplayerBoard.NAME, true, false) as Label3D

func board_mesh(root: Node) -> MeshInstance3D:
	var node := root.find_child(MenuMultiplayerBoard.PART, true, false)
	if node == null: return null
	for child in node.get_children():
		if child is MeshInstance3D: return child
	return null

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0, "display_mode":0}, true)
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(2560, 1440)
	await frames(6)
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	check(MenuMultiplayerBoard.needed() == astral, "only LiA's signpost lacks the Multiplayer board")
	var rect: Rect2 = MenuScene.reg_rects()[5]
	check(rect.size != Vector2.ZERO, "the Multiplayer click area exists")
	if astral: check(rect == MenuMultiplayerBoard.REG_RECT, "LiA uses the original's Multiplayer rectangle")
	for lang: String in ["en", "ru", "de"]:
		RemakeText.lang = lang
		var menu := preload("res://src/ui/main_menu.gd").new()
		menu.detect_graphics = false; add_child(menu)
		await frames(30)
		var scene: MenuScene = menu._scene
		check(scene != null, lang + " menu island built")
		if scene == null: continue
		var label := caption_of(scene)
		var mesh := board_mesh(scene)
		check(mesh != null, lang + " middle part has a mesh")
		if not astral:
			check(label == null, "base game keeps its own board without a remake caption")
			check(mesh != null and mesh.mesh.get_aabb().size.x > 1.5, "base game Multiplayer board present")
		else:
			check(label != null and label.text == RemakeText.t("Multiplayer").to_upper(), lang + " caption is localized: " + (label.text if label else ""))
			check(RemakeText.t("Multiplayer") != "Multiplayer" or lang == "en", lang + " Multiplayer has a translation")
			check(mesh != null and mesh.mesh.get_aabb().size.x > 1.8, lang + " skull replaced by a full-width board")
			check(label != null and label.shaded, lang + " caption shares the island lighting")
			if label:
				var font: Font = label.font
				var size := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size) * label.pixel_size
				check(size.x <= MenuMultiplayerBoard.TEXT_SIZE.x + 0.001 and size.x > 0.3, lang + " caption fits the face width %.3f" % size.x)
				check(font.get_height(label.font_size) * label.pixel_size <= MenuMultiplayerBoard.TEXT_SIZE.y + 0.001, lang + " caption fits the face height")
		# Click area, hover clip and the network screen.
		var board := scene.board_rect(MenuMultiplayerBoard.PART)
		check(board.size.x > 100 and scene.board_at(board.get_center()) == MenuMultiplayerBoard.PART, lang + " pointer picks the Multiplayer board")
		check(scene.pad_targets().any(func(t): return t.id == "multiplayer"), lang + " gamepad reaches the Multiplayer board")
		scene._set_hover(MenuMultiplayerBoard.PART); await frames(10)
		check(scene._player.assigned_animation == "ei/uspecial09", lang + " hover plays the board's original clip")
		scene._set_hover("")
		check(not ("_coop_button" in menu), lang + " no duplicate co-op button")
		await menu._on_board("multiplayer"); await frames(10)
		check(menu._net.visible, lang + " Multiplayer opens the network screen")
		if astral:
			check(caption_of(menu._net._board) != null, lang + " network screen board shows the same caption")
		menu.queue_free(); await frames(4)
	if astral:
		# The painted Authors letters are gone from the copy, the native skin is unchanged.
		var native := GameData.get_texture("mainmenu00").get_image()
		var blank := MenuMultiplayerBoard.skin().get_image()
		if native.is_compressed(): native.decompress()
		var changed := 0
		var outside := 0
		var k := native.get_width() / 256
		for y in native.get_height():
			for x in native.get_width():
				if native.get_pixel(x, y).is_equal_approx(blank.get_pixel(x, y)): continue
				if Rect2i(MenuMultiplayerBoard.LETTERS.position * k, MenuMultiplayerBoard.LETTERS.size * k).has_point(Vector2i(x, y)): changed += 1
				else: outside += 1
		check(changed > 200, "painted caption letters replaced (%d px)" % changed)
		check(outside == 0, "the rest of the skin is untouched")
	print("MENU_MULTIPLAYER_BOARD ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
