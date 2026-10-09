extends "./story_coop_traps_net.gd"
## Original map startup and pending VM are retained; prepare only party, amulet
## and positions, pause world AI, and run the real authored follow/return scripts.
var evidence := {}
var capture_delay := false

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz6g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func stop_branches() -> void:
	for s: Session in [client,host]:
		if is_instance_valid(s):
			var peer := s.multiplayer.multiplayer_peer
			s.online = false; s.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			if peer: peer.close()
	for root: Node in branches: root.queue_free()
	branches.clear(); await frames(8)
	host = null; client = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_delay = "--capture-delay" in OS.get_cmdline_user_args()
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	var origin := CoopProgress.fresh_state()
	origin.heroes[0][0].name = "VM Guest"; origin.heroes[0][0].str = 31.0
	origin.money = 222; origin.items = ["rune:e1"]; origin.visited["gz6g"] = true
	origin.quest_items.dragonamulet = true
	check(origin.save(SaveInfo.path("vm_origin")) == OK,"disposable guest origin written")
	var original_bytes := FileAccess.get_file_as_bytes(SaveInfo.path("vm_origin"))
	host = branch(false); host.state = CoopProgress.fresh_state()
	host.state.heroes[0][0].name = "VM Host"; host.state.heroes[0][0].str = 91.0
	host.state.money = 9000; host.state.items = ["rune:r1"]; host.state.quest_items.dragonamulet = true
	for n in [2,3]:
		var h: Dictionary = host.state.heroes[0][0].duplicate(true)
		h.merc = n; h.unit_name = "merc"+str(n); h.party = ""; h.controller = 0
		host.state.mercs[n] = h
	host.set_physics_process(false); GameData.player_name = "VM Host"
	check(host.host(29943,2) == OK,"real ENet host opens")
	client = branch(true); CoopProgress.bring_slot = "vm_origin"; GameData.player_name = "VM Guest"
	check(client.join("127.0.0.1",29943) == OK,"guest imports private campaign over ENet")
	check(await until(func():return host.coop.joiners.has("vm guest") and host.players.size()==2 and client.my_index==1),"host receives guest import")
	if failures: await done(); return
	CampaignState.watch = host.coop._on_var
	await host.enter_zone("gz6g",1,false); freeze(host)
	check(await until(loaded),"guest receives original dragon map")
	if failures: await done(); return
	freeze(client)
	var entry: Dictionary = host.coop.joiners["vm guest"]
	print("ENTRY ",JSON.stringify({"in_sync":entry.in_sync,"clean":entry.clean,"present":entry.present,"visited":entry.visited}))
	check(entry.in_sync and entry.clean and entry.present,"guest eligible for complete zone checkpoint")
	var vm := host.world.vm
	check(vm.instances.size() > 0,"original startup VM retained")
	for u: GameUnit in host.party_units(0): u.pos = Vector2(200,200); u.resync_drawn()
	var guest := visitor(); check(guest != null,"guest owns separate deployed hero")
	if guest == null: await done(); return
	guest.pos = Vector2(200,210); guest.resync_drawn(); ticks(4)
	var dragon := vm._get_object(1155) as GameUnit
	check(dragon != null and vm.globals.get("YDragon") == dragon,"original WorldScript resolves authored dragon")
	check(vm.instances.size() > 20,"full original pending map VM survives startup")
	if dragon == null: await done(); return
	guest.pos = dragon.pos + Vector2(2,0); guest.resync_drawn(); ticks(3 if capture_delay else 8)
	if capture_delay:
		check(vm.instances.any(func(i):return i.sname=="VTriger#0#401#RemakeParticipant" and not i.frames.is_empty() and i.wait_until>vm.time),"real guest follow branch is captured during original three-tick Sleep")
	else:
		check(dragon.mode == "follow" and dragon.mode_data.get("target") == guest,"original delayed script selects imported guest as dragon target")
		check(host.state.get_var(0,"GFol") == 1.0,"original follow flag is active")
	if failures: await done(); return
	guest.pos = dragon.pos + Vector2(20,0); guest.resync_drawn()
	var before := client.coop.merged_count
	var host_vm_before := var_to_bytes(vm.save_state())
	host.coop.send_all()
	var expected_seq := int(entry.seq)
	check(await until(func():
		if client.coop.merged_count<=before or client.coop.last_merged.is_empty(): return false
		var received := CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
		return received != null and int(received.coop.get("applied",{}).get(entry.sid,{}).get("seq",-1))>=expected_seq
	),"real progress RPC writes the requested checkpoint sequence")
	check(var_to_bytes(vm.save_state())==host_vm_before,"progress packaging does not change the authority's live pending VM")
	if failures: await done(); return
	var returned := CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
	check(returned != null and returned.current_zone == "gz6g","returned campaign retains eligible authored zone")
	if returned == null: await done(); return
	check(returned.zones.gz6g.vm.instances.size() == vm.instances.size(),"package preserves actual pending VM without clearing instances")
	check(CoopProgress.main_hero(returned).str == 31.0 and CoopProgress.main_bag(returned).money == 222,"returned campaign keeps guest personal stats and purse")
	evidence.host_vm = vm.save_state(); evidence.returned_vm = returned.zones.gz6g.vm
	evidence.guest_uid = guest.uid; evidence.guest_pos = [guest.pos.x,guest.pos.y]
	check(returned.save(SaveInfo.path("vm_return")) == OK,"returned checkpoint copied to disposable solo slot")
	check(FileAccess.get_file_as_bytes(SaveInfo.path("vm_origin")) == original_bytes,"original imported slot is byte-identical")
	await stop_branches(); CoopProgress.bring_slot = ""
	host = branch(false); host.set_physics_process(false)
	check(host.load_game("vm_return"),"independent offline Session loads returned checkpoint")
	freeze(host); vm = host.world.vm
	var solo := host.party_units(0)[0] as GameUnit
	dragon = vm._get_object(1155) as GameUnit
	check(solo.pos.distance_to(Vector2(evidence.guest_pos[0],evidence.guest_pos[1]))<0.01,"solo recipient keeps guest saved position")
	check(host.state.heroes.keys() == [0],"solo return contains only local player roster")
	if not capture_delay:
		check(dragon != null and dragon.mode == "follow","script-selected follow mode resumes")
		check(dragon != null and dragon.mode_data.get("target") == solo,"script-selected target resumes on recipient's solo hero")
	evidence.solo_target_uid = dragon.mode_data.get("target").uid if dragon.mode_data.get("target") else null
	evidence.solo_uid = solo.uid; evidence.solo_vm = vm.save_state()
	ticks(50)
	check(dragon.mode == "follow" and dragon.mode_data.get("target") == solo,"pending original VM retains valid target outside rearm proximity")
	check(host.state.get_var(0,"GFol") == 1.0,"pending original departure has not been skipped")
	check(vm.instances.filter(func(i):return i.sname=="VCheck#0#362").size()==1 and not vm.instances.any(func(i):return i.sname=="VCheck#0#390"),"recipient has one native departure thread without an idle duplicate follow")
	dragon.pos.y=294; dragon.resync_drawn(); ticks(4)
	check(dragon.mode=="guard" and dragon.mode_data.get("point")==Vector2(78,336),"returned branch reaches the original guarded departure")
	check(host.state.get_var(0,"GFol")==1.0,"original departure cooldown has not been skipped")
	ticks(155)
	check(host.state.get_var(0,"GFol")==0.0 and vm.instances.filter(func(i):return i.sname=="VCheck#0#390").size()==1,"original cooldown rearms recipient follow exactly once")
	await done()

func done() -> void:
	evidence.checks = checks; evidence.failures = failures
	FileAccess.open("user://coop-vm-solo.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	await stop_branches()
	print("COOP_VM_SOLO ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
