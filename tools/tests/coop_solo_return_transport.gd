extends "coop_solo_return.gd"
## Same-name active handoff and stale-source controls use a separate compact
## scene; chapter travel and independent solo resume have their own fixtures.
func _ready() -> void:
	await get_tree().process_frame
	process_mode=Node.PROCESS_MODE_ALWAYS; outer_scene=get_tree().current_scene
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0,"coop_share_loot":0},true)
	var origin:=CoopProgress.fresh_state(); origin.heroes[0][0].str=44.0
	origin.money=777; origin.items=["rune:e1","rune:e2","rune:ic"]; origin.visited[origin.current_zone]=true
	fingerprint=identity(CoopProgress.main_hero(origin)); purse=CoopProgress.main_bag(origin).duplicate(true)
	check(origin.save(SaveInfo.path("transport_origin"))==OK,"write disposable transport source")
	host_app=branch("TransportHost"); host=Session.new(); host_app.add_child(host)
	GameData.player_name="Transport Host"; check(host.host(PORT,4)==OK,"open actual ENet authority")
	host_app.start_game(host); host.state=CoopProgress.fresh_state()
	host.set_physics_process(false); await host.enter_zone(origin.current_zone,1,false); freeze(host)
	ann_app=branch("TransportAnn"); use_app(ann_app); open_menu(ann_app)
	if not await join_from_menu("Ann","transport_origin"): await finish(); return
	old_slot=guest.my_index
	fingerprint=identity(host.state.heroes[old_slot][0]); purse=host.coop.joiners.ann.purse.duplicate(true)
	await delivered("transport_checkpoint")
	await protected_existing_source()
	await finish()

func finish() -> void:
	print("COOP_SOLO_RETURN_TRANSPORT ",checks," checks ",failures," failures")
	await super.finish()
