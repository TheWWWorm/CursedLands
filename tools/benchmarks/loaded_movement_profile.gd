extends Node
## Diagnostic, not a parity assertion: attribute first-move latency in a
## disposable copy of a loaded save while preserving the full world roster.
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):source=arg.trim_prefix("--save=")
	if source.is_empty() or not FileAccess.file_exists(source):get_tree().quit(1);return
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	FileAccess.open(SaveInfo.path("movement-profile"),FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes(source))
	var s:=Session.new();add_child(s);s.local_host.worker=true
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false)
	if not await s.load_game_shown("movement-profile"):get_tree().quit(1);return
	var w:=s.world;w.set_process(false)
	var u:GameUnit=s.party_units(0)[0]
	w.profile_simulation=true;w.nav.profile_paths=true
	var rows:=[]
	for phase in ["initial_idle","first_move","second_move"]:
		w.profile_us.clear();w.profile_counts.clear();w.profile_slow.clear()
		w.nav.profile_totals.clear();w.nav.profile_slow.clear()
		var initial:=u.pos
		var command_us:=0
		if phase!="initial_idle":
			var start:=Time.get_ticks_usec()
			s.apply_command({"t":"move","units":[u.uid],"x":u.pos.x+40.0,"y":u.pos.y,"run":true},0)
			command_us=Time.get_ticks_usec()-start
		var ticks:=[]
		for i in (12 if phase=="initial_idle" else 30):
			var start:=Time.get_ticks_usec();w._tick(GameWorld.TICK)
			ticks.append(Time.get_ticks_usec()-start)
			await get_tree().process_frame
		var row:={"phase":phase,"command_us":command_us,"ticks_us":ticks,
			"from":[initial.x,initial.y],"to":[u.pos.x,u.pos.y],"dead":u.dead,
			"world_us":w.profile_us.duplicate(),"counts":w.profile_counts.duplicate(),
			"slow":w.profile_slow.duplicate(true),"paths":w.nav.profile_totals.duplicate(),
			"slow_paths":w.nav.profile_slow.duplicate(true)}
		rows.append(row);print("MOVEMENT_PROFILE ",JSON.stringify(row))
	FileAccess.open("user://loaded-movement-profile.json",FileAccess.WRITE).store_string(JSON.stringify({"zone":s.zone_id,"units":w.units.size(),"rows":rows},"\t"))
	w.profile_simulation=false;w.nav.profile_paths=false
	g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	TexUpscale.shutdown();get_tree().quit()
