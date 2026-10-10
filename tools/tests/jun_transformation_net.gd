extends "jun_transformation_route.gd"
## Run the native route with a separately owned hero over loopback ENet.
## Two isolated MultiplayerAPI roots share assets; only the authority ticks VM.
var peer: Session
var peer_game: Game
var branches: Array[SubViewport]=[]
var own_hero := {}
var own_bag := {"money":777,"items":["rune:e2"]}
var origin_bytes := PackedByteArray()
const PORT := 29963

func skills_equal(a: Dictionary, b: Dictionary) -> bool:
	# Native starting skills contain StringName/int values; the network
	# boundary canonicalizes them to String/float without changing values.
	var left := {};var right := {}
	for key in a:left[String(key)]=float(a[key])
	for key in b:right[String(key)]=float(b[key])
	return left==right

func branch(label: String) -> Dictionary:
	var root := SubViewport.new();root.name=label;root.size=Vector2i(800,600)
	root.own_world_3d=true;root.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(root);branches.append(root)
	var api := SceneMultiplayer.new();api.root_path=root.get_path()
	get_tree().set_multiplayer(api,root.get_path())
	var session := Session.new();root.add_child(session);session.set_physics_process(false)
	var view := Game.new();view.session=session;session.game=view;root.add_child(view)
	return {"session":session,"view":view}

func create_session() -> void:
	GameData.options["net_websocket"]=0;GameData.options["coop_share_loot"]=0
	var authority := branch("JunHost");s=authority.session;game=authority.view
	GameData.player_name="Jun Host"
	check(s.host(PORT,2)==OK,"open real ENet Jun authority")

func wait_network(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline and errors.messages.is_empty():
		if predicate.call(): return check(true,label)
		await get_tree().process_frame
	snapshot("network wait: "+label)
	return check(false,label)

func arrival_ready() -> void:
	# Prepare only the independent pre-dialogue guest origin. Admission uses
	# client_hello/bring RPC and the ordinary checkpoint comparison.
	s._capture_save_state()
	check(s.state.save(SaveInfo.path("jun_host_boundary"))==OK,"snapshot prepared host boundary")
	var origin := CampaignState.load_from(SaveInfo.path("jun_host_boundary"))
	origin.coop={};origin.heroes[0][0].name="Own Jun Guest"
	origin.heroes[0][0].str=43.0;origin.heroes[0][0].dex=37.0;origin.heroes[0][0].int=41.0
	origin.money=own_bag.money;origin.items=own_bag.items.duplicate()
	own_hero=origin.heroes[0][0].duplicate(true)
	check(origin.save(SaveInfo.path("jun_guest_origin"))==OK,"write independent matching guest origin")
	origin_bytes=FileAccess.get_file_as_bytes(SaveInfo.path("jun_guest_origin"))
	var guest_branch := branch("JunGuest");peer=guest_branch.session;peer_game=guest_branch.view
	CoopProgress.bring_slot="jun_guest_origin";GameData.player_name="Jun Guest"
	check(peer.join("127.0.0.1",PORT)==OK,"guest connects through normal ENet join")
	if not await wait_network(func():return peer.world!=null and s.players.size()==2 and not peer.loading_game and not peer._remote_loading and not peer._zone_holding and peer._pool_epoch==s._load_serial,"guest receives the prepared chapter world"):
		return
	peer.world.set_process(false);peer.world.set_physics_process(false);peer_game.rig.set_process(false)
	# CampaignState.watch is process-global; production normally has one
	# authority per process. Bind it to that authority in this two-root fixture.
	CampaignState.watch=s.coop._on_var
	var entry: Dictionary=s.coop.joiners.get("jun guest",{})
	check(not entry.is_empty() and entry.clean and entry.present and entry.in_sync,"ordinary admission recognizes matching guest progression")
	check(peer.my_index==1 and s.party_units(1).size()==1,"guest owns one separately deployed actor")
	evidence.network={"transport":"loopback ENet, two MultiplayerAPI roots in one process","guest_index":peer.my_index,
		"origin_hero":clean(own_hero),"origin_bag":clean(own_bag)}

func finish() -> void:
	if peer and s and s.world and failures.is_empty():
		var received := peer.coop.merged_count
		check(s.save_game("jun_network_checkpoint")==OK,"normal authority save transmits the chapter checkpoint")
		if await wait_network(func():return peer.coop.merged_count>received and not peer.coop.last_merged.is_empty() and peer.world!=null and peer.zone_id==s.zone_id and not peer._remote_loading and not peer._zone_holding and peer._pool_epoch==s._load_serial,"guest receives current chapter and personal save"):
			var saved := CampaignState.load_from(SaveInfo.path(peer.coop.last_merged))
			check(saved!=null,"received guest save is readable")
			if saved:
				evidence.network.returned_hero=clean(saved.heroes[0][0])
				check(saved.current_party==s.state.current_party and saved.current_zone==s.zone_id,"received save continues the host's exact chapter and map")
				for key: String in STORY_KEYS:
					check(saved.get_var(0,key)==s.state.get_var(0,key),"guest receives native progress: "+key)
				for key: String in ["str","dex","int","perks","armors","weapons","quick","spells"]:
					check(saved.heroes[0][0].get(key)==own_hero.get(key),"guest transformation keeps own "+key)
				check(skills_equal(saved.heroes[0][0].skills,own_hero.skills),"guest transformation keeps all own skill values")
				check(saved.heroes[0][0].name=="Own Jun Guest","solo save retains the guest's own display name")
				check({"money":saved.money,"items":saved.items}==own_bag,"guest save keeps own money and inventory")
				check(saved.heroes.size()==1,"guest solo save contains one local owner")
				check(saved.save(SaveInfo.path("jun_guest_return"))==OK,"preserve actual received guest save for independent resume")
				evidence.get_or_add("output_saves",{})["jun_guest_return"]=SaveInfo.path("jun_guest_return")
				for current: Session in [s,peer]:
					var units := current.party_units(peer.my_index)
					check(units.size()==1 and not units[0].dead,"network peer presents one living guest actor")
					if not units.is_empty():
						check(units[0].proto.get("name","")==saved.heroes[0][0].prototype,"network peer presents the correct guest body")
		check(FileAccess.get_file_as_bytes(SaveInfo.path("jun_guest_origin"))==origin_bytes,"original guest source save is unchanged")
	if peer and peer.multiplayer.multiplayer_peer:peer.multiplayer.multiplayer_peer.close()
	if s and s.multiplayer.multiplayer_peer:s.multiplayer.multiplayer_peer.close()
	if peer_game:peer_game.queue_free()
	if peer:peer.queue_free()
	CoopProgress.bring_slot=""
	await super.finish()
