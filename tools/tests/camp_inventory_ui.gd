extends Node
## U40–U43: real original material text/art, constructor inventory categories,
## and held transfers through the live camp input path. No save is required.
var checks := 0
var failures := 0
var session: Session
var game: Game
var camp: CampView

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func body(key: String) -> String:
	var lines := Array(GameData.text(key).split("\n")).map(func(s): return String(s).strip_edges())
	if not lines.is_empty(): lines.pop_front()
	return " ".join(lines.filter(func(s): return not s.is_empty())).strip_edges()

func frame() -> void:
	for i in 3: await get_tree().process_frame

func click_item(id: String, where: String, pressed := true) -> void:
	camp._process(0.0)
	var point := Vector2(-10, -10)
	for key: String in camp._content:
		if camp._key_shown(key) and camp._content[key] == [id, where]:
			point = camp._r(camp._slot_rect(key)).get_center()
			break
	check(point.x >= 0, "actual %s cell exists for %s" % [where, id])
	TouchInput.motion(point, Vector2.ZERO)
	TouchInput.button(point, pressed)
	Input.flush_buffered_events()
	await frame()

func release() -> void:
	# Releasing outside the original cell must still cancel the capture.
	TouchInput.button(Vector2(1, 1), false)
	Input.flush_buffered_events()
	await frame()

func snapshot(name: String) -> void:
	camp.queue_redraw()
	await frame()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + name + ".png")

func _ready() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "net_upnp": 0, "net_lan": 0,
		"net_directory": 0, "auto_graphics": 0}, true)
	# Every authored material description, including names with underscores.
	var materials := 0
	for row: Dictionary in GameData.db.table("materials"):
		var name := String(row.name).to_lower()
		var key := "material " + name.replace(" ", "_")
		var expected := body(key)
		if expected.is_empty(): continue
		materials += 1
		check(Items.flavor("material." + name) == expected, "original localized material description: " + name)
	check(materials >= 30, "checked the original material catalogue")
	check(Items.flavor("material.rock") != body("litem material"), "stone does not use the generic placeholder")
	check(Items.flavor("bp:stone axe") == body("instr stone_axe"), "blueprint text retains its original source")
	var spell := "fireball{e1;e1;r1;r1;a1;a1;m1;m1}"
	var runes := SpellSlots.rune_icons(spell)
	check(runes.size() == 8 and runes.all(func(t): return t != null), "eight installed runes use real original icons")
	check(runes[0] == runes[1] and runes[0] != runes[2], "duplicate rune icons retain multiplicity and order")
	check(SpellSlots.rune_icons("fireball").is_empty(), "allowed prototype modifiers do not create installed markers")
	check(SpellSlots.rune_icons("  FIREBALL{ E1, R1 } ") == [runes[0], runes[2]], "canonical spell parsing supplies marker identities")

	session = Session.new(); add_child(session)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.set_physics_process(false)
	session.state = CampaignState.new(); session.state.ensure_hero(0, "Human Hero")
	await session.enter_zone("bz1g" if GameData.campaign_id == CampaignProfile.ORIGINAL else "bz1h", 1, false)
	check(session.world != null, "fixture enters an actual campaign camp")
	if session.world == null:
		get_tree().quit(1)
		return
	session.world.set_physics_process(false); session.world.vm.instances.clear()
	var hero: GameUnit = session.party_units(0)[0]
	var h: Dictionary = hero.get_meta("hero")
	h.spells = [spell, "fireball"]
	for stat: String in ["str", "dex", "int"]: h[stat] = 100
	hero.max_mana = 10000
	var st := session.state
	var potion := "tiny potion 1"
	var weapon := "stone axe.rock"
	var armor := "gipat medium plate.thin"
	var worn := Items.with_wear(weapon, 1.0)
	check(not Items.info(weapon).row.is_empty() and not Items.info(armor).row.is_empty(), "constructor fixtures use original weapon and armour records")
	st.items = ["bp:stone axe", weapon, "material.rock", "bp:gipat medium plate", armor, "material.thin",
		potion, "keystone:fireball", "rune:e1", "spell:" + spell]
	st.money = 100000
	var goods := {}
	for id: String in st.items: goods[id] = 20
	st.shops[1] = {"restock": false, "goods": goods, "sold": {}}
	var panel: InventoryPanel = game.hud._inventory
	panel.open(true, 1); camp = panel._camp
	check(camp.item_info_text("spell:" + spell).contains(Spells.mod_title("e1")), "inventory text includes installed rune names")
	camp.set_process(false) # Deterministic hold timing, while input dispatch stays live.
	camp._set_bag_filter(4)
	camp.set_mode("spellconstr")
	check(camp.filter == 0 and camp.shop_filter == 5, "spell constructor selects its category automatically")
	var bag := camp.bag_items()
	check(bag.has("keystone:fireball") and bag.has("rune:e1") and bag.has("spell:" + spell)
		and bag.has("spell:fireball"), "spell constructor shows keystones, runes, bag and learned spells together")
	check(bag.all(func(id): return Items.is_spell_piece(id)), "spell constructor hides unrelated bag items")
	var stock := camp.shop_items()
	check(stock.has("keystone:fireball") and stock.has("rune:e1") and stock.has("spell:" + spell), "spell constructor also exposes all shop ingredient categories")
	camp._process(0.0)
	check(not camp._views.bag0.visible and not camp._views.bag1.visible, "legacy 3D viewports cannot cover the completed spell artwork")
	await snapshot("spell-constructor-runes")
	camp.set_mode("itemconstr")
	bag = camp.bag_items(); stock = camp.shop_items()
	check(camp.filter == 0 and camp.shop_filter == 5, "item constructor replaces the spell filters automatically")
	check(bag.has("bp:stone axe") and bag.has("bp:gipat medium plate") and bag.has(weapon) and bag.has(armor), "weapon and armour blueprints and dismantlable equipment remain accessible")
	check(bag.has("material.rock") and bag.has("material.thin") and bag.has("spell:" + spell), "item constructor includes materials and enchantment spells")
	check(not bag.has("rune:e1") and not bag.has("keystone:fireball") and not bag.has(potion), "item constructor hides unrelated ingredients and consumables")
	check(stock.has("bp:stone axe") and stock.has("bp:gipat medium plate") and stock.has("material.rock"), "item constructor shop defaults include both equipment families and materials")
	camp._set_bag_filter(5)
	check(camp.bag_items().has(potion), "manual all-items filter remains available")
	camp.set_mode("spellconstr"); camp.set_mode("itemconstr")
	check(camp.filter == 0 and not camp.bag_items().has(potion), "re-entering a constructor restores its automatic filter")
	camp._process(0.0)
	for key: String in camp._content:
		if camp._content[key][0] == "material.rock": camp._update_hover(camp._slot_rect(key).get_center())
	check(camp._info_ids()[1] == "material.rock" and camp._item_info("material.rock").desc == body("material rock"), "hover panel receives the original stone description")
	await snapshot("material-description")

	# Capture the selected item ID, not the cell index (rows shift at exhaustion).
	camp.set_mode("itemtrade"); camp._set_bag_filter(5)
	st.items = [potion, potion, potion, potion, potion, worn, worn, weapon]
	st.shops[1].goods = {potion: 8}
	await click_item(potion, "bag")
	check(camp.sell_pile == [potion] and not camp._transfer_hold.is_empty(), "mouse press stages one copy and captures held transfer")
	camp._process_transfer_hold(0.49)
	check(camp.sell_pile.size() == 1, "hold delay does not repeat early")
	camp._process_transfer_hold(0.02)
	check(camp.sell_pile.size() == 2, "held button repeats after its delay")
	for i in 8: camp._process_transfer_hold(CampView.TRANSFER_INTERVAL + 0.01)
	check(camp.sell_pile.size() == 5 and camp._transfer_hold.is_empty(), "repeat stops at the exact stack count")
	check(camp.bag_count(worn) == 2 and camp.bag_count(weapon) == 1, "shifted cells do not transfer the next item or merge worn copies")
	await release()
	camp._on_cancel()
	await click_item(worn, "bag")
	camp._process_transfer_hold(0.6)
	check(camp.sell_pile == [worn, worn] and camp.bag_count(weapon) == 1, "repeating worn items keeps the pristine item separate")
	await release(); camp._on_cancel()
	await click_item(potion, "bag")
	await release()
	camp._process_transfer_hold(1.0)
	check(camp.sell_pile.size() == 1 and camp._transfer_hold.is_empty(), "release outside the cell stops transfer")
	camp._on_cancel()
	await click_item(potion, "bag")
	camp.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	camp._process_transfer_hold(1.0)
	check(camp.sell_pile.size() == 1 and camp._transfer_hold.is_empty(), "application focus loss stops transfer")
	await release(); camp._on_cancel()
	await click_item(potion, "bag")
	panel.hide(); camp._process_transfer_hold(1.0)
	check(camp.sell_pile.size() == 1 and camp._transfer_hold.is_empty(), "closing inventory stops transfer")
	await release(); panel.show(); camp._on_cancel()
	await click_item(potion, "bag")
	camp.set_mode("spelltrade"); camp._process_transfer_hold(1.0)
	check(camp.sell_pile.is_empty() and camp._transfer_hold.is_empty(), "mode change cancels capture and returns staged copies")
	await release(); camp.set_mode("itemtrade"); camp._set_bag_filter(5)
	await click_item(potion, "bag")
	st.items.erase(potion); st.items.erase(potion); st.items.erase(potion); st.items.erase(potion)
	camp._process_transfer_hold(1.0)
	check(camp.sell_pile.size() == 1 and camp._transfer_hold.is_empty(), "external inventory depletion stops capture")
	await release(); camp._on_cancel()
	camp._set_shop_filter(3)
	await click_item(potion, "shop")
	camp._process_transfer_hold(0.6)
	check(camp.buy_pile.size() == 2 and camp.shop_left(potion) == 6, "shop holds stage purchases with authoritative stock counts")
	camp._set_shop_filter(5)
	camp._process_transfer_hold(1.0)
	check(camp.buy_pile.size() == 2 and camp._transfer_hold.is_empty(), "filter changes cancel held transfer")
	await release(); camp._on_cancel()
	# Accept must fence the local offer before the command reaches authority.
	st.items = [potion, potion, potion]
	await click_item(potion, "bag")
	camp._process_transfer_hold(0.6)
	var before := st.money
	camp._on_yes()
	check(camp._transfer_hold.is_empty(), "submitting a trade cancels the held transfer immediately")
	await frame()
	camp._process_transfer_hold(1.0)
	check(st.items == [potion] and st.money == before + 2 * Items.sell_price(potion), "the held offer settles exactly once through the authority")
	await release()
	# A charged item uses its complete native state ID, just like wear.
	var wand := "wand 1.rock"
	for row: Dictionary in GameData.db.table("quick_items"):
		if String(row.get("name", "")).to_lower().contains("wand"):
			var mats := Items.materials_for("bp:" + String(row.name).to_lower())
			if not mats.is_empty():
				wand = String(row.name).to_lower() + "." + String(mats[0].name).to_lower()
				break
	var spent := Items.with_charge(wand, maxf(0.0, Items.energy(wand) - 1.0))
	check(spent != wand, "charge-state fixture uses an actual charge-bearing item")
	st.items = [spent, spent, wand]
	camp._on_cancel()
	await click_item(spent, "bag")
	camp._process_transfer_hold(0.6)
	check(camp.sell_pile == [spent, spent] and camp.bag_count(wand) == 1, "held transfers preserve charge-state distinctions")
	await release(); camp._on_cancel()
	st.items = [potion, potion, potion]
	TouchInput.enabled = true; TouchInput.mode_changed.emit()
	await frame(); camp._process(0.0)
	var point := camp._r(camp._slot_rect("bag0")).get_center()
	var touch := InputEventScreenTouch.new(); touch.index = 0; touch.position = point; touch.pressed = true
	Input.parse_input_event(touch); Input.flush_buffered_events()
	TouchInput._process(0.51)
	check(camp.sell_pile == [potion] and TouchInput.holding(camp), "touch hold captures a shop item without a tap on release")
	camp._process_transfer_hold(0.6)
	check(camp.sell_pile == [potion, potion], "touch hold repeats the same staged item")
	touch = touch.duplicate(); touch.pressed = false
	Input.parse_input_event(touch); Input.flush_buffered_events()
	await frame(); camp._process_transfer_hold(1.0)
	check(camp.sell_pile.size() == 2 and camp._transfer_hold.is_empty(), "touch release stops without adding a final copy")
	camp._on_cancel(); TouchInput.enabled = false; TouchInput.mode_changed.emit()
	panel.hide()
	game.selected = [hero]
	# The authored camp hides the battle HUD. Show the actual equipped control
	# at its normal size in a separate layer for the visual check.
	var layer := CanvasLayer.new(); add_child(layer)
	var slots := SpellSlots.new(); slots.game = game
	slots.position = Vector2(1450, 100); slots.size = Vector2(60, 480)
	layer.add_child(slots)
	await snapshot("equipped-spell-runes")
	check(slots._entries.size() == 2 and slots._entries[0][0] == spell, "equipped slots retain installed rune IDs")
	check(slots._get_tooltip(slots._cell_rect(0).get_center()).contains(Spells.mod_title("e1") + " x2"), "equipped tooltip names duplicate installed runes")
	layer.queue_free()
	game.queue_free(); session.queue_free()
	await frame()
	print("CAMP_INVENTORY_UI ", GameData.campaign_id, " ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
