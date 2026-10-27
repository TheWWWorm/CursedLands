extends Node
## Issue #104: a running hero whose stamina runs out says "out of stamina"
## (ack 0x1d, native 547890) on that tick, once; the remake keeps the run
## request for when stamina returns.
class CaptureSession extends Session:
	var acks: Array = []
	func broadcast(event: Dictionary) -> void:
		if event.get("t", "") == "ack":
			acks.append(int(event.code))
		super.broadcast(event)

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	TutorialPanel.auto_show = false
	var session := CaptureSession.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1g",1,false)
	var w := session.world
	w.set_process(false); w.set_physics_process(false)
	w.vm.instances.clear()
	var hero: GameUnit = session.party_units(0)[0]
	check(hero.max_mana > 0.0 and not hero.free_running(), "the hero spends stamina when running")
	hero.action = "run"
	hero.mana = hero.max_mana * 0.5
	session.acks.clear()
	hero._tick(GameUnit.TICK)
	check(not EIAcks.OUT_OF_STAMINA in session.acks, "no line while stamina remains")
	hero.action = "run"
	hero.mana = hero.max_mana / 300.0
	hero._tick(GameUnit.TICK)
	check(hero.mana == 0.0, "the run uses up the last stamina")
	check(session.acks.count(EIAcks.OUT_OF_STAMINA) == 1, "the hero says it is out of stamina")
	hero.action = "run"
	hero._tick(GameUnit.TICK)
	check(session.acks.count(EIAcks.OUT_OF_STAMINA) == 1, "the line is not repeated while stamina stays at 0")
	game.queue_free(); session.queue_free()
	await get_tree().process_frame
	print("RESULT checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
