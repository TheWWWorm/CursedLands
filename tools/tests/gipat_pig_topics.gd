extends Node

class CaptureSession extends Session:
	var topics: Array[Dictionary] = []

	func broadcast(event: Dictionary) -> void:
		if event.get("t") == "topics":
			topics.append(event)
			return
		super.broadcast(event)

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0}, true)
	TutorialPanel.auto_show = false
	var s := CaptureSession.new()
	add_child(s)
	var game := Game.new()
	game.session = s
	s.game = game
	add_child(game)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("bz1g", 1, false)
	s.set_physics_process(false)
	s.world.set_process(false)
	s.world.set_physics_process(false)
	game.marks.set_process(false)
	var dialogue := s.world.vm.briefings
	dialogue.active = ""
	dialogue._pending_dialog.clear()
	for key: String in s.state.gs_keys(0, "b.", true):
		s.state.set_var(0, key, 2)
	s.state.set_var(0, "b.pig.p0", 1)

	var pigs: Array[GameUnit] = []
	var ids: Array[int] = []
	for unit: GameUnit in s.world.unit_rows():
		if String(unit.info.get("name", "")).to_lower() != "pig":
			continue
		pigs.append(unit)
		ids.append(unit.uid)
		unit._talk_command = 0
		unit._talk_posted = 9
	ids.sort()
	check(ids == [182595, 399469, 848411, 1000002436], "four authored Gipat pigs")
	var named := ScriptVM.name_id("pig")
	check(named == 1000002436, "authored script identity")

	game.marks._refresh_talk_units()
	game.marks._update_lit()
	var ready: Array[int] = []
	var highlighted: Array[int] = []
	for unit in pigs:
		if game.can_talk_to(unit):
			ready.append(unit.uid)
		if unit in game.marks._lit:
			highlighted.append(unit.uid)
		dialogue.interact(null, unit, 0)
	var offered: Array[int] = []
	for event in s.topics:
		for option: Dictionary in event.options:
			if option.var == "b.pig.p0":
				offered.append(event.uid)
	check(ready == [named], "only the script actor is talkable: %s" % [ready])
	check(highlighted == [named], "only the script actor is highlighted: %s" % [highlighted])
	check(offered == [named], "only the script actor opens the kick topic: %s" % [offered])
	check(dialogue._actor_unit("pig", 0) == s.world.units.get(named), "briefing cast uses the same script actor")

	game.queue_free()
	s.queue_free()
	await get_tree().process_frame
	print("GIPAT_PIG_TOPICS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if not failures.is_empty() else 0)
