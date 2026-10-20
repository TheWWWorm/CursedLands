extends Node
## Actual cz1h authored clock-freeze routine across full Session save/load.
var out := "user://"
var s: Session
var game: Game
var report := {"assertions":[]}
func check(ok: bool,label: String) -> void:
	report.assertions.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)
func stop() -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	game.rig.set_process(false)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"confine_mouse":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s=Session.new(); add_child(s); s.set_physics_process(false)
	game=Game.new(); game.session=s; s.game=game; add_child(game)
	s.state.ensure_hero(0,"Human Hero"); s._enter_zone("cz1h",1,false); stop()
	# Select only the unchanged original routine; stop inside its Sleep(10),
	# after FixWorldTime has executed and before the prepared cast moves.
	s.world.vm.instances.clear(); s.world.vm.spawn("VTriger#0#1",[null])
	for i in 3: s.world.vm.tick(ScriptVM.POLL)
	report.before={"fixed":s.world.vm.time_fixed,"hours":s.state.world_time,"vm":s.world.vm.save_state()}
	check(s.world.vm.time_fixed,"original cz1h VTriger#0#1 freezes clock")
	s.world.vm.tick(0.25)
	check(is_equal_approx(s.state.world_time,float(report.before.hours)),"clock remains frozen before save")
	check(s.save_game("clock_roundtrip")==OK,"full Session save succeeds")
	check(s.load_game("clock_roundtrip"),"full Session load succeeds"); stop()
	report.after={"fixed":s.world.vm.time_fixed,"hours":s.state.world_time,"vm":s.world.vm.save_state()}
	check(s.world.vm.time_fixed,"authored clock-freeze flag survives save/load")
	s.world.vm.tick(0.25); report.after_tick_hours=s.state.world_time
	check(is_equal_approx(s.state.world_time,float(report.before.hours)),"clock remains frozen after load")
	FileAccess.open(out.path_join("clock-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.queue_free(); s.queue_free()
	for i in 10: await get_tree().process_frame
	TexUpscale.shutdown(); print("AUDIT_CLOCK ",JSON.stringify({
		"checks":report.assertions.size(),"failures":report.assertions.filter(func(c):return not c.ok).size()}))
	get_tree().quit(1 if report.assertions.any(func(c):return not c.ok) else 0)
