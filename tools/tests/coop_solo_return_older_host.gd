extends "coop_rename_reconnect.gd"
## A host's normal save precedes its final leave/flush package. A client may
## legitimately return with a newer tally sequence after that save is loaded.
func _ready() -> void:
	await get_tree().process_frame
	process_mode=Node.PROCESS_MODE_ALWAYS; outer_scene=get_tree().current_scene
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0,"coop_share_loot":0},true)
	var origin:=CoopProgress.fresh_state(); origin.heroes[0][0].str=31.0; origin.money=222
	origin.visited[origin.current_zone]=true
	check(origin.save(SaveInfo.path("older_origin"))==OK,"write disposable origin")
	host_app=branch("OlderHost"); host=Session.new(); host_app.add_child(host)
	GameData.player_name="Older Host"; check(host.host(PORT,4)==OK,"open actual ENet authority")
	host_app.start_game(host); host.state=CoopProgress.fresh_state()
	host.set_physics_process(false); await host.enter_zone(origin.current_zone,1,false); freeze(host)
	guest_app=branch("OlderGuest"); get_tree().current_scene=guest_app.get_parent(); open_menu(guest_app)
	if not await join_from_menu("Ann","older_origin"): await finish(); return
	old_slot=guest.my_index
	check(host.save_game("older_host")==OK,"ordinary host save records its current tally")
	var checkpoint:=CampaignState.load_from(SaveInfo.path("older_host"))
	var e: Dictionary=checkpoint.coop.host.joiners.ann
	check(await until(func():return not guest.coop.last_merged.is_empty()),"client receives the saved checkpoint package")
	var slot:=await leave_from_menu("Ann after host checkpoint")
	var returned:=CampaignState.load_from(SaveInfo.path(slot))
	var ack:=int(returned.coop.applied[String(e.sid)].seq)
	check(ack>int(e.seq),"legitimate client acknowledgement is newer than the host disk checkpoint")
	await host_app.back_to_menu()
	check(await until(func():return menu_of(host_app)!=null and host_app.session==null),"host leaves after the acknowledged client exit")
	for i in 4: await get_tree().process_frame # queued old Session must release its RPC node name
	# Independent personal advancement, while the original authored story stays
	# at this checkpoint. No SID or sequence is synthesized by the fixture.
	CoopProgress.main_hero(returned).str=44.0; returned.money=777; returned.items=["rune:e1","rune:e2"]
	fingerprint=identity(CoopProgress.main_hero(returned)); purse=CoopProgress.main_bag(returned).duplicate(true)
	check(returned.save(SaveInfo.path("older_client_newer"))==OK,"save the newer acknowledged solo source")
	host=Session.new(); host_app.add_child(host)
	GameData.player_name="Older Host"; check(host.host(PORT,4)==OK,"restart the ENet authority")
	host_app.start_game(host); host.set_physics_process(false)
	check(await host.load_game_shown("older_host"),"normal host reload restores its older disk checkpoint"); freeze(host)
	if not await join_from_menu("Ann","older_client_newer"): await finish(); return
	check(guest.my_index==old_slot,"same-name acknowledged return keeps its reserved slot")
	check(identity(host.state.heroes[old_slot][0])==fingerprint and host.coop.joiners.ann.purse==purse,"older host checkpoint cannot roll back newer personal stats or purse")
	check(host.coop.joiners.ann.seq>=ack,"host sequence resumes beyond the client's acknowledged baseline")
	check(await until(func():return not guest.coop.last_merged.is_empty()),"returning client receives the resumed package")
	var got:=CampaignState.load_from(SaveInfo.path(guest.coop.last_merged))
	check(identity(CoopProgress.main_hero(got))==fingerprint and CoopProgress.main_bag(got)==purse,"received solo save retains new personal earnings after host restart")
	rows.append({"host_disk_seq":e.seq,"client_flush_seq":ack,"resumed_host_seq":host.coop.joiners.ann.seq,"hero":identity(CoopProgress.main_hero(got)),"purse":CoopProgress.main_bag(got)})
	await finish()

func finish() -> void:
	print("COOP_SOLO_RETURN_OLDER_HOST ",checks," checks ",failures," failures")
	await super.finish()
