extends Node
## An alarm switches a unit's behaviour as the original's descriptor switch
## (5d6630) does: the motivation list is rebuilt from the new descriptor
## (script-set motivations dropped), the AI target and state are cleared, and
## a descriptor that is always active wakes the unit and keeps it updated
## (5d6c3c -> 58d5d0; expiry 58d8ce reads the current descriptor's flag).
## Real gz3g zone, its far patrol goblin 3379 and the active-object set.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(s: Session, n: int) -> void:
	for i in n: s.world._tick(GameUnit.TICK)

## Run until `u` is frozen (at most 4000 ticks).
func asleep(s: Session, u: GameUnit) -> bool:
	var n := 0
	while s.world.active_set.is_awake(u) and n < 4000:
		ticks(s, 1); n += 1
		if n % 50 == 0: await get_tree().process_frame
	return not s.world.active_set.is_awake(u)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz3g", 1, false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	var gob: GameUnit = w.units.get(3379)
	check(gob != null, "goblin 3379 is in gz3g")
	if gob == null:
		get_tree().quit(1); return
	w.set_relation(gob.faction, hero.faction, 0); w.set_relation(hero.faction, gob.faction, 0)
	# Descriptor 0 as shipped (not always active); descriptor 1 is used by
	# alarm 1 and always active, as zone7letter's runner 1000118.
	var info: Dictionary = gob.info.duplicate(true)
	var ls: Array = info.get("logic", [])
	check(not ls.is_empty() and not bool(ls[0].get("always_active", false)), "the goblin's descriptor 0 is not always active")
	var d1: Dictionary = (ls[0] as Dictionary).duplicate(true)
	d1.alarm_use = 1; d1.always_active = 1
	ls.resize(1); ls.append(d1); ls.append((ls[0] as Dictionary).duplicate(true))
	info.logic = ls
	gob.info = info
	check(await asleep(s, gob), "the far goblin is frozen")
	# A script set its motivations and gave it an AI action.
	gob.set_meta("um", {"fight": "revenge", "susp": false, "corpse": false, "fear": -1})
	gob.set_meta("ai_state", 3); gob.set_meta("ai_target", hero)
	w.ai.invoke_alarm(1, gob.pos, false)
	check(int(gob.get_meta("logic_idx", 0)) == 1, "alarm 1 switches it to descriptor 1")
	check(not gob.has_meta("um"), "its script-set motivations are dropped")
	check(w.ai.mots(gob).fight != "revenge", "its motivations come from the descriptor again")
	check(not gob.has_meta("ai_state") and not gob.has_meta("ai_target"), "its AI target and state are cleared")
	check(w.active_set.is_awake(gob), "the always-active descriptor wakes it far from the party")
	ticks(s, 400)
	check(w.active_set.is_awake(gob), "it stays updated long after a wake's counter (400 ticks)")
	# Back to descriptor 0: its flag is the one read again.
	w.ai.invoke_alarm(0, gob.pos, true)
	check(int(gob.get_meta("logic_idx", 0)) == 0 and not bool(w.ai.logic(gob).get("always_active", false)), "alarm 0 restores descriptor 0")
	check(await asleep(s, gob), "it freezes again once its counter runs out")
	# A unit whose descriptor is not used by the alarm keeps its motivations.
	var other: GameUnit = null
	for u: GameUnit in w.unit_rows():
		var uls: Array = u.info.get("logic", [])
		if u != gob and not u.dead and u.controller < 0 and not u.has_meta("hero") \
				and uls.size() > 1 and int(uls[1].get("alarm_use", 0)) == 0:
			other = u; break
	check(other != null, "a unit whose descriptor 1 is not used by alarm 1")
	other.set_meta("um", {"fight": "revenge", "susp": false, "corpse": false, "fear": -1})
	w.ai.invoke_alarm(1, gob.pos, false)
	check(other.has_meta("um") and int(other.get_meta("logic_idx", 0)) == 0, "it keeps its script motivations and descriptor")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("ALARM_BEHAVIOUR ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
