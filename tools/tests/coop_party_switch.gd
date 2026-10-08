extends Node
## Two real loopback ENet peers, original maps and authored Nalo handler.
## A prepared checkpoint isolates guest-finished dialogue, purse ownership,
## deployment and disconnect. It is not a full rescue playthrough.
var host: Session
var client: Session
var branches: Array[Node] = []
var observations: Array = []
var checks := 0
var failures := 0

func branch(label: String, main: bool) -> Session:
	var root: Node = Node.new() if main else SubViewport.new()
	if root is SubViewport:
		root.size = Vector2i(1280,720)
		root.own_world_3d = true
	root.name = label
	add_child(root)
	branches.append(root)
	var api := SceneMultiplayer.new()
	api.root_path = root.get_path()
	get_tree().set_multiplayer(api,root.get_path())
	var s := Session.new()
	root.add_child(s)
	var g := Game.new()
	g.session = s
	s.game = g
	root.add_child(g)
	return s

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("NETWORK_CHECK ",JSON.stringify({"ok":ok,"label":label}))

func until(predicate: Callable, seconds := 45.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func units(s: Session) -> Array:
	var out := []
	for u: GameUnit in s.world.units.values():
		if u.has_meta("hero"):
			out.append({"id":u.uid,"controller":u.controller,"name":u.info.get("name",""),"prototype":u.proto.get("name",""),"dead":u.dead})
	return out

func snapshot(label: String) -> void:
	var data := {"label":label,"host_party":host.state.current_party,"client_party":client.state.current_party,"host_zone":host.zone_id,"client_zone":client.zone_id,"host_units":units(host),"client_units":units(client)}
	observations.append(data)
	print("NETWORK_OBSERVATION ",JSON.stringify(data))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"auto_graphics":0,"autosave":0,"scroll_border":0},true)
	await get_tree().process_frame
	host = branch("AuditHost",true)
	client = branch("AuditClient",false)
	check(host.host(29974,2)==OK,"host opens loopback test port")
	GameData.player_name = "Nalo Audit Guest"
	check(client.join("127.0.0.1",29974)==OK,"guest joins")
	check(await until(func():return host.players.size()==2),"two peers connected")
	if failures: get_tree().quit(2); return
	host.state = CampaignState.new()
	host.state.ensure_hero(0,"Human Hero")
	host.state.ensure_hero(1,"Human Hero","Nalo Audit Guest")
	host.state.create_party("HeroAlone")
	host.state.add_party_unit("HeroAlone","Hero","Human Hero Hadagan")
	host.state.copy_stats("Hero","HeroAlone::Hero")
	host.state.set_current_party("HeroAlone")
	host.state.money = 111
	host.state.items = ["rune:r1"]
	var guest_pid := client.multiplayer.get_unique_id()
	host.coop._pending[guest_pid] = {"hero":host.state.heroes[1][0].duplicate(true), "vars":{}, "visited":{}, "side_quests":{}, "quest_items":{}, "seq":{}, "purse":{"money":222,"items":["rune:r2"]}}
	host.coop.on_hello(guest_pid,1,"Nalo Audit Guest")
	host.state.set_var(0,"q.gz15h.q60h",2)
	host.state.set_var(0,"q.gz15h.q61h",1)
	# Pause automatic world ticking, but keep networking and normal load/save.
	host.set_physics_process(false)
	await host.enter_zone("bz13h",1,false)
	check(await until(func():return client.world!=null and client.zone_id=="bz13h" and not client._remote_loading),"both peers at prepared prison checkpoint")
	var vm := host.world.vm
	vm.briefings.active = "b.Nalo.Kr60"
	vm.briefings.active_player = 0
	client.submit({"t":"dialog_done","id":"b.Nalo.Kr60"})
	check(await until(func():return host.state.current_party=="Pretty"),"guest closes host dialogue through the command RPC")
	check(host.state.money==0 and host.state.items.is_empty(),"Nalo receives his own empty bag")
	check(host.state.party_bags.HeroAlone=={"money":111,"items":["rune:r1"]},"waiting protagonist keeps host money and items")
	check(host.coop.purse_entry(1).purse=={"money":0,"items":[]},"guest Nalo receives an empty temporary bag")
	check(host.state.coop.guest_roles[1].bags[""]=={"money":222,"items":["rune:r2"]},"guest keeps personal money and items parked with original hero")
	check(host.state.current_party=="Pretty","authored completion selects Nalo party")
	var target := vm._pending_zone.duplicate()
	check(target.size()==2 and target[0]=="gz15h","authored completion queues rescue map")
	if failures: get_tree().quit(2); return
	vm._pending_zone.clear()
	await host.enter_zone(String(target[0]),int(target[1]),false)
	check(await until(func():return client.zone_id==host.zone_id and client.state.current_party=="Pretty" and not client._remote_loading),"client receives Nalo chapter and map")
	snapshot("after authored Nalo switch")
	check(host.party_units(0).size()==1 and host.party_units(0)[0].info.name=="Nalo","host controls only Nalo")
	check(client.party_units(1).size()==1 and client.party_units(1)[0].proto.name=="Human Hadagan Pretty" and client.party_units(1)[0].display_name=="Nalo Audit Guest","guest controls a distinct Nalo role with its own display name")
	var guest: GameUnit = client.party_units(1)[0]
	var destination := guest.pos + Vector2(1,0)
	client.submit({"t":"move","units":[guest.uid],"x":destination.x,"y":destination.y})
	check(await until(func():return host.world.units[guest.uid].orders.any(func(o):return o.get("type","")=="move") or host.world.units[guest.uid].order.get("type","")=="move"),"guest movement command is accepted during Nalo chapter")
	check(host.save_game("party_switch")==OK,"isolated Nalo co-op save written")
	check(await host.load_game_shown("party_switch"),"isolated Nalo save reloads")
	check(await until(func():return not client.loading_game and not client._remote_loading and client.state.current_party=="Pretty"),"guest rejoins restored Nalo state")
	snapshot("after save reload")
	check(host.party_units(0).size()==1 and host.party_units(0)[0].info.name=="Nalo","Nalo remains host controlled after reload")
	check(client.party_units(1).size()==1,"guest remains playable after reload")
	client.multiplayer.multiplayer_peer.close()
	check(await until(func():return host.players.size()==1),"server handles guest disconnection")
	var protagonist: GameUnit = host.world.vm._by_name("Hero")
	var disconnected := {"label":"after guest disconnect","host_units":units(host),"hero_alias_id":protagonist.uid if protagonist else -1,"hero_alias_name":protagonist.info.get("name","") if protagonist else ""}
	observations.append(disconnected)
	print("NETWORK_OBSERVATION ",JSON.stringify(disconnected))
	check(protagonist!=null and protagonist.controller==0 and protagonist.info.name=="Nalo","disconnect preserves Nalo as scripted Hero")
	check(host.state.money==0 and host.state.party_bags.HeroAlone.money==111 and host.coop.joiners["nalo audit guest"].purse.money==0 and host.state.coop.guest_roles[1].bags[""].money==222,"save/reload/disconnect retains current and waiting purse owners")
	var f := FileAccess.open("user://coop-party-switch.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"  "))
	f.close()
	host.online = false
	client.online = false
	host.multiplayer.multiplayer_peer.close()
	for root in branches: root.queue_free()
	for i in 10: await get_tree().process_frame
	print("NETWORK_DONE ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
