extends Node
## Normal in-progress escape and mid-disappearance saves must keep the
## original Terror timeline while completed, resurrected saves are repaired.
var checks := 0
var failures := 0
var session: Session

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func freeze() -> void:
	session.set_physics_process(false)
	session.world.set_process(false); session.world.set_physics_process(false)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_directory":0,"net_lan":0},true)
	session = Session.new(); add_child(session)
	var game := Game.new(); game.session=session; session.game=game; add_child(game)
	session.set_physics_process(false)
	session.state=CampaignState.new(); session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1h",1,false); freeze()
	var vm := session.world.vm
	vm.instances.clear(); vm._add_mob("zone1evil.mob")
	var hero: GameUnit = session.party_units(0)[0]
	hero.pos=session.world.units[666666].pos+Vector2(5,0)
	session.state.set_var(0,"q.gz1h.q02h.2",1)
	vm.spawn("VCheck#1#8a",[null])
	check(session.save_game("terror_active")==OK,"save live escape before the 50m removal threshold")
	check(await session.load_game_shown("terror_active"),"load active escape normally")
	freeze(); vm=session.world.vm
	check(session.world.units.has(666666),"unfinished escape keeps Terror alive after loading")
	for i in 60: vm.tick(GameUnit.TICK)
	check(session.world.units.has(666666) and session.state.get_var(0,"q.gz1h.q02h.2")==1.0,"nearby hero does not trigger original removal")
	hero=session.party_units(0)[0]; hero.pos=session.world.units[666666].pos+Vector2(60,0)
	for i in 60:
		vm.tick(GameUnit.TICK)
		if session.state.get_var(0,"q.gz1h.q02h.2")==2.0: break
	check(session.state.get_var(0,"q.gz1h.q02h.2")==2.0 and session.world.units.has(666666),"original condition begins the seven-tick disappearance")
	check(session.save_game("terror_fading")==OK,"save during original disappearance wait")
	check(await session.load_game_shown("terror_fading"),"load partially completed disappearance")
	freeze(); vm=session.world.vm
	check(session.world.units.has(666666),"loading retains the pending disappearance animation")
	check(vm.instances.any(func(i):return i.sname=="VCheck#1#8a" and not i.frames.is_empty() and i.wait_until>vm.time),"native removal thread retains its saved wait")
	for i in 60: vm.tick(GameUnit.TICK)
	check(not session.world.units.has(666666),"saved native thread removes Terror after its remaining wait")
	check(session.save_game("terror_gone")==OK,"save completed native removal")
	var saved := CampaignState.load_from(SaveInfo.path("terror_gone"))
	check(saved.zones.gz1h.removed.has(666666),"normal removal creates a lasting tombstone")
	game.queue_free(); session.queue_free()
	for i in 8: await get_tree().process_frame
	print("TERROR_ACTIVE_SAVE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
