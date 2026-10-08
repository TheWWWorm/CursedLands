extends "coop_story.gd"
## Prepared Shelter conversation completion, actual original handler and ENet.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var h:=branch("Host",true); host=h.s; hg=h.g
	var c:=branch("Client",false); client=c.s; cg=c.g
	require(host.host(29908,2)==OK)
	GameData.player_name="Shelter Guest"
	require(client.join("127.0.0.1",29908)==OK)
	require(await until(func():return host.players.size()==2))
	host.set_physics_process(false); client.set_physics_process(false)
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero","Shelter Guest")
	for player in [0,1]:
		await host.enter_zone("bz3h",1,false)
		# The fixture advances the original script itself. Disable the world's
		# frame clock too; disabling Session alone leaves world simulation live.
		host.world.set_physics_process(false)
		require(await until(func():return client.zone_id=="bz3h" and not client.loading_game and not host.loading_game))
		var old_host:=weakref(host.world); var old_client:=weakref(client.world)
		var vm:=host.world.vm
		for i in 5:vm.tick(GameUnit.TICK)
		vm.instances.clear()
		vm.briefings.active="b.Glav.brief_49"
		vm.briefings.active_player=player
		vm.briefings._pending_dialog={}
		if player==1:
			client.submit({"t":"dialog_done","id":"b.Glav.brief_49"})
			await get_tree().create_timer(0.4).timeout
		else:host.apply_command({"t":"dialog_done","id":"b.Glav.brief_49"},0)
		for i in 4:vm.tick(GameUnit.TICK)
		check(await until(func():return host.zone_id=="gz3h" and client.zone_id=="gz3h" and not host.loading_game and not client.loading_game),
			"Shelter original handler directly transfers both peers, initiator "+str(player))
		check(not host.map_open and not client.map_open and host.travel_options.is_empty(),"Shelter departure has no empty map choice")
		check(host.party_units(0).size()==1 and host.party_units(1).size()==1,"both players reach the field map")
		await get_tree().create_timer(0.2).timeout
		check(old_host.get_ref()==null and old_client.get_ref()==null,"Shelter worlds released on both peers")
	check(host.save_game("shelter_departed")==OK,"Shelter departure state saves")
	check(await host.load_game_shown("shelter_departed"),"Shelter departure state reloads")
	require(await until(func():return not host.loading_game and not client.loading_game and client.zone_id=="gz3h"))
	check(host.state.get_pvar(1,"b.Glav.brief_49")==2,"guest conversation completion survives reload")
	client.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for root in branches:root.queue_free()
	for i in 10:await get_tree().process_frame
	print("SHELTER_DEPARTURE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
func _process(_dt: float) -> void:pass
