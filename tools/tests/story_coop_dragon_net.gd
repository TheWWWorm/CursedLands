extends "./story_coop_traps_net.gd"
## Actual base-map dragon, late ENet guest, saved follow target and original
## delayed departure. Unrelated AI/story is paused; this is not a quest run.

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz6g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client=branch(true); GameData.player_name="Dragon Guest"
	check(client.join("127.0.0.1",29936)==OK,"connect dragon guest")
	var ready:=await until(loaded)
	check(ready,"guest receives dragon map")
	if ready: freeze(client)
	return ready

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	host=branch(false); check(host.host(29936,2)==OK,"open local dragon host")
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	for n in [2,3]:
		var h: Dictionary=host.state.heroes[0][0].duplicate(true)
		h.merc=n; h.unit_name="merc"+str(n); h.party=""; h.controller=0
		host.state.mercs[n]=h
	host.set_physics_process(false)
	await host.enter_zone("gz6g",1,false); freeze(host)
	var vm:=host.world.vm; vm.instances.clear()
	var dragon:=vm._get_object(1155) as GameUnit
	check(dragon!=null and not dragon.dead,"original mapped amulet dragon is alive")
	if dragon==null: await finish(); return
	vm.globals.YDragon=dragon
	host.state.quest_items[vm._quest_item_name(55.0)]=true
	for u: GameUnit in host.party_units(0): u.pos=Vector2(200,200); u.resync_drawn()
	for name in ["VCheck#0#390","VCheck#0#393","VCheck#0#404"]: vm.spawn(name,[null],"WorldScript")
	ticks(3)
	check(vm._story_records().size()==3,"three original story roles precede late guest")
	if not await connect_guest(): await finish(); return
	var u:=visitor(); check(u!=null,"late guest has its own controllable actor")
	if u==null: await finish(); return
	u.pos=dragon.pos+Vector2(2,0); u.resync_drawn(); ticks(8)
	check(dragon.mode=="follow" and dragon.mode_data.get("target")==u,"original dragon follows the extra ENet guest")
	check(host.state.get_var(0,"GFol")==1,"guest follow sets the authored flag")
	if failures: await finish(); return
	check(await sync_visitor(u),"client receives guest position beside dragon")
	var previous_uid := u.uid
	host.redeploy_party(1); u=visitor()
	check(u!=null and u.uid!=previous_uid,"party redeployment replaces the guest body")
	check(dragon.mode_data.get("target")==u,"dragon follows the replacement guest body")
	check(await sync_visitor(u),"client receives the redeployed guest")
	check(host.save_game("guest-dragon")==OK,"save dragon following the guest")
	check(await host.load_game_shown("guest-dragon"),"reload dragon follow state"); freeze(host)
	check(await until(loaded),"client receives reloaded dragon map"); freeze(client)
	vm=host.world.vm; dragon=vm._get_object(1155) as GameUnit; u=visitor()
	check(dragon!=null and dragon.mode=="follow" and dragon.mode_data.get("target")==u,"saved AI target resolves to the current guest body")
	check(dragon.get_meta("um",{}).get("fear")==0 and dragon.get_meta("um",{}).get("fight")=="aggression","saved dragon keeps script-selected fear and aggression")
	client.multiplayer.multiplayer_peer.close()
	var old_root: Node=branches.back(); branches.erase(old_root); old_root.queue_free()
	check(await until(func():return host.players.size()==1),"host sees real guest disconnect")
	check(host.save_game("guest-dragon-offline")==OK,"save follow target while its guest is disconnected")
	check(await host.load_game_shown("guest-dragon-offline"),"reload while target guest is absent"); freeze(host)
	dragon=host.world.vm._get_object(1155) as GameUnit
	check(dragon.mode=="follow" and dragon.mode_data.get("target")==null,"missing guest cannot resolve to an unrelated unit")
	if not await connect_guest(): await finish(); return
	u=visitor()
	check(dragon.mode_data.get("target")==u and u.controller==1,"reconnect preserves dragon target ownership")
	dragon.pos.y=294; dragon.resync_drawn(); ticks(4)
	check(dragon.mode=="guard" and dragon.mode_data.get("point")==Vector2(78,336) and dragon.mode_data.get("radius")==7.0,
		"dragon crossing original boundary receives authored return order")
	check(host.state.get_var(0,"GFol")==1,"departure keeps flag through the original wait")
	check(host.save_game("guest-dragon-departure")==OK,"save original departure cooldown")
	check(await host.load_game_shown("guest-dragon-departure"),"reload departure cooldown"); freeze(host)
	check(await until(loaded),"client receives saved departure"); freeze(client)
	dragon=host.world.vm._get_object(1155) as GameUnit
	check(dragon.mode=="guard" and dragon.mode_data.get("point")==Vector2(78,336),"saved departure keeps dragon's home order")
	ticks(155)
	check(host.state.get_var(0,"GFol")==0,"departure clears flag after original wait")
	check(await sync_visitor(dragon),"client receives dragon departure position")
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if is_instance_valid(s):
			s.online=false
			if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root: Node in branches:
		if is_instance_valid(root): root.queue_free()
	await frames(8)
	print("STORY_COOP_DRAGON_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
