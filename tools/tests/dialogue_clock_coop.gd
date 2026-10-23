extends "coop_trade.gd"
## A real ENet host owns dialogue timing; guests cannot change it locally.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"coop_clock":1},true)
	host = peer("DialogueHost", true); client = peer("DialogueGuest", false)
	check(host.host(30147,2) == OK and client.join("127.0.0.1",30147) == OK, "dialogue peers connect")
	check(await until(func():return host.players.size() == 2), "both dialogue peers admitted")
	if failures: get_tree().quit(1); return
	host.state = CampaignState.new()
	host.state.ensure_hero(0,"Human Hero"); host.state.ensure_hero(1,"Human Hero","Guest")
	await host.enter_zone("bz1g",1,false)
	check(await until(func():return client.world != null and not client._remote_loading), "both peers enter camp")
	for s: Session in [host, client]:
		s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
		if s.world.vm: s.world.vm.instances.clear()
	check(not ModStore.editable("difficulty",host).is_empty(), "network difficulty stays Normal")
	for paused in [false,true]:
		host.field_speed = 1
		host._apply_clock(paused,1); host._send_clock()
		check(await until(func():return client.clock_speed == 1 and client.clock_paused == paused), "accelerated clock reaches guest")
		client.begin_dialogue_clock()
		check(client.clock_speed == 1 and client.clock_paused == paused, "guest cannot override the authority clock")
		host.broadcast({"t":"dialog","id":"test","phrases":[{}],"staging":true})
		check(await until(func():return not client.clock_paused and client.clock_speed == 0), "dialogue resets both peers to normal speed")
		check(not host.clock_paused and host.clock_speed == 0 and host.field_speed == 0, "host discards accelerated field speed")
		host.broadcast({"t":"dialog_close","id":"test"})
	get_tree().paused = false; Engine.time_scale = 1
	host.online = false; client.online = false
	client.multiplayer.multiplayer_peer.close(); host.multiplayer.multiplayer_peer.close()
	for root: Node in roots: root.queue_free()
	for i in 8: await get_tree().process_frame
	print("DIALOGUE_CLOCK_COOP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
