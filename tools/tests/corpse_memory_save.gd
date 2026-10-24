extends Node
## #112: exercise real NPC discovery and Session saves, including a save
## during the investigation and repeated loads after it has finished.
var checks := 0
var failures := 0
var s: Session
var g: Game

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func freeze() -> void:
	s.set_physics_process(false)
	s.world.set_process(false); s.world.set_physics_process(false)
	g.rig.set_process(false)
	for u: GameUnit in s.world.unit_rows():
		u.set_process(false); u.set_physics_process(false)

func ticks(n: int) -> void:
	for i in n:
		s.world._tick(GameUnit.TICK)
		if i % 25 == 0: await get_tree().process_frame

func remembers(observer: GameUnit, body: GameUnit) -> bool:
	return observer.get_meta("seen_corpses", {}).get(body.get_instance_id()) == body

func reload(slot: String) -> void:
	check(s.save_game(slot) == OK, slot + ": save succeeds")
	check(s.load_game(slot), slot + ": load succeeds")
	freeze()
	# Deployment is complete; the production tick restores this before AI.
	s.world.corpse_pools.prepare_restore()

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,
		"net_lan":0,"net_upnp":0,"net_directory":0}, true)
	s = Session.new(); add_child(s); s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero"); s.state.world_time = 12.0; s.state.set_var(0,"q.gz3g.q1g",1)
	g = Game.new(); g.session=s; s.game=g; add_child(g)
	await s.enter_zone("gz3g",1,false); freeze()
	var observer: GameUnit = s.world.units[3327]
	var body: GameUnit = s.world.units[3326]
	body.pos = observer.pos + Vector2(0,-1.75); body._sync_transform(0); s.world.nav.track_unit(body)
	body.die()
	await ticks(30)
	check(remembers(observer,body), "authored wolf remembers its dead packmate")
	check(observer.get_meta("suspect", {}).get("active",false), "wolf is investigating before the save")
	var before: Dictionary = observer.get_meta("suspect", {}).duplicate(true)
	var level := s.world.ai._susp_level(before) if not before.is_empty() else 0.0
	var old_instance := body.get_instance_id()
	await reload("corpse-mid")
	observer=s.world.units[3327]; body=s.world.units[3326]
	check(body.get_instance_id()!=old_instance, "load creates a new corpse instance")
	check(remembers(observer,body), "NPC memory resolves the new corpse instance before perception")
	var after: Dictionary = observer.get_meta("suspect", {})
	check(not after.is_empty() and is_equal_approx(s.world.ai._susp_level(after),level), "load preserves suspicion decay instead of restarting it")
	check(after.get("corpse",-1)==body.get_instance_id(), "active investigation resolves its corpse identity")
	await ticks(420)
	check(not observer.has_meta("suspect"), "investigation finishes naturally")
	for cycle in 3:
		await reload("corpse-finished-%d" % cycle)
		observer=s.world.units[3327]; body=s.world.units[3326]
		check(remembers(observer,body), "finished memory survives load %d" % cycle)
		await ticks(40)
		check(not observer.has_meta("suspect") and not observer.has_meta("pending_corpses"), "load %d does not rediscover the same corpse" % cycle)
	# Memory belongs to an observer. A newly discovered body must still work.
	var fresh: GameUnit = s.world.units[3328]
	fresh.pos=observer.pos+Vector2(0,-1.0); fresh._sync_transform(0); s.world.nav.track_unit(fresh)
	fresh.die(); observer.facing=(fresh.pos-observer.pos).angle()
	# Native candidate lists refresh every 8–11 logic ticks.
	s.world.time += 12 * GameUnit.TICK
	s.world.ai.player_perceive(observer,true)
	check(remembers(observer,fresh) and observer.has_meta("pending_corpses"), "a different corpse can still be discovered")
	# Pending discoveries must survive a checkpoint while stronger suspicion
	# prevents their investigation (combat/fleeing uses this same queue).
	s.world.ai.suspect(observer,observer.pos,1000.0,-2.0)
	var fresh_uid := fresh.uid
	await reload("corpse-pending")
	observer=s.world.units[3327]; fresh=s.world.units[fresh_uid]
	var pending: Dictionary = observer.get_meta("pending_corpses",{})
	check(pending.has(fresh.get_instance_id()) and pending[fresh.get_instance_id()].get_ref()==fresh, "pending discovery survives stronger suspicion")
	var loaded_suspicion: Dictionary = observer.get_meta("suspect",{})
	check(not loaded_suspicion.is_empty() and is_equal_approx(s.world.ai._susp_level(loaded_suspicion),1000.0), "pending load retains the stronger alert")
	var ledger := s.world.corpse_pools.save_state()
	s.world.remove_unit(fresh)
	s.world.corpse_pools.restore_state(ledger); s.world.corpse_pools.prepare_restore()
	check(not observer.get_meta("pending_corpses",{}).has(fresh.get_instance_id()), "removed corpse is not restored into the pending queue")
	var hero: GameUnit = s.party_units(0)[0]
	var ref: Array = s.world.corpse_pools._ref(hero)
	var refs := preload("res://src/game/actor_refs.gd")
	check(s.world.corpse_pools._resolve(refs.project_value(ref,1))==null, "absent co-op participant cannot fall back to its old runtime id")
	var peer := ref.duplicate(true); peer[1][2]=1
	check(s.world.corpse_pools._resolve(refs.project_value(peer,1))==hero, "returning co-op participant resolves its adopted solo roster")
	check(s.world.corpse_pools._resolve([hero.uid,CampaignState.party_ref(hero)])==hero, "older party references remain readable")
	g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	TexUpscale.shutdown()
	print("CORPSE_MEMORY_SAVE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
