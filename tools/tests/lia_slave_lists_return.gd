extends Node
## Prepared escape checkpoint, original shelter dismissal and real map revisit.
## Keep the saved Portal VM: starting a fresh map misses the stale death watch.
var checks := 0
var failures := 0
var session: Session
var peak_worlds := 0
const Compat := preload("res://src/game/script/story_compat.gd")
const WorldRelease := preload("world_release.gd")

func contract_checks() -> void:
	var text := EIMob.load_bytes(GameData.read_file("maps/zone1.mob")).script_text
	var original := ScriptParser.parse(text)
	var ast := ScriptParser.parse(text)
	Compat.apply(ast, CampaignProfile.ORIGINAL, "gz1h")
	check(ast.scripts.HellManAlive == original.scripts.HellManAlive, "other campaign death checks remain authored")
	ast = ScriptParser.parse(text)
	Compat.apply(ast, CampaignProfile.ASTRAL, "gz2h")
	check(ast.scripts.HellManAlive == original.scripts.HellManAlive, "other regions remain authored")
	ast = ScriptParser.parse(text)
	ast.scripts.HellManAlive.blocks[0].body.append([ScriptParser.S_CALL,"GameOver",[]])
	var modded: Dictionary = ast.scripts.HellManAlive.duplicate(true)
	Compat.apply(ast, CampaignProfile.ASTRAL, "gz1h")
	check(ast.scripts.HellManAlive == modded, "changed mod death watcher is not rewritten")
	ast = ScriptParser.parse(text)
	Compat.apply(ast, CampaignProfile.ASTRAL, "gz1h")
	check(ast.scripts.HellManAlive.blocks[0].body == original.scripts.HellManAlive.blocks[0].body, "saved statement indexes and actual death action remain unchanged")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func freeze() -> void:
	session.set_physics_process(false)
	session.world.set_process(false)
	session.world.set_physics_process(false)
	peak_worlds = maxi(peak_worlds, WorldRelease.release(get_tree(), session.world))

func ticks(count: int) -> void:
	for i in count:
		session.world.time += GameUnit.TICK
		session.world.vm.tick(GameUnit.TICK)

func _ready() -> void:
	contract_checks()
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,
		"net_upnp":0,"net_lan":0,"net_directory":0}, true)
	session = Session.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.set_physics_process(false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-fixture="):
			var state := CampaignState.load_from(arg.trim_prefix("--save-fixture="))
			check(state != null and session._load_state("old_slave_lists", state), "unmodified release checkpoint loads")
			freeze()
			await verify_return(game)
			return
	session.state = CampaignState.new()
	session.state.create_party("FPrison")
	session.state.add_party_unit("FPrison", "Hero", "Hero1")
	session.state.add_party_unit("FPrison", "merc2", "merc2")
	session.state.set_current_party("FPrison")
	await session.enter_zone("gz1h", 1, false); freeze()
	var vm := session.world.vm
	vm.instances.clear()
	var hero: GameUnit = vm._by_name("Hero")
	check(hero != null and vm._by_name("merc2") != null, "Kir and Kel deploy before the shelter")
	# Start the actual post-tunnel escape handler at its authored trigger.
	hero.pos = Vector2(257.1, 50.7)
	session.state.set_var(0, "b.merc2.brief_5", 2)
	vm.spawn("VCheck#1#9", [null])
	ticks(380)
	check(vm.instances.any(func(inst): return inst.sname == "HellManAlive"), "original escape arms Kel's death watcher")
	check(not hero.dead, "living Kel does not kill Kir")
	var kel: GameUnit = vm._by_name("merc2")
	kel.dead = true
	check(vm._all(vm.ast.scripts.HellManAlive.blocks[0].conds, ScriptVM.Instance.new()), "actual Kel death before shelter dismissal still triggers the original failure")
	kel.dead = false
	session.state.set_var(0, "q.gz1h.q1h", 2)
	await session.enter_zone("bz2h", 1, false); freeze()
	check(session.state.zones.gz1h.vm.instances.any(func(inst): return inst.s == "HellManAlive"), "departure preserves the active escape watcher")
	vm = session.world.vm
	vm.instances.clear()
	vm.briefings.active = "b.bz2h.brief_6"
	vm.briefings.active_player = 0
	vm.briefings.complete(0, "b.bz2h.brief_6")
	ticks(2)
	check(session.state.party_member("FPrison::merc2").is_empty(), "original shelter briefing dismisses Kel")
	check(vm._by_name("merc2") != null and vm._by_name("merc2").hidden, "Kel waits hidden in the shelter")
	session.state.set_var(0, "q.gz1h.q2h", 1)
	check(GameData.text("quest q2h").begins_with("Списки рабов"), "checkpoint selects the Slave Lists quest")
	check(session.save_game("slave_lists_before") == OK, "pre-departure checkpoint saves")
	check(await session.load_game_shown("slave_lists_before"), "pre-departure checkpoint reloads")
	freeze()
	await verify_return(game)

func verify_return(game: Game) -> void:
	await session.enter_zone("gz1h", 5, false); freeze()
	var vm := session.world.vm
	var hero: GameUnit = vm._by_name("Hero")
	check(vm._by_name("merc2") == null, "Kel correctly remains at the shelter")
	check(vm.instances.any(func(inst): return inst.sname == "HellManAlive"), "return restores the old escape watcher")
	ticks(40)
	check(hero != null and not hero.dead, "Kir survives the restored escape watcher after dismissal")
	check(not session.sp_main_hero_dead(), "Slave Lists return keeps a living protagonist")
	check(session.save_game("slave_lists_after") == OK, "returned quest state saves")
	check(await session.load_game_shown("slave_lists_after"), "returned quest state reloads")
	freeze(); ticks(40)
	check(not session.world.vm._by_name("Hero").dead, "reloading the return does not reactivate the completed escape failure")
	game.queue_free(); session.queue_free()
	for i in 8: await get_tree().process_frame
	check(peak_worlds == 1, "each map change releases the previous map")
	print("LIA_SLAVE_LISTS_RETURN ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
