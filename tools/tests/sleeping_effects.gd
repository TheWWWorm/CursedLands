extends Node
## Timed effects on a frozen unit (ObjectActivity). The original does not
## update sleeping objects (update loop 0x58D670), so their effects stopped
## counting down until the party came near. Cursed Lands counts them down, as
## the Rebirth edition does, and an effect running out wakes the unit (58D5D0)
## so its update removes it. Real gz3g patrol goblin far from the party.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(s: Session, n: int) -> void:
	for i in n: s.world._tick(GameUnit.TICK)

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
	check(await asleep(s, gob), "the far goblin is frozen")
	var at := gob.pos
	# Expiry after exactly as many ticks as on an awake unit.
	gob.buffs.feeblemind = {GameUnit.EFFECT_TICKS:40, "until":w.time + 40 * GameUnit.TICK, "no_cast":true}
	hero.buffs.feeblemind = {GameUnit.EFFECT_TICKS:40, "until":w.time + 40 * GameUnit.TICK, "no_cast":true}
	ticks(s, 10)
	check(gob.effect_ticks("feeblemind") == 30, "a sleeping unit's effect counts down (%s left)" % gob.effect_ticks("feeblemind"))
	check(hero.effect_ticks("feeblemind") == 30, "at the same rate as an awake unit's")
	check(not w.active_set.is_awake(gob) and gob.pos == at, "counting down does not wake it or move it")
	check(is_equal_approx(float(gob.buffs.feeblemind.until), float(hero.buffs.feeblemind.until)), "its deadline follows the count")
	ticks(s, 29)
	check(gob.effect_ticks("feeblemind") == 1 and gob.cannot_cast(), "one tick left, still in effect")
	check(not w.active_set.is_awake(gob), "still asleep before the effect runs out")
	ticks(s, 1)
	check(not gob.buffs.has("feeblemind") and not gob.cannot_cast(), "the effect runs out on the same tick as on an awake unit")
	check(not hero.buffs.has("feeblemind"), "the awake unit's effect ran out too")
	check(w.active_set.is_awake(gob), "the effect running out wakes the unit")
	check(await asleep(s, gob), "it sleeps again afterwards")
	# Several effects: each counts down; only the first to run out wakes it.
	gob.buffs.feeblemind = {GameUnit.EFFECT_TICKS:5, "until":w.time + 5 * GameUnit.TICK, "no_cast":true}
	gob.buffs.silence = {GameUnit.EFFECT_TICKS:300, "until":w.time + 300 * GameUnit.TICK}
	ticks(s, 5)
	check(not gob.buffs.has("feeblemind") and gob.effect_ticks("silence") == 295, "a short effect runs out, the long one keeps counting")
	check(await asleep(s, gob), "asleep again with the long effect")
	var left := gob.effect_ticks("silence")
	ticks(s, 20)
	check(gob.effect_ticks("silence") == left - 20 and not w.active_set.is_awake(gob), "the long effect keeps counting while asleep")
	# A record without a tick counter is left alone and wakes nothing.
	gob.buffs.erase("silence")
	gob.buffs.legacy = {"until":w.time + 1.0}
	ticks(s, 40)
	check(gob.buffs.has("legacy") and not w.active_set.is_awake(gob), "an effect without a tick count does not wake it")
	gob.buffs.erase("legacy")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("SLEEPING_EFFECTS ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
