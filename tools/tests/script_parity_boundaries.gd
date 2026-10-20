extends Node
## Integration around native-qualified script boundaries: parsing, retained
## values, freed actors, quest objectives, and old/new area save records.
var checks := 0
var failures := 0

class PartyVM extends ScriptVM:
	var party: Array = []
	func heroes() -> Array:
		return party

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var world := GameWorld.new()
	var session := Session.new()
	session.state = CampaignState.new()
	var vm := PartyVM.new()
	vm.world = world
	vm.session = session
	vm.ast = ScriptParser.parse("""
		WorldScript (
			literal = IsEqual(16777217, 16777216)
			rounded = Add(16777216, 1)
			stored = IsEqual(rounded, 16777216)
			fraction = Div(1, 3)
			threshold = IsLess(fraction, 0.33333334)
			near = IsEqual(1, 1.000001)
			ids = IsEqual(1990002, 1990003)
			case_sensitive = IsEqualString("Quest", "quest")
			AddRectToArea(1, -654.125, -20.25, 123.4567, 9.87654)
			AddRoundToArea(2, 0, 0, 5)
			AddRectToArea(3, 10, 10, 0, 0)
		)
	""")
	check(vm.ast.errors.is_empty(), "production parser accepts the comparison script")
	var inst := ScriptVM.Instance.new()
	inst.blocks = [{"conds": [], "body": vm.ast.world}]
	vm._run(inst)
	check(vm.globals.literal == 1.0, "parsed literals have native float32 precision")
	check(vm.globals.rounded == 16777216.0 and vm.globals.stored == 1.0, "assigned results retain native precision")
	check(vm.globals.threshold == 0.0, "stored division does not cross the next quest threshold")
	check(vm.globals.near == 0.0 and vm.globals.ids == 0.0, "near numbers and adjacent actor IDs remain distinct")
	check(vm.globals.case_sensitive == 0.0, "quest string case is significant")

	var edge := Vector2(123.4567, 9.87654)
	check(vm._is_in_area(1, edge), "fractional upper corner is included exactly")
	check(not vm._is_in_area(3, Vector2(5, 5)), "reversed authored area remains empty")
	check(not vm._is_in_area(2, Vector2(3, 4)), "circle boundary is excluded")
	check(vm._is_in_area(2, Vector2(3, 3.99999)), "point just inside circle is included")
	check(not vm._is_in_area(99, Vector2.ZERO), "missing area is empty")
	var saved = bytes_to_var(var_to_bytes({"areas": vm.areas}))
	var restored := PartyVM.new()
	restored.world = world
	restored.session = session
	restored._restore(saved)
	check(restored._is_in_area(1, edge), "native rectangle corners survive VM save serialization and restore")
	check(not restored._is_in_area(2, Vector2(3, 4)), "circle boundary survives restore")
	restored._restore({"areas": {4: [Rect2(0, 0, 10, 10)]}})
	check(restored._is_in_area(4, Vector2(10, 10)), "older Rect2 save records remain readable")

	var hero := GameUnit.new()
	hero.world = world
	hero.pos = edge
	vm.party = [hero]
	check(vm._objective_met(["QObjArea", "1"], {}), "quest objective uses the same upper-corner rule")
	hero.pos = Vector2(3, 4)
	check(not vm._objective_met(["QObjArea", "2"], {}), "quest objective uses the same strict circle rule")
	var guard_rules = preload("res://src/game/script/story_guard_escape.gd")
	check(guard_rules._inside_gate(vm, edge), "guard contact uses the shared area rule")

	var target := [[ScriptParser.N_VAR, "target"]]
	inst.locals.target = hero
	hero.free()
	check(vm._call("DistanceUnitUnit", target + target, inst) > 1e29, "freed actors retain missing-distance sentinel")
	check(vm._call("DistanceUnitPoint", target + [[ScriptParser.N_NUM, 0.0], [ScriptParser.N_NUM, 0.0]], inst) > 1e29,
		"freed point-distance actor cannot appear near the origin")
	check(vm._call("UnitInSquare", target + [[ScriptParser.N_NUM, 0.0], [ScriptParser.N_NUM, 0.0],
		[ScriptParser.N_NUM, 10.0], [ScriptParser.N_NUM, 10.0]], inst) == 0.0, "freed actor cannot enter a rectangle")
	vm.party.clear()
	session.free()
	world.free()
	print("SCRIPT_PARITY_BOUNDARIES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
