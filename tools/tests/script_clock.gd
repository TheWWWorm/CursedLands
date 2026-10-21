extends Node
## Original scene-clock commands versus real VM ticks and saved campaign time.
const P := preload("res://src/game/script/script_parser.gd")
var checks := 0
var failures: Array = []
var observations: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 10: printerr("FAIL ",label)

func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/fixtures/original_script_clock.json"))
	var campaign := "lost_in_astral" if GameData.campaign_id == CampaignProfile.ASTRAL else "original"
	if not data.campaigns.has(campaign): printerr("Missing qualified native clock fixture"); get_tree().quit(2); return
	var s := Session.new(); s.process_mode = Node.PROCESS_MODE_DISABLED; add_child(s)
	var w := GameWorld.new(); w.process_mode = Node.PROCESS_MODE_DISABLED; w.presentation = false
	w.nav = NavGrid.new(); w.session = s; s.world = w; add_child(w)
	for index in data.campaigns[campaign].cases.size():
		var case: Dictionary = data.campaigns[campaign].cases[index]
		s.state = CampaignState.new(); s.state.set_var(0,"gtime",float(case.initial_gtime))
		s.state.set_scene_hour(float(case.initial_gtime)) # supplied initial scene clock, as in native capture
		var vm := ScriptVM.create(w,s); w.vm = vm
		for row: Dictionary in case.rows:
			var action: Dictionary = row.action
			if action.op == "advance":
				vm.tick(float(action.ticks)*GameUnit.TICK)
			elif action.op != "initial":
				vm._call(action.op,[[P.N_NUM,float(action.hour)]],ScriptVM.Instance.new())
			var expected: Dictionary = row.state
			var actual := {"hour":vm._call("GetWorldTime",[],ScriptVM.Instance.new()),"gtime":s.state.get_var(0,"gtime"),"fixed":vm.time_fixed}
			var label := "%d / %s / %s"%[index,str(action),str(expected)]
			# Native offset rounding can return 24.0 just below midnight.
			# Compare hours circularly; all raw values remain in the trace.
			check(absf(wrapf(float(actual.hour)-float(expected.hour),-12.0,12.0)) < 0.00002,"original scene hour / "+label)
			check(absf(float(actual.gtime)-float(expected.gtime)) < 0.00002,"original campaign timer / "+label)
			check(bool(actual.fixed) == (float(expected.rate)==0.0),"original clock freeze / "+label)
			observations.append({"case":index,"action":action,"expected":expected,"actual":actual})
			if action.op == "FixWorldTime":
				check(s.state.save("user://script-clock-state.sav")==OK,"save after scene clock reset")
				var saved := CampaignState.load_from("user://script-clock-state.sav")
				check(absf(saved.get_var(0,"gtime")-float(expected.gtime))<0.00002,"saved campaign timer remains independent")
				check(saved.day==int(float(expected.gtime)/24.0)+1,"campaign day follows elapsed time")
		w.vm = null; vm.world = null; vm.session = null; vm.briefings.vm = null
	# Legacy documents contain only day/hour; retain that finite information
	# on import rather than inventing an earlier, already lost campaign time.
	var legacy := s.state.to_dict(); legacy.erase("campaign_time")
	legacy.day=3; legacy.world_time=7.25
	FileAccess.open("user://script-clock-legacy.sav",FileAccess.WRITE).store_var(legacy)
	var imported := CampaignState.load_from("user://script-clock-legacy.sav")
	check(imported.get_var(0,"gtime")==55.25,"legacy day/hour imports as the available campaign time")
	imported.set_scene_hour(0.3)
	check(imported.get_var(0,"gtime")==55.25,"first scene reset preserves an imported campaign timer")
	imported.set_var(0,"gtime",47.5); imported.set_scene_hour(0.3)
	imported.advance_hours(1.0)
	check(imported.get_var(0,"gtime")==48.5 and imported.day==3,"campaign date rolls over independently of scene midnight")
	check(is_equal_approx(imported.world_time,1.3),"elapsed travel retains the independent scene-hour offset")
	FileAccess.open("user://script-clock.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":GameData.campaign_id,
		"checks":checks,"failures":failures,"observations":observations},"\t"))
	s.world = null; w.free(); s.free()
	print("SCRIPT_CLOCK ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
