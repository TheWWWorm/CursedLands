extends Node
## Real authored wolf perception with a deferred corpse investigation and
## delayed warnings. Keep the one-hit, unseen kill from #38 quiet.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func forget(u: GameUnit) -> void:
	for key in ["noticed", "seen_corpses", "perceived", "suspect", "pending_corpses", "calm", "attacker", "fear_on", "help_next"]:
		u.remove_meta(key)
	u.order = {}; u.orders.clear(); u.ai_next = 0

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"auto_graphics":0},true)
	var s := Session.new(); add_child(s); s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero"); s.state.world_time=12.0; s.state.set_var(0,"q.gz3g.q1g",1)
	var g := Game.new(); g.session=s; s.game=g; add_child(g)
	await s.enter_zone("gz3g",1,false)
	var w := s.world; w.set_process(false); w.set_physics_process(false)
	var observer: GameUnit = w.units[3327]
	var body: GameUnit = w.units[3326]
	var caller: GameUnit = w.units[3328]
	var far: GameUnit = w.units[3329]
	var hero: GameUnit = s.party_units(0)[0]
	body.pos=observer.pos+Vector2(0,-1.75); body._sync_transform(0); w.nav.track_unit(body)
	body.die()
	w.ai.suspect(observer, observer.pos+Vector2(5,0), 1000.0)
	w.ai.player_perceive(observer,true)
	check((observer.get_meta("seen_corpses",{}) as Dictionary).has(body.get_instance_id()), "wolf really sees the body during a higher-priority alert")
	check(observer.get_meta("suspect").l0==1000.0, "body does not override an urgent threat")
	# Let that alert expire while the wolf is occupied. Seeing the body must
	# not permanently consume its later investigation.
	w.time += 600 * GameUnit.TICK
	observer.order={}; observer.ai_next=0
	w.ai.think(observer)
	check(observer.get_meta("suspect",{}).get("pos")==body.pos, "wolf returns to the previously seen body after the urgent alert")
	check(observer.orders.any(func(o):return o.get("susp",false) and o.get("type")=="move"), "wolf issues an approach order to the body")
	# Warning conveys the identified hostile to a friend facing away. A
	# neutral or distant listener must not acquire a fabricated enemy.
	for u in [observer,caller,far]: forget(u)
	caller.pos=Vector2(56,240); observer.pos=caller.pos+Vector2(3,0); far.pos=caller.pos+Vector2(20,0)
	hero.pos=caller.pos+Vector2(-3,0); hero.hidden=false
	observer.facing=0
	for u in [caller,observer,far,hero]: u._sync_transform(0); w.nav.track_unit(u)
	w.ai._help.clear()
	check(not w.ai.can_notice(observer,hero,float(observer.stats.sight)), "pack listener cannot acquire this enemy through its own sight")
	w.ai.on_attacked(caller,hero)
	for tick in 26: w.time+=GameUnit.TICK; w.ai.tick()
	check(not (observer.get_meta("noticed",{}) as Dictionary).has(hero.get_instance_id()), "ally waits the original warning delay")
	w.time+=GameUnit.TICK; w.ai.tick()
	check((observer.get_meta("noticed",{}) as Dictionary).has(hero.get_instance_id()), "nearby packmate learns which hostile was detected")
	check(not (far.get_meta("noticed",{}) as Dictionary).has(hero.get_instance_id()), "warning respects the authored help radius")
	w.ai.think(observer)
	check(observer.orders.any(func(o):return o.get("target")==hero and o.get("type") in ["attack","cast"]), "alerted packmate issues an attack order")
	# An ally that arrives after initial detection also receives a warning.
	forget(far); far.pos=caller.pos+Vector2(0,3); w.nav.track_unit(far)
	if not caller.orders.is_empty(): caller.order=caller.orders.pop_front()
	caller.ai_next=0; w.ai.rechoose(caller)
	check(w.ai._help.any(func(e):return e[0]==far), "ongoing combat warns an ally that has just come within range")
	# Lethal hits never execute the surviving-hit warning path. This checks
	# the actual damage entry point, not a direct call to die().
	w.ai._help.clear(); forget(observer); forget(caller)
	# Face every living observer away, beyond peripheral detection. Murder
	# witness scans remain active; this is specifically an *unseen* kill.
	hero.pos=caller.pos-Vector2(4,0)
	for u: GameUnit in w.unit_rows():
		if u.controller>=0 or u.dead or u==caller: continue
		forget(u)
		if u.pos.distance_to(caller.pos)<10: u.pos=caller.pos+Vector2(12,0)
		u.facing=(u.pos-caller.pos).angle()
		w.nav.track_unit(u)
	observer.pos=caller.pos+Vector2(6,0); observer.facing=0; w.nav.track_unit(observer)
	w.time+=12*GameUnit.TICK
	check(observer.pos.distance_to(caller.pos)<7,"stealth control remains inside the victim's help radius")
	check(not w.ai.can_notice(observer,caller,float(observer.stats.sight)) and not w.ai.can_notice(observer,hero,float(observer.stats.sight)), "stealth control cannot see victim or killer")
	caller.hp=1
	caller.take_damage(1000000.0,hero)
	check(caller.dead and not w.ai._help.any(func(e):return e[0]==observer), "one-hit kill cannot warn the unaware packmate")
	check(not (observer.get_meta("noticed",{}) as Dictionary).has(hero.get_instance_id()), "an unseen kill does not reveal the killer to a packmate")
	g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	TexUpscale.shutdown()
	print("PACK_ALERT_RECOVERY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
