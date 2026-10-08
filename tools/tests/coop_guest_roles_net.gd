extends Node
## Real imported guest, original Nalo/Shaina events, authority/client bodies,
## save/reload, reconnect and return. Unrelated quests/AI are paused.
var host: Session
var client: Session
var branches: Array[Node] = []
var checks := 0
var failures := 0
var astral := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func until(predicate: Callable, seconds := 90.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func branch(guest: bool) -> Session:
	var root: Node = SubViewport.new() if guest else Node.new()
	if root is SubViewport:
		root.size = Vector2i(1280,720); root.own_world_3d = true; root.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.name = "RoleGuest" if guest else "RoleHost"; add_child(root); branches.append(root)
	var api := SceneMultiplayer.new(); api.root_path = root.get_path(); get_tree().set_multiplayer(api,root.get_path())
	var s := Session.new(); s.name = "Session"; root.add_child(s)
	var g := Game.new(); g.session = s; s.game = g; root.add_child(g)
	return s

func freeze(s: Session) -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	s.game.rig.set_process(false); s.game.hud._tutorial.close(); s.game.hud._dialog.visible = false
	if s.world.vm: s.world.vm.instances.clear()

func loaded() -> bool:
	return client.world != null and client.zone_id == host.zone_id and client.my_index == 1 \
		and not client.loading_game and not client._remote_loading and not client._zone_holding and client._pool_epoch == host._load_serial

func prepared(strength: float, money: int, name: String) -> CampaignState:
	var st := CoopProgress.fresh_state()
	st.heroes[0][0].str = strength; st.heroes[0][0].name = name
	st.money = money; st.items = ["rune:e1"]
	var party := "FSusel" if astral else "HeroAlone"
	st.create_party(party)
	st.add_party_unit(party,"Hero2" if astral else "Hero","Hero2" if astral else "Human Hero Hadagan")
	st.copy_stats("Hero",party+"::"+("Hero2" if astral else "Hero"))
	st.set_current_party(party)
	if astral: st.money = money; st.items = ["rune:e1"]
	st.visited["bz5h" if astral else "bz13h"] = true
	st.visited["gz2h" if astral else "gz15h"] = true
	return st

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	astral = GameData.campaign_id == CampaignProfile.ASTRAL
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0,"coop_share_loot":0},true)
	var origin := prepared(31.0,222,"Original Guest")
	check(origin.save(SaveInfo.path("roles_origin")) == OK,"write isolated imported origin")
	var origin_bytes := FileAccess.get_file_as_bytes(SaveInfo.path("roles_origin"))
	host = branch(false); check(host.host(29935,3) == OK,"open temporary-role host")
	host.state = prepared(91.0,9000,"Host")
	host.set_physics_process(false)
	await host.enter_zone("bz5h" if astral else "bz13h",1,false); freeze(host)
	client = branch(true); CoopProgress.bring_slot = "roles_origin"; GameData.player_name = "Role Guest"
	check(client.join("127.0.0.1",29935) == OK,"join with actual imported progress")
	check(await until(func(): return host.players.size()==2 and host.coop.joiners.has("role guest") and loaded()),"imported guest receives prepared camp")
	if failures: await finish(); return
	freeze(client); CampaignState.watch = host.coop._on_var
	var e: Dictionary = host.coop.joiners["role guest"]
	# A late arrival intentionally lacks whole-zone credit. Re-enter this
	# prepared checkpoint together before testing the independent chapter save.
	await host.enter_zone("bz5h" if astral else "bz13h",1,false); freeze(host)
	check(await until(func():return loaded() and e.in_sync and e.clean and e.present),"both peers start a fully credited chapter checkpoint")
	if failures: await finish(); return
	freeze(client)
	var protagonist := CoopProgress.main_hero(origin).duplicate(true)
	check(host.party_units(1).size()==1 and host.party_units(1)[0].controller==1,"one actual guest actor before handoff")
	var vm := host.world.vm
	var dialogue := "b.merc8.brief_23" if astral else "b.Nalo.Kr60"
	vm.briefings.active = dialogue; vm.briefings.active_player = 1
	client.submit({"t":"dialog_done","id":dialogue})
	var party := "Shaina" if astral else "Pretty"
	var prototype := "merc8" if astral else "Human Hadagan Pretty"
	check(await until(func():return host.state.current_party==party),"guest completion selects authored temporary party")
	var target: Array = vm._pending_zone.duplicate(); vm._pending_zone.clear()
	check(target.size()==2,"original event queues destination")
	if failures: await finish(); return
	await host.enter_zone(String(target[0]),int(target[1]),false); freeze(host)
	check(await until(loaded),"both peers enter temporary chapter")
	freeze(client)
	check(await until(func():return not host.party_units(1).is_empty() and not client.party_units(1).is_empty()),"temporary actor links to client character record")
	if failures: await finish(); return
	var u: GameUnit = host.party_units(1)[0]
	check(u.proto.get("name")==prototype and client.party_units(1)[0].proto.get("name")==prototype,"host and client deploy matching temporary guest body")
	check(host.state.heroes[1][0].name=="Role Guest" and u.display_name=="Role Guest","preview and overhead retain the guest's name")
	check(host.coop.purse_entry(1).purse=={"money":0,"items":[]},"temporary guest cannot use parked main inventory")
	check(vm != host.world.vm and host.world.vm._by_name("Hero").controller==0,"host remains the unique narrative protagonist")
	if failures: await finish(); return
	var at := host.world.nav.nearest_walkable(u.pos+Vector2(1.5,0))
	client.submit({"t":"move","units":[u.uid],"x":at.x,"y":at.y})
	check(await until(func():return u.orders.any(func(o):return o.get("type")=="move") or u.order.get("type")=="move"),"guest retains control of temporary body")
	u.hp = u.max_hp*.7
	host.coop.with_purse(1,func():host.state.money+=13;host.state.items.append("rune:e2"))
	var before := client.coop.merged_count
	check(host.save_game("roles_active")==OK,"save active temporary guest")
	check(await until(func():
		if client.coop.merged_count<=before or client.coop.last_merged.is_empty(): return false
		var received := CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
		return received!=null and received.current_party==party and received.money==13
	),"guest receives current chapter progress package")
	var merged := CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
	if merged==null or merged.current_party!=party or merged.money!=13:
		print("ROLE_PROGRESS_DIAGNOSTIC ",{"party":merged.current_party if merged else "missing","money":merged.money if merged else -1,
			"in_sync":e.in_sync,"clean":e.clean,"present":e.present,"context":e.get("party_context",{}).get("current_party","missing")})
	check(merged!=null and merged.current_party==party and merged.heroes[0][0].prototype==prototype and merged.money==13,"independent guest save contains played role and its own bag")
	check(merged!=null and CoopProgress.main_hero(merged).str==protagonist.str and CoopProgress.main_bag(merged).money==222,"package keeps normal guest stats and purse parked")
	check(await host.load_game_shown("roles_active"),"host reloads active role"); freeze(host)
	check(await until(loaded),"client receives reloaded temporary world"); freeze(client)
	e = host.coop.joiners["role guest"]
	check(host.party_units(1)[0].proto.get("name")==prototype and e.purse=={"money":13,"items":["rune:e2"]},"reload preserves temporary body and private loot")
	client.online=false; client.multiplayer.multiplayer_peer.close()
	check(await until(func():return host.players.size()==1),"guest disconnects during temporary chapter")
	CoopProgress.bring_slot=""
	check(client.join("127.0.0.1",29935)==OK,"reconnect without replacing original tally")
	check(await until(func():return host.players.size()==2 and loaded() and not host.party_units(1).is_empty()),"guest reclaims saved temporary body")
	freeze(client)
	check(host.party_units(1).size()==1 and host.party_units(1)[0].proto.get("name")==prototype and host.coop.purse_entry(1).purse.money==13,"reconnect creates no duplicate and retains role inventory")
	if astral:
		await host.enter_zone("bz5h",1,false); freeze(host)
		check(await until(loaded),"return to original Shaina camp"); freeze(client)
		host.state.set_var(0,"b.merc8.brief_24",1)
		host.world.vm.spawn("VCheck#1#1",[])
		for i in 4: host.world.vm.tick(ScriptVM.POLL)
	else:
		host.world.vm.spawn("VTriger#0#23",[null])
		for i in 35: host.world.vm.tick(ScriptVM.POLL)
		var back: Array = host.world.vm._pending_zone.duplicate(); host.world.vm._pending_zone.clear()
		# VM.tick dispatches LeaveToZone through call_deferred; its queue can
		# already be empty before the session starts the transfer next frame.
		if back.size()==2: await host.enter_zone(String(back[0]),int(back[1]),false); freeze(host)
		check(await until(func():return host.zone_id=="bz13h" and not host.loading_game),"original Nalo return reaches prison camp")
	check(await until(func():return loaded() and client.state.current_party==host.state.current_party),"client receives authored return")
	var expected := String(protagonist.prototype) if astral else "Human Hero Hadagan"
	check(host.party_units(1).size()==1 and host.party_units(1)[0].proto.get("name")==expected and client.party_units(1)[0].proto.get("name")==expected,"return restores guest's prior body on both peers")
	if host.state.heroes[1][0].str!=31.0 or host.world.vm._by_name("Hero").controller!=0:
		print("ROLE_RETURN_DIAGNOSTIC ",{"guest":host.state.heroes[1][0],"alias":host.world.vm._by_name("Hero").info,
			"alias_controller":host.world.vm._by_name("Hero").controller,"story":host.world.vm._story_records().map(func(x):return [x.uid,x.info.name,x.controller])})
	check(host.state.heroes[1][0].str==31.0 and host.world.vm._story_records()[0].controller==0,"return keeps personal stats and stable narrative role")
	check(FileAccess.get_file_as_bytes(SaveInfo.path("roles_origin"))==origin_bytes,"imported original save stays byte-identical")
	await finish()

func finish() -> void:
	for s: Session in [client,host]:
		if s and is_instance_valid(s):
			s.online=false
			if s.multiplayer.multiplayer_peer: s.multiplayer.multiplayer_peer.close()
	for root: Node in branches: root.queue_free()
	for i in 5: await get_tree().process_frame
	CoopProgress.bring_slot=""
	print("COOP_GUEST_ROLES_NET ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
