extends Node
## Script MoveToPoint (builtin 0x2) moves a unit at its gait, as the
## original's order pipeline replayed in Unicorn
## (fixtures/original_move_gait.json, original_move_gait.py):
## a move order without the double-click flag, so the unit runs with the run
## gait or, outside the party, while its combat flag is set. Its last run
## (GameUnit.running, true on a new unit) does not decide the gait.
const P := preload("res://src/game/script/script_parser.gd")

class Probe extends GameUnit:
	var sent: Array = []
	func command(o: Dictionary, _queue := false) -> void:
		sent.append(o)

var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _ready() -> void:
	var s := Session.new(); s.process_mode = Node.PROCESS_MODE_DISABLED; add_child(s)
	var w := GameWorld.new(); w.process_mode = Node.PROCESS_MODE_DISABLED; w.presentation = false
	w.nav = NavGrid.new(); w.session = s; s.world = w; add_child(w)
	var vm := ScriptVM.new(); vm.world = w; vm.session = s; w.vm = vm
	var path: String = get_script().resource_path.get_base_dir() + "/fixtures/original_move_gait.json"
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rows := 0
	for row: Dictionary in fixture.original.cases:
		if row.source != "script":
			continue
		rows += 1
		var u := Probe.new()
		u.controller = 0 if row.party else -1
		u.gait_run = int(row.gait) == 3
		u.alert = int(row.combat_flag) == 1
		u.running = true   # a new unit's, or a stale double-clicked run
		vm.globals.u = u
		vm._eval([P.N_CALL, "MoveToPoint", [[P.N_VAR, "u"], [P.N_NUM, 12.5], [P.N_NUM, 30.25]]],
			ScriptVM.Instance.new())
		var label := "%s gait %d flag %d" % ["party" if row.party else "npc", int(row.gait), int(row.combat_flag)]
		check(u.sent.size() == 1 and String(u.sent[0].get("type", "")) == "move", "one move order / " + label)
		if u.sent.size() == 1:
			# unit.gd's script / AI move: the order's run flag or the combat run.
			var runs := bool(u.sent[0].get("run", true)) or u.ai_combat_run()
			check(runs == (int(row.moves_at_gait) == 3), "original gait / " + label)
		u.free()
	check(rows == 8, "fixture has the eight script cases")
	w.vm = null; vm.world = null; vm.session = null; s.world = null; w.free(); s.free()
	print("SCRIPT_MOVE_GAIT %d checks %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
