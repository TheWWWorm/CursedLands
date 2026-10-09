extends "story_coop_traps_net.gd"
## Inspect a supplied save copy without preparing quests or replacing VM state.
## The optional causal phase invokes real actor deaths, not combat or success
## flags. All saves and screenshots stay in the runner's disposable profile.
const QUEST := "q.gz5g.q22g"
const SCRABS := [19,20,15,16,17,39,41,40,21,22,23]
const SURVIVORS := [22,23]
var source_file := ""
var evidence := {}

func quest_state() -> Array:
	var out := []
	for suffix in ["",".1",".2",".3",".4",".5",".6",".7",".8"]:
		out.append(host.state.get_var(0,QUEST+suffix))
	return out

func actor(u: GameUnit) -> Dictionary:
	if u == null: return {"missing":true}
	return {"uid":u.uid,"name":u.display_name,"pos":[u.pos.x,u.pos.y],"hp":u.hp,
		"dead":u.dead,"hidden":u.hidden,"fogged":u.fogged,"visible":u.visible,
		"in_tree":u.is_inside_tree(),"looted":host.world.looted.has(u.uid),
		"model":u.model.template if u.model else "","model_in_tree":u.model.is_inside_tree() if u.model else false,
		"model_visible":u.model.is_visible_in_tree() if u.model and u.model.is_inside_tree() else false}

func native_dead(u: GameUnit) -> bool:
	var inst := ScriptVM.Instance.new()
	inst.locals.subject = u
	return bool(host.world.vm._call("IsDead",[[ScriptParser.N_VAR,"subject"]],inst))

func refresh_sight() -> void:
	var fog: UnitFog = host.game.get_node("UnitFog")
	fog._t = 0.0; fog._process(0.0)

func write_report() -> void:
	evidence.checks = checks; evidence.failures = failures
	FileAccess.open("user://queen-user-save.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	print("QUEEN_USER_SAVE ",JSON.stringify(evidence))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--queen-save="): source_file = arg.trim_prefix("--queen-save=")
	check(not source_file.is_empty() and FileAccess.file_exists(source_file),"supplied read-only source exists")
	if failures: await finish(); return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(source_file,SaveInfo.path("user-queen"))==OK,"copy source into disposable save slot")
	evidence.source_sha256 = FileAccess.get_sha256(source_file)
	host = branch(false); check(host.host(29949,2)==OK,"open inspection host")
	host.set_physics_process(false)
	check(host.load_game("user-queen"),"load actual supplied save through Session")
	if host.world == null: write_report(); await finish(); return
	freeze(host)
	evidence.loaded_zone = host.zone_id; evidence.loaded_quest = quest_state()
	check(host.zone_id=="bz3g","autosave restores actual Dead City return state")
	check(quest_state().slice(0,3)==[1.0,2.0,1.0],"saved queen complete and small creatures pending")
	await host.enter_zone("gz5g",1,false); freeze(host)
	check(host.zone_id=="gz5g","normal travel restores saved cave")
	ticks(12); refresh_sight()
	evidence.return_quest = quest_state()
	evidence.units = []
	var alive: Array[int] = []
	for id: int in SCRABS:
		var u: GameUnit = host.world.units.get(id,host.world.looted.get(id))
		evidence.units.append(actor(u))
		check(u!=null,"required creature %d retains its saved actor"%id)
		if u and not u.dead: alive.append(id)
		check(native_dead(u)==(id not in SURVIVORS),"original IsDead reads saved creature %d accurately"%id)
	check(alive==SURVIVORS,"exactly saved creatures 22 and 23 remain alive")
	var queen: GameUnit = host.world.looted.get(1000027)
	evidence.queen = actor(queen)
	check(not host.world.units.has(1000027),"saved looted weakened queen does not resurrect")
	evidence.queen_saved_looted = host.state.zones.gz5g.looted.has(1000027)
	check(host.world.vm.globals.Scrabs.size()==11,"restored authored Every retains all eleven references")
	check(quest_state().slice(0,3)==[1.0,2.0,1.0],"original VM correctly leaves incomplete group pending")
	var leader: GameUnit = host.party_units(0)[0]
	evidence.party_start = actor(leader); evidence.paths = []
	for id: int in SURVIVORS:
		var u: GameUnit = host.world.units[id]
		var route := leader._path_to(u.pos,u)
		var length := 0.0; var previous := leader.pos
		for p: Vector2 in route: length += previous.distance_to(p); previous=p
		evidence.paths.append({"uid":id,"points":route.size(),"length":length,
			"endpoint_distance":route[-1].distance_to(u.pos) if not route.is_empty() else -1})
		check(not route.is_empty() and route[-1].distance_to(u.pos)<leader.melee_reach(u),"ordinary attack path reaches survivor %d"%id)
	# Diagnostic observer placement on each ordinary attack route proves the
	# original living actor can be seen through the actual party-sight code.
	# This is not a walking/combat playthrough. NPC positions, HP, scripts and
	# fog settings are untouched; unrelated simulation remains frozen.
	evidence.approaches = []
	for id: int in SURVIVORS:
		var u: GameUnit = host.world.units[id]
		var saved_pos := u.pos
		var route := leader._path_to(u.pos,u)
		var observer := Vector2.INF
		for index in range(route.size()-1,-1,-1):
			var p: Vector2 = route[index]
			if p.distance_to(u.pos)<3.0 or p.distance_to(u.pos)>9.0: continue
			leader.pos=p; leader.resync_drawn(); refresh_sight()
			if not u.fogged:
				observer=p; break
		evidence.approaches.append({"uid":id,"method":"diagnostic observer placement on native attack path",
			"observer":[leader.pos.x,leader.pos.y],"creature":actor(u),
			"sight_ray":host.world.sight_ray(leader,u),"listed":UnitFog.listed(host.game,u)})
		check(observer!=Vector2.INF and not u.hidden and not u.fogged and u.visible and UnitFog.listed(host.game,u),"survivor %d is visible to nearby diagnostic observer"%id)
		check(u.pos==saved_pos and u.hp==60.0 and not u.dead,"survivor %d retains saved placement and full health"%id)
		if DisplayServer.get_name()!="headless" and observer!=Vector2.INF:
			host.game.rig.distance=18.0
			host.game.rig.focus(EISpace.pos(u.pos.x,u.pos.y,host.world.ground_at(u.pos.x,u.pos.y)))
			await frames(8); await RenderingServer.frame_post_draw
			check(u.model.is_visible_in_tree() and not u.screen_rects(host.game.rig.camera).is_empty(),"survivor %d has a visible projected model"%id)
			check(get_viewport().get_texture().get_image().save_png("user://queen-survivor-%d.png"%id)==OK,"capture actual visible survivor %d"%id)
	check(host.save_game("user-queen-inspected")==OK,"inspection state writes only disposable slot")
	# Reload the supplied copy before the isolated causal proof so the
	# observer placement cannot change the initial quest boundary.
	check(host.load_game("user-queen"),"reload untouched copied source for causal proof")
	freeze(host); await host.enter_zone("gz5g",1,false); freeze(host)
	leader = host.party_units(0)[0]
	# Actual deaths execute the restored original VM.
	host.world.units[22].die(leader); ticks(12)
	check(quest_state().slice(0,3)==[1.0,2.0,1.0],"one remaining death cannot complete the two-creature gate")
	host.world.units[23].die(leader); ticks(12)
	check(quest_state().slice(0,3)==[2.0,2.0,2.0],"both real death events complete the original saved quest")
	check(host.state.get_var(0,"b.SKD.Dr22")==1 and host.state.get_var(0,"z.gz5g")==2,"original dragon return topic and cave completion unlock")
	evidence.completed_quest=quest_state()
	check(host.save_game("user-queen-causal-complete")==OK,"save causal completion to disposable slot")
	check(host.load_game("user-queen-causal-complete"),"reload causal result normally")
	freeze(host); ticks(12)
	check(quest_state().slice(0,3)==[2.0,2.0,2.0],"authored completion persists after normal reload")
	check(FileAccess.get_sha256(source_file)==evidence.source_sha256,"supplied source remains byte-identical")
	write_report(); await finish()
