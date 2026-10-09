extends "coop_story.gd"
## Real import/package RPCs and independent solo deployment of the resulting
## chapter save. Original party instructions are selected by the state fixture.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func freeze(s: Session) -> void:
	s.set_physics_process(false)
	if s.world:
		s.world.set_physics_process(false)
		s.world.set_process(false)
		s.world.vm.instances.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"control_mode":1},true)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-path="):
			var path := arg.trim_prefix("--resume-path=")
			var saved_slots: Array[String] = []
			for i in (3 if GameData.campaign_id == CampaignProfile.ASTRAL else 4):
				var slot := "context_stage_%d" % i
				var state := CampaignState.load_from(path.path_join(slot + ".sav"))
				check(state != null and state.save(SaveInfo.path(slot)) == OK, "copy actual RPC-created save " + slot)
				saved_slots.append(slot)
			await resume(saved_slots)
			finish()
			return
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	var camp := "bz1h" if astral else "bz7g"
	var origin := CoopProgress.fresh_state()
	origin.heroes[0][0].name = "Context Guest"
	origin.heroes[0][0].str = 31.0
	origin.money = 222
	origin.items = ["rune:e1"]
	origin.visited[camp] = true
	check(origin.save(SaveInfo.path("context_origin")) == OK, "private imported origin written")
	var original_bytes := FileAccess.get_file_as_bytes(SaveInfo.path("context_origin"))
	var h := branch("Host", true)
	host = h.s; hg = h.g
	var c := branch("Guest", false)
	client = c.s; cg = c.g
	(client.get_parent() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.state = CoopProgress.fresh_state()
	host.state.heroes[0][0].name = "Context Host"
	host.state.heroes[0][0].str = 91.0
	host.state.money = 9000
	host.state.items = ["rune:r1"]
	host.set_physics_process(false)
	GameData.player_name = "Context Host"
	check(host.host(29927 if astral else 29928, 2) == OK, "host opens prepared session")
	CoopProgress.bring_slot = "context_origin"
	GameData.player_name = "Context Guest"
	check(client.join("127.0.0.1",29927 if astral else 29928) == OK, "guest connects with personal save")
	check(await until(func(): return host.coop.joiners.has("context guest") and host.players.size() == 2 and client.my_index == 1), "authority receives actual bring RPC")
	if failures: get_tree().quit(2); return
	var entry: Dictionary = host.coop.joiners["context guest"]
	check(entry.get("party_context", {}).get("money") == 222, "bring RPC carries guest party context")
	# Two in-process peers otherwise share this static callback. Each real
	# process owns one; route it to the authority in this fixture.
	CampaignState.watch = host.coop._on_var
	await host.enter_zone(camp,1,false)
	freeze(host)
	check(await until(func():return client.zone_id == camp and not client._remote_loading, 90.0), "both peers enter original camp")
	check(entry.in_sync and entry.clean and entry.present, "guest starts at a fully credited checkpoint")
	if failures: get_tree().quit(2); return
	var helper: Node = load(get_script().resource_path.get_base_dir() + "/coop_progress_context.gd").new()
	helper.s = host
	var transitions := [["bz1h","FPrison","gz1h"],["bz2h","FSusel","bz2h"],["bz7h","Gipat","gz7g"]] if astral else [["bz7g","HeroAlone","bz13h"],["bz13h","Pretty","gz15h"],["zone15","HeroAlone","bz13h"],["bz13h","","gz15h"]]
	var slots: Array[String] = []
	for step: Array in transitions:
		helper.vm = host.world.vm
		helper.transition(step[0],step[1])
		# Original scripts can transfer directly into a field without writing
		# z.<destination>. Do not manufacture that unlock in this regression.
		var old_count := client.coop.merged_count
		await host.enter_zone(step[2],1,false)
		freeze(host)
		check(await until(func():return client.zone_id == step[2] and not client._remote_loading), "network transfer to " + step[2])
		check(entry.in_sync and entry.clean and entry.present, "shared chapter transfer retains guest progression eligibility")
		if failures: break
		host.coop.send_all()
		check(await until(func():
			if client.coop.merged_count <= old_count or client.coop.last_merged.is_empty(): return false
			var saved := CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
			return saved != null and saved.current_party == step[1] and saved.current_zone == step[2]
		), "guest writes received chapter package")
		var merged := CampaignState.load_from(SaveInfo.path(client.coop.last_merged))
		check(merged != null and merged.current_party == step[1], "received save selects " + step[1])
		if merged == null: break
		check(CoopProgress.main_hero(merged).str == 31.0 and CoopProgress.main_bag(merged).money == 222, "network package keeps personal stats and purse")
		var slot := "context_stage_%d" % slots.size()
		merged.save(SaveInfo.path(slot))
		slots.append(slot)
	check(helper.failures == 0, "all original party instruction sequences executed")
	helper.free()
	check(FileAccess.get_file_as_bytes(SaveInfo.path("context_origin")) == original_bytes, "imported save file remains byte-identical")
	check(host.save_game("context_host") == OK, "host stores personal contexts for reconnect")
	var stored := CampaignState.load_from(SaveInfo.path("context_host"))
	check(stored != null and stored.coop.host.joiners["context guest"].has("party_context"), "host save retains context journal")
	client.online = false
	var client_peer := client.multiplayer.multiplayer_peer
	client.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	client_peer.close()
	check(await until(func():return host.players.size() == 1), "guest disconnect completes")
	host.online = false
	var host_peer := host.multiplayer.multiplayer_peer
	host.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	host_peer.close()
	for root in branches: root.queue_free()
	for i in 5: await get_tree().process_frame
	branches.clear()
	CoopProgress.bring_slot = ""
	await resume(slots)
	finish()


func resume(slots: Array[String]) -> void:
	# A new, offline session consumes each saved guest chapter and creates its
	# own actors. This is stronger than inspecting a serialized dictionary.
	for slot: String in slots:
		var solo := branch("Solo" + slot, true)
		var ss: Session = solo.s
		ss.set_physics_process(false)
		var restored := CampaignState.load_from(SaveInfo.path(slot))
		check(ss.load_game(slot), "independent " + slot + " loads through normal save path")
		freeze(ss)
		var roster: Array = restored.heroes[0]
		var deployed := ss.party_units(0)
		check(deployed.size() == roster.size(), "independent " + slot + " deploys complete story roster")
		check(not deployed.is_empty() and deployed[0].info.get("name") == roster[0].get("unit_name",roster[0].name), "independent " + slot + " resolves protagonist identity")
		check(not deployed.is_empty() and not deployed[0].dead and deployed[0].hp > 0, "independent " + slot + " has a usable protagonist")
		check(not deployed.is_empty() and (not roster[0].has("pos") or deployed[0].pos.distance_to(roster[0].pos) < 0.01), "independent " + slot + " restores saved position")
		check(ss.world.units.values().all(func(u: GameUnit):return not u.has_meta("hero") or u.controller == 0), "independent " + slot + " contains no borrowed player slot")
		for root in branches: root.queue_free()
		for i in 3: await get_tree().process_frame
		branches.clear()


func finish() -> void:
	print("COOP_PROGRESS_CONTEXT_NETWORK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
