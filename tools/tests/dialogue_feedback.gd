extends Node
class CaptureSession extends Session:
	var events: Array = []
	func broadcast(event: Dictionary) -> void:
		events.append(event.duplicate(true))
		super.broadcast(event)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1},true)
	var session := CaptureSession.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.set_physics_process(false)
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("bz5h",1,false)
	var world := session.world
	world.set_process(false); world.set_physics_process(false)
	world.vm.instances.clear()
	var vm := world.vm
	var b := vm.briefings
	b.active = ""; b._pending_dialog = {}; b._check = INF
	var smith: GameUnit = vm._by_name("NSheriff")
	check(smith != null, "authored smith exists")
	smith._talk_command = 0; smith._talk_posted = 9
	for key: String in session.state.gs_keys(0,"b.",true): session.state.set_var(0,key,3)
	session.state.set_var(0,"b.NSheriff.buy_1",1)
	session.state.set_var(0,"b.NSheriff.NSheriff_about",1)
	b.interact(null,smith,0)
	check(session.events.back().options.size() == 2, "initial list has assortment speech and work topic")
	b.topic(0,String(session.events.back().options.filter(func(row): return String(row.var).to_lower().ends_with(".buy_1"))[0].var),smith.uid)
	check(b.active.to_lower() == "b.nsheriff.buy_1", "assortment starts authored introduction")
	check(Briefings.parse(GameData.text("briefing buy_1")).phrases.size() > 0, "authored speech is retained")
	b.complete(0,b.active,true)
	vm.instances.clear(); vm.spawn("BuyNSheriffMain#1",[null])
	for i in 6: vm.tick(0.1)
	check(session.state.get_var(0,"b.NSheriff.buy_1") == 2, "introduction remains completed")
	b.interact(null,smith,0)
	var root: Array = session.events.back().options
	check(root.size() == 1 and root[0].var == "@smith_assortment", "catalogue no longer replaces main topic list")
	b.topic(0,"@smith_assortment",smith.uid)
	var choices: Array = session.events.back().options
	check(choices.size() == 22 and choices[0].var == "@smith_back", "all 21 authored offers and Back are available")
	var cash := session.state.money
	b.topic(0,"@smith_back",smith.uid)
	check(session.events.back().options == root and session.state.money == cash, "Back restores main topics without a purchase")
	b.interact(null,smith,0)
	check(session.events.back().options == root and b.active.is_empty(), "talking again does not repeat introduction or force catalogue")
	var marks := OrderMarks.new(); marks.game = game; game.add_child(marks); marks.set_process(false)
	game.selected.clear(); GameData.options.select_type = 1
	marks._refresh_talk_units(); marks._update_lit()
	check(not smith in marks._lit, "topic list suppresses the conversation highlight")
	game.hud._dialog.visible = false
	marks._refresh_talk_units(); marks._update_lit()
	check(smith in marks._lit, "NPC with available topics lights without selection")
	for e: Array in b.available_for(smith): session.state.set_var(0,"b.%s.%s" % e,2)
	marks._refresh_talk_units(); marks._update_lit()
	check(not smith in marks._lit, "highlight clears when no topic remains")
	GameData.options.select_type = 0; game.selected.assign([smith])
	marks._refresh_talk_units(); marks._update_lit()
	check(smith in marks._lit, "selection still lights a unit with no topics")
	var dialog := DialogPanel.new()
	check(dialog._item_name("rune:e0") == Items.title("rune:e0") and not "rune:" in dialog._item_name("rune:e0"), "rune reward uses localized name")
	var wand := Items.blueprint_name("bp:wand 6")
	check(wand == GameData.text("qitem wand_6 rock").get_slice("\n",0).strip_edges() and not wand.is_empty(), "wand blueprint uses authored localized name")
	check(not "Wand 6" in Items.title("bp:wand 6") and not "Wand 6" in Items.log_name("bp:wand 6"), "tooltip and item log omit placeholder wand name")
	dialog.free()
	game.queue_free(); session.queue_free()
	await get_tree().process_frame
	print("DIALOGUE_FEEDBACK ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
