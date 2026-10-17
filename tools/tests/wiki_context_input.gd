extends "arena_expansion_ui.gd"
## Real key dispatch and pointer hit testing, including the native camp UI.
var session: Session
var game: Game
var camp: CampView

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = down
		get_viewport().push_input(event)
	await frames()

func hovered_item(id: String, mode: String, where: String) -> void:
	camp.set_mode(mode); camp._process(0); await frames()
	var point := Vector2(-1, -1)
	for cell: String in camp._content:
		if camp._key_shown(cell) and camp._content[cell] == [id, where]:
			point = camp.get_global_transform_with_canvas() * camp._r(camp._slot_rect(cell)).get_center()
			break
	check(point.x >= 0, "visible native cell for " + id + " in " + where)
	if point.x < 0: return
	await move(point)
	check(WikiContext.hovered(game.hud).get("item", "") == id, "context follows pointer over " + id)
	await key(KEY_F7)
	var wiki := game.hud._wiki
	var expected := "rune/" + id.trim_prefix("rune:").uri_encode() if id.begins_with("rune:") else WikiCatalog.item_key(id)
	check(wiki.visible and (wiki.current.begins_with("spell/") if (id.begins_with("spell:") or id.begins_with("keystone:")) else wiki.current == expected), "F7 opens hovered article for " + id)
	check(get_tree().paused and game.hud.blocks_input(), "campaign wiki owns input and pause")
	await key(KEY_ESCAPE)
	check(not wiki.visible and not get_tree().paused and camp.is_visible_in_tree(), "Escape restores the same camp")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errors)
	GameData.options.merge({"show_tutorial":0, "autosave":0, "auto_graphics":0, "confine_mouse":0, "net_upnp":0, "net_lan":0, "net_directory":0}, true)
	await frames(24)
	GameData._window_gen += 1; get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 800); get_window().position = Vector2i.ZERO
	await frames()
	check(EIKeymap.keys_for("wiki_context", 0).has("F7") and EIKeymap.keys_for("wiki_context", 1).has("F7"), "F7 defaults in classic and WASD layouts")
	session = Session.new(); add_child(session)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.set_physics_process(false)
	session.state = CampaignState.new(); session.state.ensure_hero(0, "Human Hero")
	await session.enter_zone("bz1g", 1, false)
	check(session.world != null, "real campaign camp loads")
	if session.world == null: get_tree().quit(1); return
	session.world.set_physics_process(false); session.world.vm.instances.clear()
	var hero: GameUnit = session.party_units(0)[0]
	game.selected = [hero]
	var h: Dictionary = hero.get_meta("hero")
	h.spells = ["fireball{e1}"]; hero.max_mana = 10000
	for stat: String in ["str", "dex", "int"]: h[stat] = 100
	session.state.items = ["stone axe.rock", "spell:fireball{e1}", "rune:e1", "keystone:fireball"]
	session.state.shops[1] = {"restock":false, "goods":{"stone axe.rock":20, "spell:fireball{e1}":20, "rune:e1":20}, "sold":{}}
	game.hud._inventory.open(true, 1); camp = game.hud._inventory._camp
	await frames()
	await hovered_item("stone axe.rock", "weapons", "bag")
	await hovered_item("stone axe.rock", "itemtrade", "shop")
	await hovered_item("spell:fireball{e1}", "spellconstr", "bag")
	await hovered_item("rune:e1", "spellconstr", "shop")
	await hovered_item("keystone:fireball", "spellconstr", "bag")
	await shot("camp-without-wiki-button")
	game.hud._inventory.hide(); await frames()
	# Unit panel context is the displayed unit; it never sends a combat order.
	# The village normally hides the field HUD; expose its real controls for this fixture.
	game.hud.set_process(false); game.hud._field.show()
	var orders := hero.orders.duplicate(true)
	await move(game.hud.unit_panel.get_global_rect().get_center()); await frames(15)
	await key(KEY_F7)
	check(game.hud._wiki.current == WikiContext.for_unit(hero).key, "hovered hero panel opens its creature article: " + game.hud._wiki.current)
	check(hero.orders == orders, "wiki shortcut issues no gameplay order")
	await key(KEY_ESCAPE)
	game.hud.set_process(true)
	# Native quest rows and their text both expose the same quest.
	game.hud.open_quests("field", "bz1g"); await frames()
	var quests := game.hud.quests_screen
	var quest_key: String = game.hud._wiki.catalog.search("", "Quests")[0]
	quests.quests = PackedStringArray([quest_key.trim_prefix("quest/").uri_decode()]); quests._select(0)
	await move(quests.get_global_transform_with_canvas() * quests._r(Rect2(60, 30, 300, 24)).get_center())
	await key(KEY_F7)
	check(game.hud._wiki.current == quest_key, "native hovered quest row opens its article")
	await key(KEY_ESCAPE)
	quests.close(""); await frames()
	# Rebinding uses the active layout; typing and rebinding dialogs retain keys.
	var bindings := EIKeymap.bindings()
	var edited := bindings.duplicate(); edited.erase(EIKeymap.scan_code(KEY_F7)); edited[EIKeymap.scan_code(KEY_F4)] = "wiki_context"
	EIKeymap.set_bindings(edited)
	await key(KEY_F7); check(not game.hud._wiki.visible, "old binding no longer opens wiki")
	await key(KEY_F4); check(game.hud._wiki.visible, "new binding opens wiki")
	await key(KEY_ESCAPE)
	game.hud._options.open(); game.hud._options._show_group(10); await key(KEY_F4)
	check(not game.hud._wiki.visible and game.hud._options.visible, "options keep shortcut for key capture")
	game.hud._options._close()
	var edit := LineEdit.new(); game.hud._safe_root.add_child(edit); edit.grab_focus()
	await key(KEY_F4); check(not game.hud._wiki.visible, "text fields retain keyboard input")
	edit.queue_free(); await frames()
	# A saved unbind remains unbound after a layout reload.
	for sc in edited.keys():
		if edited[sc] == "wiki_context": edited.erase(sc)
	EIKeymap.set_bindings(edited)
	EIKeymap._loaded = false; EIKeymap._wasd_loaded = false
	check(EIKeymap.keys_for("wiki_context").is_empty(), "saved unbinding survives reload")
	EIKeymap.set_bindings(bindings)
	# Online campaign wiki must not pause the simulation.
	session.online = true; await key(KEY_F7)
	check(game.hud._wiki.visible and not get_tree().paused, "co-op wiki leaves the shared clock running")
	await key(KEY_ESCAPE); session.online = false
	game.queue_free(); session.queue_free(); await frames()
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("WIKI_CONTEXT_INPUT ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
