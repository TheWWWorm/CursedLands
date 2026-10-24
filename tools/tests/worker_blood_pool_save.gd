extends "local_host_campaign.gd"
## Load the actual death/save produced by blood_pool_save into a separate
## authority process, then save/reload through the normal frontend requests.
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var source := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-save="): source=arg.trim_prefix("--resume-save=")
	if not FileAccess.file_exists(source): get_tree().quit(2); return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"marks":1},true)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(source,SaveInfo.path("blood-input"))==OK,"copy death/save fixture into isolated profile")
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session=s; s.game=g; get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"separate authority starts")
	check(await s.load_game_shown("blood-input"),"worker loads saved death pool")
	check(await until(func():return s.world!=null and not s._remote_loading and not s.loading_game,40),"frontend receives the loaded world")
	check(await until(func():return GroundMarks.of(s.world).blood_marks.size()==1,10),"saved pool reaches frontend through reliable replay")
	var input := CampaignState.load_from(SaveInfo.path("blood-input"))
	var clip: String = input.zones[input.current_zone].get("blood_pools",{}).get(3326,{}).get("clip","")
	if not clip.is_empty(): check(s.world.units[3326].model._current==clip,"frontend restores the saved death clip rather than choosing another")
	get_tree().paused=true
	await get_tree().create_timer(.4,true,false,true).timeout
	var saved := await s.local_host.request("save",{"slot":"blood-worker","name":"Pool persistence","camera":s.local_host.view()})
	check(saved.get("ok",false),"worker saves the current pool")
	var state := CampaignState.load_from(SaveInfo.path("blood-worker"))
	var pools: Array = state.zones[state.current_zone].get("pool_membership",{}).get("pools",[])
	check(pools.size()==1 and pools[0].mark.age>=20,"worker preserves and ages the authoritative recipe")
	check(await s.load_game_shown("blood-worker"),"frontend reloads worker checkpoint")
	check(await until(func():return s.world!=null and not s._remote_loading and GroundMarks.of(s.world).blood_marks.size()==1,40),"pool survives a second process-backed reload")
	get_tree().paused=false
	await s.local_host.stop(); g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	FileAccess.open("user://worker-blood-pool-save.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"pools":pools},"\t"))
	TexUpscale.shutdown(); print("WORKER_BLOOD_POOL_SAVE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
