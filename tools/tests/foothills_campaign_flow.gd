extends "worker_travel_clock.gd"
## #119 follow-up: exercise production new/load transitions without generating
## an artificial campaign save or inserting a clock-cache mismatch.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(CrashReport.instance._performance):
		CrashReport.instance._performance.queue_free()
	var main := get_parent()
	# Main.start_game deliberately removes menu/tool siblings.
	reparent(get_tree().root)
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1),true)
	var s := Session.new(); main.add_child(s)
	s.players = {1:{"index":0,"name":"Clock test"}}
	main.start_game(s)
	await s.new_campaign(false)
	check(await until(func():return s.world!=null and s.zone_id=="gz1g" and not s._remote_loading and LoadingScreen._current==null,60),"production new campaign is ready in Ruins")
	check(s.local_host.frontend and s.local_host.single_player,"production new campaign starts its separate authority")
	s.submit({"t":"console","line":"god on","request":1})
	await compare_rates(s,main.game)
	s.submit({"t":"console","line":"travel gz3g","request":2})
	check(await until(func():return s.zone_id=="gz3g" and not s._remote_loading and LoadingScreen._current==null,60),"new campaign arrives in Foothills")
	await compare_rates(s,main.game)
	var answer := await s.local_host.request("save",{"slot":"fresh-foothills","camera":s.local_host.view()})
	check(answer.get("ok",false),"actual travelling campaign saved")
	var old_pid := s.local_host.process_id
	await main.back_to_menu()
	check(not OS.is_process_running(old_pid),"return to menu closes the first authority")
	s = Session.new(); main.add_child(s)
	main.start_game(s)
	check(await s.load_game_shown("fresh-foothills"),"production load restores actual Foothills save")
	check(await until(func():return s.world!=null and not s._remote_loading and LoadingScreen._current==null,60),"loaded Foothills presentation is ready")
	check(s.local_host.process_id>0 and s.local_host.process_id!=old_pid,"load starts a fresh authority process")
	check(main.game.speed==1 and s.field_speed==1,"saved fast field speed survives menu and worker replacement")
	await compare_rates(s,main.game)
	await s.local_host.stop()
	FileAccess.open("user://foothills-campaign-flow.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"\t"))
	print("FOOTHILLS_CAMPAIGN_FLOW checks=",checks," failures=",failures)
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
