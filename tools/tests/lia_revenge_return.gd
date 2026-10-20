extends Node
## Take the west bridge on a prior visit, then return for Revenge. The unused
## east-route watcher must not consume the mansion's reused area 2.
var checks := 0
var failures := []
var session: Session
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)
func freeze() -> void:
	session.set_physics_process(false); session.world.set_process(false); session.world.set_physics_process(false)
func ticks(count: int) -> void:
	for i in count:
		session.world.time += GameUnit.TICK
		session.world.vm.tick(GameUnit.TICK)
func move(at: Vector2) -> void:
	for u: GameUnit in session.party_units(0): u.pos = at
	ticks(3)
func v(key: String) -> int: return int(session.state.get_var(0, "q.gz2h." + key))
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	session = Session.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.set_physics_process(false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-fixture="):
			var state := CampaignState.load_from(arg.trim_prefix("--save-fixture="))
			check(state != null and session._load_state("old_revenge",state),"affected old checkpoint loads")
			freeze()
			check(v("q14h.2") == 1 and session.world.vm.areas.has(2),"missing mansion trigger is restored for the waiting objective")
			move(Vector2(117,354))
			check(v("q14h.2") == 2 and v("q14h.3") == 1,"restored trigger advances the existing Revenge quest")
			await finish_quest(game)
			return
	session.state.create_party("FPrison")
	session.state.add_party_unit("FPrison","Hero","Hero1")
	session.state.set_current_party("FPrison")
	session.state.set_var(0,"q.gz2h.q7h",1)
	await session.enter_zone("gz2h",1,false); freeze(); ticks(30)
	check(session.world.vm.ast.scripts.has("VCheck#4#1"),"real Revenge region loads")
	move(Vector2(218.5,117.3))
	check(v("q7h.1") == 2,"prior quest reaches bridge choice")
	move(Vector2(148,173))
	check(v("q7h.3") == 2 and v("q7h.2") == 3,"prior quest takes the west bridge")
	move(Vector2(147,235))
	check(v("q7h") == 2,"prior bridge quest completes")
	check(session.world.vm.instances.any(func(i): return i.sname == "VCheck#1#3"),"unused east watcher remains in native VM")
	check(session.save_game("revenge_before") == OK,"prior-visit checkpoint saves")
	await session.enter_zone("bz2h",1,false); freeze()
	session.state.set_var(0,"q.gz2h.q14h",1)
	await session.enter_zone("gz2h",1,false); freeze(); ticks(30)
	check(session.world.units.has(1014001),"Revenge adds Aliya after the return")
	check(int(session.world.levers.get(150158,{}).get("state",-1)) == 1,"mansion entrance opens by the authored quest action")
	move(Vector2(115,317))
	check(v("q14h.1") == 2 and v("q14h.2") == 1,"return reaches the meeting and activates mansion objective")
	move(Vector2(117,354))
	if "--save-blocked" in OS.get_cmdline_user_args(): session.save_game("revenge_blocked")
	check(v("q7h.3") == 2,"Revenge does not fail the completed west bridge objective")
	check(v("q14h.2") == 2 and v("q14h.3") == 1,"mansion trigger survives the stale bridge watcher")
	await finish_quest(game)

func finish_quest(game: Game) -> void:
	for id in [1014004,1014005]:
		var guard: GameUnit = session.world.units.get(id)
		if guard: guard.dead = true
	ticks(3)
	check(v("q14h.3") == 2 and v("q14h.4") == 1,"defeating the two mansion guards advances Revenge")
	if session.world.levers.has(150157): session.world.lever_sys.set_state(150157,1,0)
	ticks(3)
	check(v("q14h") == 2,"opening the quest chest completes Revenge")
	game.queue_free(); session.queue_free()
	for i in 8: await get_tree().process_frame
	TexUpscale.shutdown()
	FileAccess.open("user://lia-revenge-return.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("LIA_REVENGE_RETURN ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
