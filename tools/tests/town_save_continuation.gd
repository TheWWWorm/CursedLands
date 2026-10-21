extends "campaign_clock_coop.gd"
## Real town reloads preserve clocks and authored waiting script state.
## Original branch capture establishes the load route; original map bodies
## supply the waiting conditions and continuation. This is not a complete
## original save-file or native multiplayer replay.
var authored := {}

func stop(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.set_process(false); s.game.rig.set_process(false)
	if s.world.vm: s.world.vm.briefings._check=INF

func thread_state(name: String) -> Dictionary:
	for row: Dictionary in host.world.vm.save_state().instances:
		if row.s==name: return row
	return {}

func reload_town(slot: String) -> void:
	check(host.save_game(slot)==OK,"save actual town scene")
	var previous := client.world.get_instance_id()
	check(await host.load_game(slot),"reload actual town scene")
	stop(host)
	check(await until(func():return client.world!=null and client.world.get_instance_id()!=previous and not client.loading_game and not client._remote_loading),"guest completes town reload")
	stop(client)
	check(host.world.zone.type=="brief" and client.world.zone.type=="brief","both peers restore the town scene")

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	var astral := GameData.campaign_id==CampaignProfile.ASTRAL
	var campaign := "lost_in_astral" if astral else "original"
	var references: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("fixtures/original_save_route.json")))
	var routes: Array = references.campaigns[campaign].cases
	check(routes[0].route=="mission" and routes[2].route=="mission" and routes[1].route=="zone_entry","original load branch restores field/town mission state and treats global map separately")
	host=peer("TownSaveHost",true);client=peer("TownSaveGuest",false)
	check(host.host(30048,2)==OK and client.join("127.0.0.1",30048)==OK,"town save peers connect")
	check(await until(func():return host.players.size()==2),"two town save players")
	if failures: get_tree().quit(2); return
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Town Guest")
	host.state.set_var(0,"gtime",35.75);host.state.set_scene_hour(0.3);host.set_physics_process(false)
	var town := "bz5h" if astral else "bz1g"
	await enter(town); host.world.vm.instances.clear()
	snapshot("enter town",11.75,35.75,false)
	host.world.vm._call("FixWorldTime",[[P.N_NUM,0.3]],ScriptVM.Instance.new())
	check(await until(func():return client.world.clock_fixed and is_equal_approx(client.state.world_time,0.3)),"town scene freeze reaches guest")
	await command("GSSetVar",19.0)
	# A completed original hire topic waiting for a script consumer must not
	# be rewritten as an available topic by deployment during a full reload.
	for owner in [0,1]:
		host.state.set_pvar(owner,"amerc_2",1)
		host.state.set_pvar(owner,"b.merc2.n1_2",2)
	var name := "Fire#12" if astral else "VCheck#0#47"
	var next := "Fire#11" if astral else "VTriger#0#48"
	check(host.world.vm.ast.scripts.has(name) and host.world.vm.ast.scripts.has(next),"actual town contains original waiting routine and continuation")
	if not astral:
		host.state.set_var(0,"GTwolf",0)
		host.state.set_var(0,"q.gz3g.q1g",1)
	host.world.vm.spawn(name,[null])
	for i in 7: host.world.vm.tick(ScriptVM.POLL)
	var before := thread_state(name)
	check(not before.is_empty(),"original town routine is pending before save")
	if astral: check(before.has("sc") and before.st==6,"LiA fire routine is partway through its authored Sleep(30)")
	else: check(before.b==-1 and before.f.is_empty(),"Gipath deadline waits while elapsed time is below 47 hours")
	authored={"zone":town,"script":name,"next":next,"body":host.world.vm.ast.scripts[name],"before":before}
	await reload_town("town-script-continuation")
	snapshot("full town reload",0.3,19.0,true)
	var after := thread_state(name);authored.after=after
	check(after==before,"full town load preserves exact authored thread frame, locals, sleep and poll state")
	for owner in [0,1]:
		check(host.state.get_pvar(owner,"b.merc2.n1_2")==2,"pending completed hire flag survives for player %d"%owner)
	check(client.state.get_pvar(1,"b.merc2.n1_2")==2,"guest receives its saved completed hire flag")
	if astral:
		for i in 23: host.world.vm.tick(ScriptVM.POLL)
		check(thread_state(name).get("st",-1)==29 and thread_state(next).is_empty(),"restored fire timer does not finish a tick early")
		host.world.vm.tick(ScriptVM.POLL)
	else:
		for i in 3: host.world.vm.tick(ScriptVM.POLL)
		check(thread_state(next).is_empty(),"restored quest timer remains pending below its deadline")
		await command("GSSetVar",47.0)
		host.world.vm.tick(ScriptVM.POLL)
		check(thread_state(next).is_empty(),"authored strict deadline does not trigger at exactly 47 hours")
		await command("GSSetVar",48.0)
		host.world.vm.tick(ScriptVM.POLL)
	check(not thread_state(next).is_empty() and thread_state(name).is_empty(),"restored routine advances once to its original continuation")
	authored.continuation=thread_state(next)
	# Preserve both the running and frozen scene variants. This is a full
	# town save, so it must not take the ordinary entry gtime-modulo reset.
	host.world.vm.instances.clear()
	host.world.vm._call("RunWorldTime",[[P.N_NUM,22.75]],ScriptVM.Instance.new())
	await command("GSSetVar",50.5)
	check(await until(func():return not client.world.clock_fixed and is_equal_approx(client.state.world_time,22.75)),"running town hour reaches guest")
	await reload_town("town-running-clock")
	snapshot("running town reload",22.75,50.5,false)
	FileAccess.open("user://town-save-continuation.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":campaign,"checks":checks,"failures":failures,"trace":trace,"authored":authored},"\t"))
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root: Node in roots: root.queue_free()
	for i in 12: await get_tree().process_frame
	print("TOWN_SAVE_CONTINUATION ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
