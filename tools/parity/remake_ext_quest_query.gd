extends RefCounted
## Remake side of cases_ext_quest_query.py: production ScriptVM._eval.

class QueryWorld extends GameWorld:
	var heights := {}
	var night := 0.0
	var party: Array[GameUnit] = []
	func ground_at(x: float, y: float) -> float:
		return float(heights.get(Vector2(x, y), 0.0))
	func darkness() -> float:
		return night
	func party_units() -> Array[GameUnit]:
		return party

func kinds() -> Array:
	return ["quest_query"]

## Party record 0 is the protagonist (state.heroes[0]); later records are
## active mercenaries (state.mercs) in record order. A record whose actor is
## absent keeps its roster entry without a world actor.
func _party(data: Dictionary, units: Array, world: QueryWorld, state: CampaignState) -> void:
	var roster := []
	for i in data.get("party", []).size():
		var row: Dictionary = data.party[i]
		var hero := {"name": "record%d" % int(row.id)}
		if i == 0:
			roster.append(hero)
		else:
			hero["merc"] = true
			hero["party"] = state.current_party
			state.mercs["merc%d" % i] = hero
		var index := int(row.get("unit", -1))
		if index >= 0 and units[index] is GameUnit:
			var u: GameUnit = units[index]
			u.controller = 0
			u.set_meta("hero", hero)
			world.party.append(u)
	if not roster.is_empty():
		state.heroes[0] = roster

func capture(_kind: String, data: Dictionary, trace: Node) -> Array:
	var world := QueryWorld.new()
	world.night = trace.f32(float(data.get("night", 0.0)))
	var vm := ScriptVM.new()
	vm.world = world
	vm.ast = ScriptParser.new()
	var session: Session = trace.quest_session()
	session.state = trace.quest_state(data.get("variables", {}), data)
	vm.session = session
	var units: Array = trace.quest_units(data.units, world)
	for i in units.size():
		if units[i] is GameUnit:
			var row: Dictionary = data.units[i]
			units[i].mana = trace.f32(float(row.get("mana", 0.0)))
			units[i].max_mana = trace.f32(float(row.get("max_mana", 0.0)))
			units[i].faction = int(row.get("player", 0))
	_party(data, units, world, session.state)
	var inst := ScriptVM.Instance.new()
	trace.quest_groups(data.get("groups", {}), inst, units)
	var expression: Array = trace.quest_expression(data.expression, inst, units)
	var result = vm._eval(expression, inst)
	# An unimplemented builtin evaluates to null; script conditions read it as 0.
	var value := 0.0 if result == null else float(result)
	var states := [{"value_bits": trace.bits(value), "truth": vm._truthy(result)}]
	trace.free_quest_units(units)
	session.free()
	world.free()
	return states
