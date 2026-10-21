extends RefCounted
## Remake side of cases_ext_npc_ai.py: production UnitAI decisions with
## fixture subclasses that supply only the declared boundaries.

## Ground heights for the supplied unit positions (the native records carry z).
class NpcWorld extends GameWorld:
	var heights := {}
	var clear_rays := true
	func ground_at(x: float, y: float) -> float:
		return float(heights.get(Vector2(x, y), 0.0))
	func darkness() -> float:
		return 0.0
	func weather_sight_factor() -> float:
		return 1.0
	func sight_ray(_u: GameUnit, _o: GameUnit) -> float:
		return 1.0 if clear_rays else 0.0

## Declared boundaries: no perception scan candidates (the noticed list is an
## input), supplied danger cells.
class NpcAI extends UnitAI:
	var danger: Array = []
	func _notice_candidates(_u: GameUnit, _radius := NAN) -> Array:
		return []
	func danger_at(p: Vector2) -> bool:
		return danger.has(p)

## Declared boundaries: senses and the legs' wound factor are supplied.
class NpcUnit extends GameUnit:
	var terms := {}
	func sight_factor() -> float: return float(terms.get("sight_factor", 1.0))
	func vis_factor() -> float: return float(terms.get("visibility", 1.0))
	func detect(which: int) -> float:
		return float(terms.get("notice_life_detect", 0.0)) if which == 2 else float(terms.get("notice_sight_detect", 0.0))
	func sense(which: int) -> float:
		return float(terms.get("notice_life", 1.0)) if which == 2 else float(terms.get("sight", 8.5))
	func wound_factor(type: int) -> float:
		return float(terms.get("wound", 1.0)) if type == 3 else super(type)


func kinds() -> Array:
	return ["npc_fear", "npc_suspicion"]


func capture(kind: String, data: Dictionary, trace: Node) -> Array:
	seed(20261021)
	match kind:
		"npc_fear": return capture_fear(data, trace)
		"npc_suspicion": return capture_suspicion(data, trace)
	push_error("Unsupported npc_ai kind " + kind)
	return []


func f32(trace: Node, v) -> float:
	return trace.f32(float(v))


func make_world(data: Dictionary) -> NpcWorld:
	var world := NpcWorld.new()
	world.zone = {"type": "game"}
	world.authority = false
	world.ai = NpcAI.new(world)
	world.ai.activity.enabled = false
	world.ai.distant.enabled = false
	for row: Array in data.get("relations", []):
		world.set_relation(int(row[0]), int(row[1]), int(row[2]))
	# Supplied ai.reg values (the native block 0x7c53e8 receives the same);
	# restored after the scenario so no other family observes them.
	_saved_reg = GameData.ai_reg.duplicate(true)
	for key: String in data.get("config", {}):
		var section := "RPG" if key == "DamageLevelRunLimit" else "Logic"
		if not GameData.ai_reg.has(section): GameData.ai_reg[section] = {}
		GameData.ai_reg[section][key] = float(data.config[key])
	return world


func make_units(data: Dictionary, world: NpcWorld, trace: Node) -> Array:
	var units := []
	var registry := {}
	for i in data.units.size():
		var row: Dictionary = data.units[i]
		var u := NpcUnit.new()
		u.world = world
		u.uid = i + 1
		u.faction = int(row.get("side", 1))
		u.controller = 0 if row.get("party", false) else -1
		u.dead = bool(row.get("dead", false))
		u.terms = row.duplicate()
		u.terms.notice_life_detect = 1000.0 if row.get("noticed", false) else 0.0
		u.stats = {"sight": f32(trace, row.get("sight", 8.5)), "ranged": bool(row.get("ranged", false))}
		u.proto = {"spells": ["spell0"] if row.get("spell0", false) else []}
		var c := int(row.get("move_class", 3))
		u._classes = [c, c, c]
		var parts := []
		for p: Dictionary in row.get("parts", []):
			parts.append({"type": int(p.type), "state": int(p.state), "cur": f32(trace, p.cur), "max": f32(trace, p.max),
				"size": f32(trace, p.get("size", 0.2)), "lethal": f32(trace, p.get("lethal", 0.0))})
		if not parts.is_empty(): u.parts = parts
		u.info = {"aggression": int(data.get("aggression", 3)), "logic_model": 3,
			"help_radius": f32(trace, row.get("help_radius", 10.0)), "alarm_cond": 0}
		place(u, row.pos, world, trace)
		registry[u.uid] = u
		units.append(u)
	world.units = registry
	return units


func place(u: GameUnit, pos: Array, world: NpcWorld, trace: Node) -> void:
	u.pos = Vector2(f32(trace, pos[0]), f32(trace, pos[1]))
	world.heights[u.pos] = f32(trace, pos[2] if pos.size() > 2 else 0.0)


func points(rows: Array, trace: Node) -> Array:
	var out := []
	for p: Array in rows:
		out.append(Vector2(f32(trace, p[0]), f32(trace, p[1])))
	return out


func perception_state(ai: UnitAI, u: GameUnit, trace: Node) -> Dictionary:
	if not u.has_meta("suspect"):
		return {"level": 0, "delta": 0, "point_bits": [0, 0]}
	var s: Dictionary = u.get_meta("suspect")
	var p: Vector2 = s.pos
	return {"level": int(ai._susp_level(s)), "delta": int(s.d), "point_bits": [trace.bits(p.x), trace.bits(p.y)]}


var _saved_reg := {}

func free_all(units: Array, world: GameWorld) -> void:
	for u in units: u.free()
	world.free()
	GameData.ai_reg = _saved_reg


func capture_fear(data: Dictionary, trace: Node) -> Array:
	var world := make_world(data)
	var ai: NpcAI = world.ai
	var units := make_units(data, world, trace)
	var u: NpcUnit = units[0]
	var noticed := {}
	for i in units.size():
		if data.units[i].get("noticed", false): noticed[units[i].get_instance_id()] = units[i]
		if data.units[i].get("fighting", false): units[i].order = {"type": "attack", "target": u}
	if not noticed.is_empty(): u.set_meta("noticed", noticed)
	var flag := int(data.flag)
	var states := []
	for k in data.ticks.size():
		var tick: Dictionary = data.ticks[k]
		# The production clock accumulates (time += dt), so do the same.
		world.time += GameUnit.TICK
		for index in tick.get("moves", {}):
			place(units[int(index)], tick.moves[index], world, trace)
		ai.danger = points(tick.get("danger", []), trace)
		var current := String(tick.get("current", "calm"))
		if current == "fear": u.set_meta("fear_on", true)
		else: u.remove_meta("fear_on")
		match String(tick.get("walking", "none")):
			"fear": u.order = {"type": "move", "to": u.pos, "fear": true, "calm": true}
			"other": u.order = {"type": "move", "to": u.pos, "calm": true}
			_: u.order = {}
		if current == "aggression":
			u.order = {"type": "attack", "target": units[int(tick.get("target", 1))], "ai": true}
		fear_events(ai, u, units, tick, "before", trace)
		# The noticed list is this tick's input; no new perception scan.
		u.set_meta("perceived", world.time)
		var priority := ai._fear_priority(u, flag)
		var s: Dictionary = u.get_meta("fear")
		var state := perception_state(ai, u, trace)
		state.merge({"decision_priority": priority, "j_bits": trace.bits(float(s.j)), "r_bits": trace.bits(float(s.r)),
			"kept_danger": s.has("danger")})
		states.append(state)
		fear_events(ai, u, units, tick, "after", trace)
	free_all(units, world)
	return states


## Events of tick k: "before" happen earlier in world tick k than the
## observer's decision (an attacker that ticked first), "after" later in it.
func fear_events(ai: UnitAI, u: GameUnit, units: Array, tick: Dictionary, when: String, trace: Node) -> void:
	for event: Dictionary in tick.get("events", []):
		if String(event.get("when", "after")) != when:
			continue
		if event.kind == "suspect":
			var p: Array = event.point
			ai.suspect(u, Vector2(f32(trace, p[0]), f32(trace, p[1])), float(event.level), float(event.delta))
		elif event.kind == "hit":
			ai.on_attacked(u, units[int(event.by)])


## Suspicion records of the living non-party units. World tick order: the
## clock advances, "before" events (earlier in the tick than the units'
## decisions), the decision-time observation, "after" events (later in the
## tick), then UnitAI.tick() (the delayed help sounds, after every unit).
func capture_suspicion(data: Dictionary, trace: Node) -> Array:
	var world := make_world(data)
	var ai: NpcAI = world.ai
	var units := make_units(data, world, trace)
	var watched := []
	for i in units.size():
		if not data.units[i].get("party", false) and not data.units[i].get("dead", false):
			watched.append(i)
	var states := []
	for k in data.ticks.size():
		var tick: Dictionary = data.ticks[k]
		world.time += GameUnit.TICK
		for index in tick.get("moves", {}):
			place(units[int(index)], tick.moves[index], world, trace)
		suspicion_events(ai, units, tick, "before", trace)
		var rows := []
		for i: int in watched:
			var u: GameUnit = units[i]
			var row := perception_state(ai, u, trace)
			var pending := []
			for e: Array in ai._help:
				if e[0] == u:
					pending.append(int(e[2]))
			row.pending = pending
			rows.append(row)
		states.append({"units": rows})
		suspicion_events(ai, units, tick, "after", trace)
		ai.tick()
	free_all(units, world)
	return states


func suspicion_events(ai: UnitAI, units: Array, tick: Dictionary, when: String, trace: Node) -> void:
	for event: Dictionary in tick.get("events", []):
		if String(event.get("when", "after")) != when:
			continue
		var u: GameUnit = units[int(event.get("unit", 0))]
		match String(event.kind):
			"suspect":
				var p: Array = event.point
				ai.suspect(u, Vector2(f32(trace, p[0]), f32(trace, p[1])), float(event.level), float(event.delta))
			"help":
				var h: Array = event.point
				ai.call_for_help(u, Vector2(f32(trace, h[0]), f32(trace, h[1])))
			"hit":
				ai.hit_hook(u, units[int(event.by)] if event.get("by") != null else null)
