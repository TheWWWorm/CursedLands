extends "story_coop_traps_net.gd"
## Actual base cave scripts, poison-key use, replacement queen, and shared
## ENet/save state. Unrelated combat/pathfinding is paused; deaths use the
## ordinary actor death path, never fabricated quest completion flags.
const QUEST := "q.gz5g.q22g"
const FOUNTAINS := [4525,4524,4523]
var source := 3

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz5g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true); GameData.player_name = "Cave Guest"
	check(client.join("127.0.0.1",29943) == OK,"connect cave guest")
	var ready := await until(loaded)
	check(ready,"guest receives cave and shared quest state")
	if ready: freeze(client)
	return ready

func quest_state(s: Session) -> Array:
	var out := [s.state.get_var(0,QUEST)]
	for i in range(1,9): out.append(s.state.get_var(0,QUEST+"."+str(i)))
	return out

func shared_state(label: String) -> void:
	host.sync_state()
	check(await until(func():return quest_state(client)==quest_state(host),10),label)
	print("CAVE_STATE ",label," ",quest_state(host))

func save_reload(slot: String) -> bool:
	check(host.save_game(slot)==OK,"save "+slot)
	check(await host.load_game_shown(slot),"load "+slot)
	freeze(host)
	var ready := await until(loaded)
	check(ready,"guest receives "+slot)
	if ready: freeze(client)
	return ready

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = clampi(arg.trim_prefix("--source=").to_int(),1,3)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	print("CAVE_ROUTE source=",source," title=",GameData.text("quest q22g").get_slice("\n",0))
	host = branch(false); check(host.host(29943,2)==OK,"open cave host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero"); host.set_physics_process(false)
	await host.enter_zone("gz5g",1,false); freeze(host)
	var vm := host.world.vm
	vm.briefings._rewards("Dr20") # The original dragon briefing grants this quest and one poison.
	check(host.state.quest_items.has("dragonpoison") and host.state.get_var(0,QUEST)==1,"original Dr20 reward grants quest and poison")
	ticks(24)
	var leader: GameUnit = host.party_units(0)[0]
	# Discover all three alternatives using the real distance checks.
	for nid: int in FOUNTAINS:
		var p: Vector3 = host.world.objects[nid].get_meta("ei").position
		leader.pos = Vector2(p.x,p.y); leader.resync_drawn(); ticks(6)
	ticks(6)
	print("CAVE_INITIAL ",quest_state(host)," queen=",host.world.units.get(14))
	check(quest_state(host)==[1.0,1.0,1.0,2.0,1.0,2.0,1.0,2.0,1.0],"all three discovered poison alternatives are initially available")
	if not await connect_guest(): await finish(); return
	if not await save_reload("cave-before-poison"): await finish(); return
	vm = host.world.vm
	var guest := visitor()
	check(guest!=null,"guest has an authoritative actor")
	if guest==null: await finish(); return
	check(vm._lever_science_ok(guest,FOUNTAINS[source-1]),"guest can use the shared original poison key")
	vm._use_lever(guest,FOUNTAINS[source-1]); ticks(24); await frames(3); ticks(6)
	check(int(host.world.levers[FOUNTAINS[source-1]].state)==1,"selected original source switches to poisoned state")
	for i in 3:
		check(host.state.get_var(0,QUEST+"."+str(4+i*2))==(2 if i==source-1 else 3),"source "+str(i+1)+" retains the original success/failure branch")
	check(not host.state.quest_items.has("dragonpoison"),"single poison item is consumed by the original script")
	check(host.world.units.has(1000027) and not host.world.units.has(14),"original queen is replaced by the authored weakened queen")
	print("CAVE_ALIVE_SCRABS ",vm.globals.Scrabs.filter(func(u):return is_instance_valid(u) and not u.dead).map(func(u):return u.uid))
	check(vm.globals.Scrabs.filter(func(u):return is_instance_valid(u) and not u.dead).size()==[5,3,0][source-1],"poison kills the authored subset of small creatures")
	check(host.state.get_var(0,QUEST+".1")==1,"removing the healthy queen does not count as killing the weakened queen")
	await shared_state("both peers see poison outcome")
	# Previously killed creatures must still count after their corpses are
	# looted, even though a removed living queen no longer counts as dead.
	for u in vm.globals.Scrabs:
		if is_instance_valid(u) and u.dead: host.take_loot(guest,u)
	check(host.world.looted.size()==[6,8,11][source-1],"poisoned creatures can be looted before the remaining kills")
	if not await save_reload("cave-after-poison"): await finish(); return
	vm = host.world.vm
	check(host.world.units.has(1000027) and not host.world.units[1000027].dead,"living weakened queen survives save/reload")
	check(host.state.get_var(0,QUEST+".1")==1,"save/reload preserves pending queen objective")
	var queen: GameUnit = host.world.units.get(1000027)
	if queen: queen.die(visitor())
	ticks(12)
	check(host.state.get_var(0,QUEST+".1")==2,"killing weakened queen completes original queen objective")
	check(host.state.get_var(0,QUEST)==(2 if source==3 else 1),"overall quest also requires every surviving small creature")
	if source!=3:
		if not await save_reload("cave-queen-dead"): await finish(); return
		vm = host.world.vm
		check(host.state.get_var(0,QUEST)==1 and host.state.get_var(0,QUEST+".1")==2,"queen-dead incomplete route survives save/reload")
		for u in vm.globals.Scrabs:
			if is_instance_valid(u) and not u.dead: u.die(visitor())
		ticks(12)
	check(host.state.get_var(0,QUEST)==2 and host.state.get_var(0,QUEST+".2")==2,"original quest completes after queen and all small creatures die")
	check(host.state.get_var(0,"b.SKD.Dr22")==1 and host.state.get_var(0,"z.gz5g")==2,"authored dragon return topic and cave completion unlock")
	await shared_state("both peers see completed quest")
	if not await save_reload("cave-complete"): await finish(); return
	ticks(6); await shared_state("completed quest persists on both peers after reload")
	client.multiplayer.multiplayer_peer.close()
	var old_root: Node = branches.back(); branches.erase(old_root); old_root.queue_free()
	check(await until(func():return host.players.size()==1),"host observes guest disconnect")
	if await connect_guest(): await shared_state("reconnected guest retains original completed quest")
	print("CAVE_QUEEN_ROUTE source=",source," ",checks," checks ",failures," failures")
	await finish()
