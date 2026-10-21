extends Node
## Actual GS commands versus native interpreter/table captures. Map-entry
## observations belong to campaign_clock_coop's real Session transitions.
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
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir()+"/fixtures/original_campaign_clock.json"))
	var campaign := "lost_in_astral" if GameData.campaign_id == CampaignProfile.ASTRAL else "original"
	if not data.campaigns.has(campaign): printerr("Missing qualified native campaign-clock fixture"); get_tree().quit(2); return
	var s := Session.new(); s.process_mode = Node.PROCESS_MODE_DISABLED; add_child(s)
	var w := GameWorld.new(); w.process_mode = Node.PROCESS_MODE_DISABLED; w.presentation = false
	w.nav = NavGrid.new(); w.session = s; s.world = w; add_child(w)
	for index in data.campaigns[campaign].cases.size():
		var case: Dictionary = data.campaigns[campaign].cases[index]
		s.state = CampaignState.new(); s.state.set_var(0,"gtime",float(case.initial))
		s.state.set_scene_hour(0.3 if case.fixed else 11.75)
		var vm := ScriptVM.create(w,s); w.vm = vm
		vm.time_fixed=case.fixed; w.clock_fixed=case.fixed
		for row: Dictionary in case.rows:
			if row.action == "zone_hour": continue # actual map loads covered separately
			if row.action != "initial":
				var args := [[P.N_NUM,0.0],[P.N_STR,"gtime"]]
				if row.action != "GSDelVar": args.append([P.N_NUM,float(case.value)])
				vm._call(row.action,args,ScriptVM.Instance.new())
			var expected: Dictionary = row.state
			var actual := {"hour":vm._call("GetWorldTime",[],ScriptVM.Instance.new()),
				"gtime":vm._call("GSGetVar",[[P.N_NUM,0.0],[P.N_STR,"gtime"]],ScriptVM.Instance.new()),
				"fixed":vm.time_fixed,"present":s.state.gs_keys().has("gtime")}
			var label := "%d / %s / %s"%[index,row.action,str(expected)]
			check(absf(wrapf(float(actual.hour)-float(expected.hour),-12.0,12.0)) < 0.00002,"native scene hour / "+label)
			check(absf(float(actual.gtime)-float(expected.gtime)) < 0.00002,"native elapsed clock / "+label)
			check(actual.fixed==expected.fixed,"native freeze / "+label)
			check(actual.present==expected.present,"native GS presence / "+label)
			observations.append({"case":index,"action":row.action,"expected":expected,"actual":actual})
		var expected: Dictionary = case.rows[1].state
		check(s.state.save("user://campaign-clock-state.sav")==OK,"save clock after GS command")
		var saved := CampaignState.load_from("user://campaign-clock-state.sav")
		check(absf(saved.get_var(0,"gtime")-float(expected.gtime))<0.00002,"saved elapsed clock after GS command")
		check(absf(wrapf(saved.world_time-float(expected.hour),-12.0,12.0))<0.00002,"saved independent scene hour after GS command")
		check(saved.gs_keys().has("gtime")==bool(expected.present),"saved native GS presence after command")
		w.vm = null; vm.world = null; vm.session = null; vm.briefings.vm = null
	FileAccess.open("user://campaign-clock.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":GameData.campaign_id,
		"checks":checks,"failures":failures,"observations":observations},"\t"))
	s.world = null; w.free(); s.free()
	print("CAMPAIGN_CLOCK ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
