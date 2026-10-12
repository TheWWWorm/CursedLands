extends "camp_inventory_ui.gd"
## Render every camp screen with the installed HD Lands pack and exercise the
## live click path. Only isolated --mod-tests profiles may run this fixture.

func click_at(point: Vector2) -> void:
	TouchInput.motion(point, Vector2.ZERO)
	TouchInput.button(point, true)
	Input.flush_buffered_events()
	await frame()
	TouchInput.button(point, false)
	Input.flush_buffered_events()
	await frame()

func side(name: String) -> void:
	check(name in camp.side_buttons(), "screen offers " + name)
	await click_at(camp._r(CampView.SIDE_BUTTONS[name][0]).get_center())

func hover(id: String, where: String) -> void:
	camp._process(0)
	for key: String in camp._content:
		if camp._key_shown(key) and camp._content[key] == [id, where]:
			TouchInput.motion(camp._r(camp._slot_rect(key)).get_center(), Vector2.ZERO)
			Input.flush_buffered_events()
			await frame()
			check(camp._hover_key == key, "hover reaches actual " + where + " cell")
			return
	check(false, "visible hover cell for " + id)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"):
		get_tree().quit(2)
		return
	check(ModStore.create_profile("HD camp check", false, ["community.hd-lands-textures@1.4.0"]).is_empty(), "activate real installed HD package")
	check(GameData.open(GameData.root).is_empty(), "mount original campaign with HD overrides")
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0, "net_lan":0,
		"net_directory":0, "auto_graphics":0, "display_mode":0, "confine_mouse":0,
		"control_mode":0, "pad_enabled":0, "gfx_detailed_heads":1}, true)
	TutorialPanel.auto_show = false
	RenderingServer.set_render_loop_enabled(true)
	session = Session.new(); add_child(session)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.state = CampaignState.new(); session.state.ensure_hero(0, "Human Hero")
	await session.enter_zone("bz1g", 1, false)
	check(session.world != null, "enter actual Gipat camp")
	if session.world == null:
		get_tree().quit(1)
		return
	session.set_physics_process(false)
	session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	var hero: GameUnit = session.party_units(0)[0]
	game.selected.assign([hero])
	var h: Dictionary = hero.get_meta("hero")
	var spell := "fireball{e1;e1;r1;r1;a1;a1;m1;m1}"
	h.spells = [spell, "fireball"]
	h.exp = 500000
	for stat: String in ["str", "dex", "int"]: h[stat] = 25
	Combat.hero_stats(hero, h)
	var st := session.state
	var potion := "tiny potion 1"
	var weapon := "stone axe.rock"
	var armor := "gipat medium plate.thin"
	var worn := Items.with_wear(weapon, 1.0)
	var goods := {}
	st.items = [potion, weapon, armor, worn, "bp:stone axe", "material.rock",
		"bp:gipat medium plate", "material.thin", "keystone:fireball", "rune:e1", "spell:" + spell]
	st.money = 100000
	for id: String in st.items: goods[id] = 20
	var item_shop := 0
	var spell_shop := 0
	for id: int in Shops.records():
		if item_shop == 0 and Shops.sells_items(id): item_shop = id
		if spell_shop == 0 and Shops.sells_spells(id): spell_shop = id
	check(item_shop != 0 and spell_shop != 0, "native item and spell traders exist")
	for id: int in [item_shop, spell_shop]:
		st.shops[id] = {"restock":false, "goods":goods.duplicate(), "sold":{}}
	var panel: InventoryPanel = game.hud._inventory
	panel.open(true, item_shop); camp = panel._camp
	check(camp._tex.campinfo.get_width() > 256 and camp._tex.campslots.get_width() > 256, "camp buttons and equipment slots retain full HD sheets")
	GameData._window_gen += 1
	# A tiling desktop can retain its own window size. Exercise that actual
	# surface separately; the Xvfb run verifies both fixed target sizes.
	var native_window := OS.get_cmdline_user_args().has("--native-window")
	if not native_window: get_tree().root.mode = Window.MODE_WINDOWED
	for i in 20: await get_tree().process_frame
	var shapes: Array[Vector2i] = [Vector2i(1280,960), Vector2i(2560,1440)]
	if native_window: shapes.assign([Vector2i(get_viewport().get_visible_rect().size)])
	for shape: Vector2i in shapes:
		if not native_window: get_tree().root.size = shape
		for i in 20: await get_tree().process_frame
		check(get_viewport().get_visible_rect().size == Vector2(shape), "requested viewport is actually rendered: " + str(shape))
		for screen: String in CampView.MODES:
			panel.open(true, spell_shop if screen in ["spelltrade", "spellconstr"] else item_shop)
			await frame()
			await side(screen)
			check(camp.mode == screen, "click opens " + screen + " at " + str(shape))
			if screen == "weapons":
				check(camp._doll.visible and camp._doll._model != null, "equipped character preview is rendered")
				check(not camp._hero_rows().is_empty(), "armour and weapon stats are populated")
				await hover(armor, "bag")
			elif screen == "spells":
				await RenderingServer.frame_post_draw
				check(camp._skill_rows.size() > Skills.LIST.size(), "training and perk rows are populated")
				await hover("spell:" + spell, "known")
			elif screen == "itemtrade":
				await click_item(potion, "shop"); await release()
				await click_item(weapon, "bag"); await release()
				check(camp.buy_pile == [potion] and camp.sell_pile == [weapon], "buy and sell cells accept clicks together")
			elif screen == "spelltrade":
				await click_item("spell:" + spell, "shop"); await release()
				check(camp.buy_pile == ["spell:" + spell], "spell shop stages the selected card")
			elif screen == "itemconstr":
				await click_item(weapon, "bag"); await release()
				check(camp.c_ready == weapon and not camp._content.cbp[0].is_empty(), "item workshop displays item and components")
			elif screen == "spellconstr":
				await click_item("spell:" + spell, "bag"); await release()
				check(camp.s_ready() and camp.s_spell == spell, "spell workshop displays assembled spell and runes")
			elif screen == "repair":
				await click_item(worn, "bag"); await release()
				check(camp.repair_pile == [worn], "repair cell accepts worn item")
			check(Rect2(Vector2.ZERO, Vector2(shape)).encloses(camp._r(Rect2(0,0,800,600))), "entire camp layout fits " + screen)
			await snapshot("hd-%s-%d" % [screen, shape.x])
		# Settle one actual purchase through the on-screen confirmation button.
		panel.open(true, item_shop); await frame()
		await side("itemtrade")
		await click_item(potion, "shop"); await release()
		var before := st.money
		var count := st.items.count(potion)
		var cost := Items.buy_price(potion)
		await side("accept")
		check(st.items.count(potion) == count + 1 and st.money == before - cost, "shop confirmation settles one purchase")
		# Training uses the original row hit targets over the HD price plates.
		await side("spells")
		await RenderingServer.frame_post_draw
		var old := Skills.level(h, "melee")
		for row: Array in camp._skill_rows:
			if row[1].get("stat", "") == "melee":
				await click_at(camp._r(row[0]).get_center())
				break
		check(Skills.level(h, "melee") == old + 1, "stats screen skill button raises the chosen skill")
		await side("exit")
		check(not panel.visible, "HD exit button closes the screen")
	# The other common framed dialogs also share the original atlas layout.
	get_tree().root.size = Vector2i(1280,960)
	var layer := CanvasLayer.new(); add_child(layer)
	var options := OptionsPanel.new(); layer.add_child(options); options.open()
	await snapshot("hd-options"); options.free(); await frame()
	var saves := LoadPanel.new(); layer.add_child(saves); saves.open()
	await snapshot("hd-load"); saves.free(); await frame()
	var mods := ModPanel.new(); layer.add_child(mods); mods.open()
	await snapshot("hd-mods-mounted")
	check(mods._body.size.x <= mods._scroll.size.x + 1, "mod menu also fits while HD is mounted")
	layer.queue_free(); game.queue_free(); session.queue_free(); await frame()
	print("HD_CAMP_UI ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
