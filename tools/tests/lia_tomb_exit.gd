extends "story_coop_traps_net.gd"
## Real LiA tomb scripts and Session checkpoints. Mechanisms are activated
## directly; this checks quest/travel state, not a combat or walking route.
const TOMB := "gz11d1"
const NEEDLE := "q.gz11d1.q16ag"
const HALL := "q.gz11d1.fq13"
const EXIT := "z.gz11g"
const COMPAT = preload("res://src/game/script/story_compat.gd")

func v(key: String) -> float:
	return host.state.get_var(0,key)

func activate(id: int, count := 3) -> void:
	host.world.lever_sys.set_state(id,1,0)
	ticks(count)

func saved_progress() -> Dictionary:
	var heroes := []
	for rows: Array in host.state.heroes.values():
		for hero: Dictionary in rows:
			var record := {}
			for key: String in ["exp","str","dex","int","bag","quick","armor","weapon","spells"]:
				record[key]=hero.get(key)
			heroes.append(record)
	var levers := {}
	for id in host.world.levers: levers[id]=host.world.levers[id].state
	return {"quest":host.state.quest_items.duplicate(true),"money":host.state.money,
		"needle":v(NEEDLE),"hall":v(HALL),"heroes":heroes.duplicate(true),"levers":levers}

func startup_count() -> int:
	return host.world.vm.instances.filter(func(i):return i.sname=="Start").size()

func verify_exit(label: String) -> void:
	var ex: Dictionary = host.world.zone.exits[1]
	var center: Vector2 = ex.remove.get_center()
	check(v(EXIT)==0 and host.open_exit_at(center,0)==1,label+": original return exit is usable")
	for u: GameUnit in host.party_units(0):
		u.pos=center; u.resync_drawn()
	host._arm_exit(0,center,true,1)
	host._check_exits()
	check(MessageBox.is_up(host.game.hud._leave_box),label+": normal exit click opens confirmation")
	if host.game.hud._leave_box:
		host.game.hud._leave_box.queue_free(); host.game.hud._leave_box=null
		host.game.hud._close_menu()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"auto_exit":0},true)
	host=branch(false); host.set_physics_process(false)
	host.state=CampaignState.new()
	host.state.create_party("FGipat")
	host.state.add_party_unit("FGipat","Hero","Hero1")
	host.state.set_current_party("FGipat")
	check(host.state.campaign_id==CampaignProfile.ASTRAL,"fixture uses Lost in Astral data")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-fixture="):
			var old := CampaignState.load_from(arg.trim_prefix("--save-fixture="))
			check(old!=null and host._load_state("old_tomb",old),"affected pre-fix checkpoint loads")
			freeze(host); ticks(30)
			check(v(NEEDLE)==2 and v(HALL)==2,"old completed quests remain completed")
			verify_exit("pre-fix checkpoint")
			check(host.save_game("tomb-recovered")==OK and host.load_game("tomb-recovered"),"recovered checkpoint saves and reloads")
			freeze(host); ticks(30); verify_exit("second reload")
			await leave_tomb()
			await finish(); return

	host.state.set_var(0,"q.gz11g.q16g",1)
	host.state.set_var(0,"q.gz11g.q16g.1",2)
	host._reveal_travel_zones("gz9g_gz11g")
	check(v(EXIT)==1,"island map reveals the Rift before the first tomb visit")
	await host.enter_zone(TOMB,1,false); freeze(host); ticks(40)
	check(v(NEEDLE)==1 and v(EXIT)==1,"first visit keeps the authored Magic Needle gate")
	activate(2002381); activate(1030052); activate(4523,335)
	check(v(NEEDLE+".4")==2 and v(EXIT)==1,"flooding alone does not skip the needle objective")
	check(host.save_game("tomb-before-needle")==OK and host.load_game("tomb-before-needle"),"unfinished needle checkpoint reloads")
	freeze(host); ticks(30)
	check(v(NEEDLE)==1 and v(EXIT)==1,"reload does not unlock the unfinished first visit")
	activate(2002355)
	check(v(NEEDLE)==2 and v(EXIT)==0,"authored needle completion opens the first exit")
	check(not host.world.vm.instances.any(func(i):return i.sname=="Start"),"first-visit startup has finished")
	await host.enter_zone("gz11g",6,false); freeze(host)
	host._reveal_travel_zones("gz9g_gz11g")
	check(v(EXIT)==1,"later island travel reveals the Rift again")
	host.state.set_var(0,HALL,1)
	await host.enter_zone(TOMB,1,false); freeze(host); ticks(30)
	check(v(EXIT)==0,"return for Hall of the Great restores the tomb exit")
	activate(4357253)
	check(v(HALL)==2 and v(NEEDLE)==2,"original Hall chest completes the second quest")
	check(host.save_game("tomb-after-hall")==OK,"completed second-visit checkpoint saves")
	verify_exit("Hall of the Great revisit")
	negative_controls()
	# Construct the old broken flag in an otherwise real, completed checkpoint.
	# The baseline release also writes this state naturally on the revisit.
	host.state.set_var(0,EXIT,1)
	check(host.save_game("tomb-blocked")==OK,"affected checkpoint is retained for cross-build recovery")
	var before := saved_progress()
	check(host.load_game("tomb-blocked"),"affected completed checkpoint reloads")
	freeze(host)
	COMPAT.recover(host.world.vm); COMPAT.recover(host.world.vm)
	check(startup_count()==1,"repeated recovery schedules only one native startup")
	ticks(1)
	check(v(EXIT)==1 and startup_count()==1,"recovery retains the original startup wait")
	check(host.save_game("tomb-recovery-wait")==OK and host.load_game("tomb-recovery-wait"),"save/reload resumes recovery during its native wait")
	freeze(host)
	check(startup_count()==1,"loading a pending recovery does not duplicate startup")
	ticks(30)
	check(saved_progress()==before,"recovery preserves both quests, rewards, party and mechanisms")
	verify_exit("affected checkpoint")
	COMPAT.recover(host.world.vm)
	check(startup_count()==0,"open exit does not replay startup again")
	await leave_tomb()
	print("LIA_TOMB_EXIT ", JSON.stringify({"checks":checks,"failures":failures}))
	await finish()

func negative_controls() -> void:
	var vm := host.world.vm
	host.state.set_var(0,EXIT,1)
	for stage in [0,1,3]:
		host.state.set_var(0,NEEDLE,stage); COMPAT.recover(vm)
		check(startup_count()==0 and v(EXIT)==1,"uncompleted needle stage %d remains gated" % stage)
	host.state.set_var(0,NEEDLE,2)
	host.world.levers[4523].state=0; COMPAT.recover(vm)
	check(startup_count()==0,"closed water mechanism is not recovered")
	host.world.levers[4523].state=1
	host.state.set_var(0,"start_zone11dun1",0); COMPAT.recover(vm)
	check(startup_count()==0,"first-visit startup is not replayed")
	host.state.set_var(0,"start_zone11dun1",1)
	for name: String in ["Start","VCheck#0#5"]:
		var original: Dictionary=vm.ast.scripts[name]
		vm.ast.scripts[name]=original.duplicate(true)
		vm.ast.scripts[name].blocks[0].body.append([ScriptParser.S_CALL,"KillScript",[]])
		COMPAT.recover(vm)
		check(startup_count()==0,"modified "+name+" script is left alone")
		vm.ast.scripts[name]=original
	var original_world:=vm.ast.world
	vm.ast.world=[]; COMPAT.recover(vm)
	check(startup_count()==0,"modified WorldScript without Start is left alone")
	vm.ast.world=original_world
	host.state.campaign_id=CampaignProfile.ORIGINAL; COMPAT.recover(vm)
	check(startup_count()==0,"base campaign is left alone")
	host.state.campaign_id=CampaignProfile.ASTRAL
	host.world.zone.id="gz11d2"; COMPAT.recover(vm)
	check(startup_count()==0,"other dungeon is left alone")
	host.world.zone.id=TOMB

func leave_tomb() -> void:
	if host.open_exit_at(host.world.zone.exits[1].remove.get_center(),0)!=1: return
	host.apply_command({"t":"leave_exit","exit":1},0)
	check(await until(func():return host.zone_id=="gz11g" and not host.loading_game),"confirmed exit returns to the Rift")
	freeze(host)
	check(host.party_units(0).size()==1 and v(NEEDLE)==2 and v(HALL)==2,"travel preserves party and completed quests")
