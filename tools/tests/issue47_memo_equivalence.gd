extends Node
## Issue #47: ScriptVM condition sharing must not change script behaviour.
## Run the same loaded world twice, sharing on and off, and compare the full
## saved VM state and campaign variables every 50 ticks.
func digest(s: Session) -> String:
	var st: Dictionary = s.world.vm.save_state()
	return str(JSON.stringify(st).hash()) + "/" + str(JSON.stringify(s.state.vars).hash()) + "/n" + str(s.world.vm.instances.size())
func trace(zone: String, save: String, memo: bool, ticks: int) -> Array:
	seed(4747)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	if save.is_empty():
		s.state.ensure_hero(0,s._hero_proto(0)); s.state.world_time=13.0
		await s.enter_zone(zone,1,false)
	else:
		s.load_game(save)
	var w:=s.world
	w.set_process(false);w.set_physics_process(false);s.set_physics_process(false)
	w.vm.condition_memo = memo
	seed(4747)
	var out:=[]
	for i in ticks:
		w._tick(GameUnit.TICK)
		if i % 50 == 49: out.append(digest(s))
	g.queue_free();s.queue_free()
	for i in 3: await get_tree().process_frame
	return out
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	var save := ""; var zones := []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--save="):
			DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
			DirAccess.copy_absolute(a.trim_prefix("--save="),SaveInfo.path("eq")); save="eq"
		if a.begins_with("--zones="): zones = Array(a.trim_prefix("--zones=").split(","))
	var fails := 0
	var compared := 0
	for z in (zones if save.is_empty() else [""]):
		compared += 1
		var a: Array = await trace(z, save, true, 1000)
		var b: Array = await trace(z, save, false, 1000)
		var ok := a == b
		if not ok: fails += 1
		print("EQUIV ", z if z else "save", " ", "same" if ok else "DIFFERENT", " ", a.slice(-1), " ", b.slice(-1))
	print("MEMO_EQUIV ", compared, " checks ", fails, " failures")
	get_tree().quit(1 if fails else 0)
