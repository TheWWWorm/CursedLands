extends "local_host_campaign.gd"
## #112 through the separate authority used by normal desktop play.
func observer_row(state: CampaignState) -> Dictionary:
	for row: Dictionary in state.zones[state.current_zone].get("pool_membership",{}).get("controllers",[]):
		if row.unit[0]==3327: return row
	return {}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var source := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-dir="): source=arg.trim_prefix("--resume-dir=")
	if source.is_empty(): get_tree().quit(2); return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,
		"net_lan":0,"net_upnp":0,"net_directory":0},true)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session=s; s.game=g; get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"separate corpse authority starts")
	for name: String in ["corpse-mid","corpse-finished-2"]:
		check(DirAccess.copy_absolute(source.path_join(name+".sav"),SaveInfo.path(name))==OK,"copy "+name)
		var original := observer_row(CampaignState.load_from(SaveInfo.path(name)))
		for cycle in 2:
			check(await s.load_game_shown(name),"worker loads %s cycle %d" % [name,cycle])
			check(await until(func():return s.world!=null and not s._remote_loading and not s.loading_game,40),"frontend receives corpse world")
			await get_tree().create_timer(.8,true,false,true).timeout
			get_tree().paused=true
			await get_tree().create_timer(.2,true,false,true).timeout
			var saved := await s.local_host.request("save",{"slot":name,"name":"Corpse memory regression","camera":s.local_host.view()})
			check(saved.get("ok",false),"worker saves corpse checkpoint")
			var row := observer_row(CampaignState.load_from(SaveInfo.path(name)))
			check(row.get("corpses",[]).any(func(ref):return ref[0]==3326),"authoritative NPC retains the body across worker reload")
			if name=="corpse-mid":
				check(row.has("suspicion") and float(row.suspicion.t0)>=float(original.suspicion.t0),"in-progress investigation retains its elapsed age")
			else:
				check(not row.has("suspicion") and row.get("pending",[]).is_empty(),"finished investigation cannot restart after worker reload")
			get_tree().paused=false
	await s.local_host.stop(); g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	TexUpscale.shutdown()
	print("WORKER_CORPSE_MEMORY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
