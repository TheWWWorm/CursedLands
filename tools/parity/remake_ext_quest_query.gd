extends RefCounted
## Remake side of cases_ext_quest_query.py: production ScriptVM._eval.

class NightWorld extends GameWorld:
	var heights := {}
	var night := 0.0
	func ground_at(x: float, y: float) -> float:
		return float(heights.get(Vector2(x, y), 0.0))
	func darkness() -> float:
		return night

func kinds() -> Array:
	return ["quest_query"]

func capture(_kind: String, data: Dictionary, trace: Node) -> Array:
	var world := NightWorld.new()
	world.night = trace.f32(float(data.get("night", 0.0)))
	var vm := ScriptVM.new()
	vm.world = world
	vm.ast = ScriptParser.new()
	var session: Session = trace.quest_session()
	session.state = trace.quest_state({}, data)
	vm.session = session
	var units: Array = trace.quest_units(data.units, world)
	for i in units.size():
		if units[i] is GameUnit:
			units[i].mana = trace.f32(float(data.units[i].get("mana", 0.0)))
			units[i].max_mana = trace.f32(float(data.units[i].get("max_mana", 0.0)))
	var inst := ScriptVM.Instance.new()
	var expression: Array = trace.quest_expression(data.expression, inst, units)
	var result = vm._eval(expression, inst)
	# An unimplemented builtin evaluates to null; script conditions read it as 0.
	var value := 0.0 if result == null else float(result)
	var states := [{"value_bits": trace.bits(value), "truth": vm._truthy(result)}]
	trace.free_quest_units(units)
	session.free()
	world.free()
	return states
