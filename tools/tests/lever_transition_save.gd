extends Node
## Controlled mechanism regression, not a physical route or network run.
## Native reference: 52b7a0 SetState, 52b490 draw, 52b560/52b650 save/load.
const P := preload("res://src/game/script/script_parser.gd")
const GATE := 338774
var s: Session
var game: Game
var checks := 0
var failures := []
var evidence := {"cases":[],"assertions":[],"scope":"Actual original zone15 YardGates04, native VM handler, deterministic Tween clock, full Session saves/reloads for open and close; no route/AI/ENet coverage."}
var cells := []
func check(ok: bool, label: String) -> void:
	checks += 1; evidence.assertions.append({"label":label,"ok":ok})
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func near(a: float,b: float) -> bool: return absf(a-b) < 0.000002
func native_pose(start: float,target: float,ticks: float,elapsed: float) -> float:
	var remaining := float(PackedFloat32Array([(ticks+1.0-elapsed)/ticks])[0])
	return target-float(PackedFloat32Array([(target-start)*remaining])[0]) if remaining > 0.0 else target
func call_state(state: int, duration: float) -> void:
	s.world.vm._call("SwitchLeverStateEx",[[P.N_CALL,"GetObject",[[P.N_NUM,GATE]]],[P.N_NUM,state],[P.N_NUM,duration]],ScriptVM.Instance.new())
func stop_simulation() -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); game.rig.set_process(false)
func step(amount: float) -> void:
	if s.world.lever_sys._tweens.has(GATE):
		var tw: Tween = s.world.lever_sys._tweens[GATE]
		if tw.is_valid():
			tw.pause(); tw.custom_step(amount*GameUnit.TICK)
func physical_cells() -> Array:
	var out := []
	for p: Vector2 in cells: out.append(s.world.nav.cell_open(p,1))
	return out
func capture(label: String) -> Dictionary:
	var ls := s.world.lever_sys
	var row := {"label":label,"state":s.world.levers[GATE].state,"figure":ls.figure_t(GATE),"physical":ls.physical_t(GATE),"saved":ls.export_row(GATE),"cells":physical_cells()}
	evidence.cases.append(row); return row
func disk_row(row: Array) -> Array:
	var path := "user://row-roundtrip.sav"
	var f := FileAccess.open(path,FileAccess.WRITE); f.store_var(row); f.close()
	return FileAccess.open(path,FileAccess.READ).get_var()
func roundtrip_case(target: int, duration: float) -> void:
	var start := float(1-target)
	var label := "open" if target == 1 else "close"
	call_state(1-target,0.0); call_state(target,duration)
	step(4.0)
	var mid := capture(label+" before full save")
	check(near(mid.figure,native_pose(start,target,duration,4.0)),label+" begins at native mid-transition pose")
	check(near(mid.physical,target),label+" collision is authoritative target before save")
	s.save_game("mid_"+label)
	check(s.load_game("mid_"+label),label+" full Session save/reload succeeds")
	stop_simulation()
	var restored := capture(label+" fresh loaded world")
	check(int(restored.state) == target,label+" retains logical state")
	check(near(restored.figure,mid.figure),label+" retains current visual pose")
	check(near(restored.physical,target),label+" retains native target collision after reload")
	check(restored.cells == mid.cells,label+" preserves actual original gate passability")
	step(1.5)
	check(near(s.world.lever_sys.figure_t(GATE),native_pose(start,target,duration,5.5)),label+" resumes original curve and elapsed time")
	var saved_again := disk_row(s.world.lever_sys.export_row(GATE))
	s.world.lever_sys.restore_row(GATE,saved_again)
	step(2.0)
	check(near(s.world.lever_sys.figure_t(GATE),native_pose(start,target,duration,7.5)),label+" second reload preserves cumulative elapsed time")
	step(duration-7.0)
	check(near(s.world.lever_sys.figure_t(GATE),native_pose(start,target,duration,duration+0.5)),label+" remains moving half a native tick before completion")
	step(0.5)
	var end := capture(label+" completed at original deadline")
	check(near(end.figure,target),label+" finishes at original deadline")
	check(near(end.physical,target) and end.cells == mid.cells,label+" navigation stays at target throughout resumed animation")
func metadata_controls() -> void:
	var ls := s.world.lever_sys
	call_state(0,0.0); call_state(1,10.0)
	var immediate := disk_row(ls.export_row(GATE))
	ls.restore_row(GATE,immediate); step(0.5)
	check(near(ls.figure_t(GATE),native_pose(0,1,10,0.5)),"save before first draw retains native first-tick extrapolation")
	call_state(1,0.0)
	check(near(ls.figure_t(GATE),1) and near(ls.physical_t(GATE),1),"immediate transitions remain immediate")
	call_state(0,0.0)
	s.world.vm._call("SwitchLeverState",[[P.N_CALL,"GetObject",[[P.N_NUM,GATE]]],[P.N_NUM,1]],ScriptVM.Instance.new())
	var duration := ls.switch_time(GATE)
	check(near(duration,22.0),"original stga6 database supplies its authored 22-tick duration")
	step(6.25)
	check(near(ls.figure_t(GATE),native_pose(0,1,duration,6.25)),"default handler uses authored duration before save")
	var joining := disk_row(ls.export_row(GATE))
	s.world.authority = false # exercise the zone-snapshot importer, not an ENet session
	ls.restore_row(GATE,joining)
	check(near(ls.physical_t(GATE),1),"client snapshot import retains the authoritative ordinary gate target")
	step(duration-6.0)
	check(near(ls.figure_t(GATE),native_pose(0,1,duration,duration+0.25)),"client snapshot resumes the same remaining authored duration")
	step(0.75)
	check(near(ls.figure_t(GATE),1),"default transition ends at its original 23-tick deadline")
	check(ls.export_row(GATE).size()==3,"finished ordinary transition leaves no stale optional timing")
	s.world.authority = true
	call_state(0,10.0); step(2.0); call_state(1,0.0)
	check(ls.export_row(GATE).size()==3 and near(ls.figure_t(GATE),1),"new immediate command cancels obsolete transition metadata")
	ls.restore_row(GATE,[1,0.25,false])
	check(near(ls.figure_t(GATE),0.25) and near(ls.physical_t(GATE),0.25) and not s.world.levers[GATE].enabled,"legacy rows preserve their settled interpretation")
	var good := {"kind":"ordinary","v":1,"from":0.0,"target":1.0,"ticks":10.0,"elapsed":4.0}
	var bad := [{}, {"kind":"ordinary"}, {"kind":"unknown","v":1}, []]
	for key in ["from","target","ticks","elapsed","v"]:
		var missing := good.duplicate(); missing.erase(key); bad.append(missing)
	for pair: Array in [["ticks",0.0],["ticks",-1.0],["ticks",INF],["elapsed",NAN],["elapsed",-0.1],["elapsed",11.0],["from",INF],["target",0.0],["target",2.0],["v",2],["elapsed",true]]:
		var invalid := good.duplicate(); invalid[pair[0]] = pair[1]; bad.append(invalid)
	for i in bad.size():
		ls.restore_row(GATE,[1,0.25,true,bad[i]])
		step(2.0)
		check(near(ls.figure_t(GATE),0.25) and near(ls.physical_t(GATE),0.25),"malformed/unknown transition tail ignored "+str(i))
	# The existing drawbridge serialization/clock importer must remain byte-for-byte compatible.
	var fast := {"v":1,"seq":7,"stage":0,"physical":1.0,"from":1.0,"target":0.0,"elapsed":3,"total":6}
	ls.restore_row(GATE,[0,0.5,true,fast])
	var retained := ls.export_row(GATE)
	check(retained.size()==4 and retained[3]==fast,"existing drawbridge transition payload remains unchanged")
	for i in 3:
		s.world._logic_step += 1; ls.tick()
	check(near(ls.figure_t(GATE),0) and near(ls.physical_t(GATE),0),"existing drawbridge remaining ticks still commit normally")
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for opt: Array in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"): GameData.options[opt[0]] = 0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	TutorialPanel.auto_show = false
	s = Session.new(); add_child(s); s.set_physics_process(false)
	game = Game.new(); game.session = s; s.game = game; add_child(game)
	s.state.ensure_hero(0,"Human Hero"); s._enter_zone("gz15h",1,false)
	check(s.world != null and s.zone_id == "gz15h","actual original zone loads without an external save fixture"); stop_simulation()
	var obj: Dictionary = s.world.objects[GATE].get_meta("ei")
	evidence.original_object = obj; evidence.switch_time = s.world.lever_sys.switch_time(GATE)
	check(obj.name == "YardGates04" and not s.world.lever_sys._fast(GATE),"original prison gate uses ordinary native transition")
	var all_cells := []
	for y in range(207,224):
		for x in range(155,176): all_cells.append(Vector2(x*0.5+0.25,y*0.5+0.25))
	call_state(0,0.0); cells=all_cells; var closed := physical_cells()
	call_state(1,0.0); var opened := physical_cells(); cells=[]
	for i in all_cells.size():
		if closed[i] != opened[i]: cells.append(all_cells[i])
	check(not cells.is_empty(),"actual gate changes navigation cells across native states")
	evidence.changed_cells = cells.map(func(p):return [p.x,p.y])
	roundtrip_case(1,12.0)
	roundtrip_case(0,12.5)
	metadata_controls()
	evidence.checks=checks; evidence.failures=failures
	FileAccess.open("user://lever-transition-save.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	game.queue_free(); s.queue_free()
	for i in 10: await get_tree().process_frame
	TexUpscale.shutdown(); print("LEVER_TRANSITION_SAVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
