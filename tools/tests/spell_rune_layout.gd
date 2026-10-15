extends Node
## Actual shops, gameplay spell bar and settings, with both layouts and all
## translations. Original coordinates are derived from executable 005eca10.
class FixtureSession extends Session:
	var shop_fixture := false
	func shop_available() -> bool: return shop_fixture

var checks := 0
var failures := 0
var panel: OptionsPanel

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://" + name + ".png") == OK, "capture " + name)

func click(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		event.position = panel._origin() + at * panel.kv()
		panel._gui_input(event)

func option_row() -> int:
	for row: int in panel._rows:
		if panel._rows[row].name == "original_rune_layout": return row
	return -1

func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(GameData.option("original_rune_layout") == 0, "fresh settings default to compact clusters")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0}, true)
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW), true)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var s := FixtureSession.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz21k" if GameData.campaign_id == CampaignProfile.ASTRAL else "gz1g", 1, false)
	s.set_physics_process(false); s.world.set_physics_process(false); s.world.set_process(false)
	s.world.vm.briefings._check = INF; g.hud._dialog.hide()
	var spells := ["spell:lightning{e1;e1;m1;m1;m1;m1;m1;m1}", "spell:inv_lit{m1;m1;m1;m1;m1;m1;m1;m1}", "spell:healing{e1;e1;m1;m1;m1}", "spell:strength{d1;d1;d1;m1;m1}"]
	s.state.items = []; s.state.money = 10000000; s.state.shops[3] = {"restock":false,"goods":{},"sold":{}}
	for i in spells.size():
		s.state.shops[3].goods[spells[i]] = [1,2,123,9][i]
		for j in [1,2,12,9][i]: s.state.items.append(spells[i])
	var hero := s.party_units(0)[0] as GameUnit
	var h: Dictionary = hero.get_meta("hero")
	h.spells = spells.map(func(sp: String): return Items.spell_code(sp))
	g.selected.assign([hero])
	s.shop_fixture = true
	var inventory: InventoryPanel = g.hud._inventory
	inventory.open(true, 3)
	var camp: CampView = inventory._camp
	camp.set_mode("spelltrade"); camp._update_hover(Vector2(10,300))
	var archives := {RemakeText.lang:GameData.texts}
	for arg: String in OS.get_cmdline_user_args():
		for language: String in ["en","ru","de"]:
			if arg.begins_with("--" + language + "-texts="): archives[language] = EIResArchive.open_path(arg.get_slice("=",1))
	panel = OptionsPanel.new(); g.hud.add_child(panel)
	var native_centres := [Vector2(50,25.1688),Vector2(74.8312,25.1688),Vector2(74.8312,50),Vector2(74.8312,74.8312),Vector2(50,74.8312),Vector2(25.1688,74.8312),Vector2(25.1688,50),Vector2(25.1688,25.1688)]
	for language: String in archives:
		GameData.texts = archives[language]; EIText.code_page = EIText.detect_code_page(GameData.texts)
		RemakeText.lang = RemakeText.detect(GameData.texts); GameData._text_cache.clear()
		check(RemakeText.lang == language, "correct text archive " + language)
		for resolution: Vector2i in [Vector2i(800,600),Vector2i(1600,900)]:
			get_window().content_scale_size = resolution; await frames()
			for style in [0,1]:
				GameData.options.original_rune_layout = style
				camp._process(0.0); await frames()
				for key: String in ["shop0","bag0","buy0","sell0","sready"]:
					var previous: Array = camp._content.get(key, ["",""])
					camp._content[key] = [spells[0], "buy"]
					for count in [1,2,12,123,9999]:
						camp.buy_pile.assign(Array()); camp.buy_pile.resize(count); camp.buy_pile.fill(spells[0])
						var slot := camp._slot_rect(key)
						var cells := camp._spell_rune_rects(key)
						check(cells.size() == 8, "eight visible runes " + key)
						if style == 1:
							var bottom_y := cells[4].position.y
							var price_y := camp._r(Rect2(slot.position + Vector2(15,CampView._price_offset(spells[0])),Vector2(70,20))).position.y
							check(price_y + Interface800.font().get_height(camp._fpx(1)) + camp._s() < bottom_y, "price and shadow finish above bottom runes " + key)
							for i in cells.size():
								var expected := camp._r(Rect2(slot.position + native_centres[i] - Vector2.ONE * 7.2916667, Vector2.ONE * 14.5833333))
								check(cells[i].position.distance_to(expected.position) < 0.001 and cells[i].size.distance_to(expected.size) < 0.001, "native rune position " + key)
						else:
							var price := camp._r(Rect2(slot.position + Vector2(15,65),Vector2(70,20)))
							var qty := camp._r(Rect2(slot.position + Vector2(15,15),Vector2(70,20)))
							var width := Interface800.font().get_string_size(str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,camp._fpx(1)).x + 2
							qty.position.x = qty.end.x - width; qty.size.x = width
							check(cells.all(func(cell: Rect2): return not cell.intersects(price)), "cluster clears price " + key)
							check(count == 1 or cells.all(func(cell: Rect2): return not cell.intersects(qty)), "cluster clears stack " + key)
					camp._content[key] = previous
				camp.buy_pile.clear(); camp._sig = ""; camp._process(0.0)
				check(camp._overlay.get_index() > camp._pile_clip.get_index(), "text drawn over item art")
				await frames(); await capture("runes-" + language + "-" + str(resolution.x) + "-" + str(style))
				inventory.hide(); s.shop_fixture = false; await frames()
				check(g.hud._slots.is_visible_in_tree() and g.hud._slots._entries.size() == 4, "gameplay spell bar retains all four spells")
				check(SpellSlots.rune_icons(h.spells[0]).size() == 8, "gameplay spell retains eight rune textures")
				await capture("world-runes-" + language + "-" + str(resolution.x) + "-" + str(style))
				s.shop_fixture = true; inventory.show()
			panel.open(); panel._show_group(OptionsPanel.INTERFACE_GROUP); await frames()
			var row := option_row()
			check(row >= 0, "rune layout option appears in Interface and controls")
			if row >= 0:
				var label: String = panel._rows[row].label
				var tip: String = panel._rows[row].tip
				check(label == RemakeText.t("Original rune layout"), "localized option label " + language)
				check(language == "en" or (label != "Original rune layout" and not tip.contains("Arrange spell runes")), "localized help " + language)
				check(Interface800.font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,panel.font_px(1)).x <= 260 * panel.kv().x, "option label fits " + language)
				await capture("rune-option-" + language + "-" + str(resolution.x))
				click(Vector2(590,168+24*row)); click(Vector2(250,550))
				var cfg := ConfigFile.new()
				check(GameData.option("original_rune_layout") == 0 and cfg.load(GameData.CONFIG_PATH) == OK and cfg.get_value("options","original_rune_layout",-1) == 0, "disabled choice persists")
				panel.open(); panel._show_group(OptionsPanel.INTERFACE_GROUP)
				check(panel._values.original_rune_layout == 0, "reopened settings retain compact choice")
				click(Vector2(590,168+24*row)); click(Vector2(250,550)); cfg.load(GameData.CONFIG_PATH)
				check(GameData.option("original_rune_layout") == 1 and cfg.get_value("options","original_rune_layout",-1) == 1, "original choice persists")
			panel.hide()
	print("SPELL_RUNE_LAYOUT ", checks, " checks ", failures, " failures")
	FileAccess.open("user://spell-rune-layout.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"languages":archives.keys(),"layouts":["compact_default","original_optional"]},"  "))
	g.queue_free(); s.queue_free(); await frames(2); get_tree().quit(1 if failures else 0)
