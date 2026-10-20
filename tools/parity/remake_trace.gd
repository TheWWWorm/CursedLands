extends Node
## Emits observations from production game methods. This process receives only
## input fixtures. Native expectations and the comparator are not staged here.

class FixtureWorld extends GameWorld:
	var heights := {}
	var supplied_dark := 0.0
	var supplied_weather := 1.0
	var supplied_radius := 0.0
	func _tick_body(dt: float) -> void:
		time += dt
	func ground_at(x: float, y: float) -> float:
		return float(heights.get(Vector2(x, y), 0.0))
	func darkness() -> float:
		return supplied_dark
	func weather_sight_factor() -> float:
		return supplied_weather
	func object_radius(_node: Node3D) -> float:
		return supplied_radius

class RadiusUnit extends GameUnit:
	var supplied_body := 0.0
	func body_radius() -> float:
		return supplied_body

func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func bits(value: float) -> int:
	return PackedFloat32Array([value]).to_byte_array().decode_u32(0)

func _ready() -> void:
	var input_path := ""
	var output_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--parity-inputs="): input_path = argument.trim_prefix("--parity-inputs=")
		if argument.begins_with("--parity-output="): output_path = argument.trim_prefix("--parity-output=")
	if input_path.is_empty() or output_path.is_empty():
		push_error("Parity inputs and output are required")
		get_tree().quit(2)
		return
	var raw := FileAccess.get_file_as_string(input_path)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary or parsed.get("schema") != 1:
		push_error("Invalid parity input schema")
		get_tree().quit(2)
		return
	var profile := {}
	for key in ["confine_mouse", "show_fps", "volume_sfx", "volume_stream", "volume_voice"]:
		profile[key] = GameData.option(key)
	if profile != {"confine_mouse": 0, "show_fps": 1, "volume_sfx": 0, "volume_stream": 0, "volume_voice": 0}:
		push_error("Parity must run in an isolated, muted development profile")
		get_tree().quit(2)
		return
	GameData.difficulty = 0
	var rows := []
	for case: Dictionary in parsed.scenarios:
		var states: Array = capture(String(case.kind), case.inputs)
		if states.is_empty():
			push_error("Empty parity capture: " + String(case.id))
			get_tree().quit(2)
			return
		var steps := []
		for i in states.size():
			steps.append({"step": i, "state": states[i]})
		rows.append({"id": case.id, "steps": steps})
		print("REMAKE ", case.id, " ", steps.size())
	var output := {
		"schema": 1, "role": "remake", "input_sha256": raw.sha256_text(),
		"engine": Engine.get_version_info(), "profile": profile,
		"scenarios": rows
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot create parity capture")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("PARITY_CAPTURE_COMPLETE ", rows.size())
	get_tree().quit(0)

func capture(kind: String, data: Dictionary) -> Array:
	match kind:
		"clock": return capture_clock(data)
		"cast_rank": return capture_rank(data)
		"script_random": return capture_random(data)
		"sight_factor": return capture_sight(data)
		"interaction_reach": return capture_reach(data)
		"attack", "attack_chance": return capture_attack(data, kind == "attack_chance")
	push_error("Unsupported parity adapter: " + kind)
	return []

func capture_clock(data: Dictionary) -> Array:
	var world := FixtureWorld.new()
	world.retain_logic_debt = false
	var states := []
	for frame: Array in data.frames:
		var before := world._logic_step
		world._sample_frame(int(frame[0]), 55.0 / float(data.interval_ms), bool(frame[1]))
		states.append({
			"ticks": world._logic_step - before, "total_ticks": world._logic_step,
			"remainder_ms": world._logic_accumulator / GameUnit.TICK * float(data.interval_ms),
			"draw_fraction": world.logic_fraction(), "consumed_ms": world._frame_ms
		})
	world.free()
	return states

func capture_rank(data: Dictionary) -> Array:
	var world := FixtureWorld.new()
	var units: Array[GameUnit] = []
	for i in data.units.size():
		var row: Dictionary = data.units[i]
		var unit := GameUnit.new()
		unit.uid = i
		unit.world = world
		unit.pos = Vector2(row.pos[0], row.pos[1])
		# Rendering coordinates deliberately disagree with authoritative ones.
		unit.position = Vector3(unit.pos.x, 999.0, -unit.pos.y)
		unit.dead = bool(row.dead)
		world.heights[unit.pos] = f32(float(row.pos[2]))
		units.append(unit)
	var pool: Array = []
	for i in data.pool:
		pool.append(units[int(i)])
	var target: GameUnit = units[int(data.target)] if int(data.target) >= 0 else null
	if target:
		pool.erase(target)
		pool.push_front(target)
	var states := []
	while true:
		var pick := Spells._cast_pick(world, pool, target, Vector2(data.point[0], data.point[1]), f32(float(data.point[2])))
		if pick:
			pool.erase(pick)
		var remaining := []
		for unit: GameUnit in pool:
			remaining.append(unit.uid)
		states.append({"selected": pick.uid if pick else -1, "remaining": remaining})
		if pick == null or pool.is_empty():
			break
	for unit: GameUnit in units:
		unit.free()
	world.free()
	return states

func capture_random(data: Dictionary) -> Array:
	var states := []
	for word in data.words:
		states.append({"word": int(word), "value_bits": bits(ScriptVM.random_value(float(data.maximum), int(word)))})
	return states

func capture_sight(data: Dictionary) -> Array:
	var world := FixtureWorld.new()
	world.supplied_dark = f32(float(data.dark))
	world.supplied_weather = f32(float(data.weather))
	var unit := GameUnit.new()
	unit.world = world
	unit.proto = {"senses": [15.0, f32(float(data.night))]}
	var states := []
	for posture in data.postures:
		unit.stance = GameUnit.STANCE_CRAWL if int(posture) == 0 else GameUnit.STANCE_KNEEL if int(posture) == 1 else GameUnit.STANCE_NONE
		unit.action = "run" if int(posture) == 3 else "walk"
		states.append({"posture": int(posture), "factor_bits": bits(unit.sight_factor())})
	unit.free()
	world.free()
	return states

func capture_reach(data: Dictionary) -> Array:
	var world := FixtureWorld.new()
	var vm := ScriptVM.new()
	vm.world = world
	var unit := RadiusUnit.new()
	unit.figure_radius = f32(float(data.own_figure))
	unit.supplied_body = f32(unit.figure_radius + f32(0.2))
	var target: Node3D
	if data.kind == "lever":
		target = Node3D.new()
		world.supplied_radius = f32(float(data.target_use))
	else:
		var other := RadiusUnit.new()
		other.figure_radius = f32(float(data.target_figure))
		other.supplied_body = other.figure_radius
		other.dead = data.kind == "loot"
		target = other
	var result := vm._interact_reach(unit, target, String(data.kind))
	target.free()
	unit.free()
	vm.world = null
	world.free()
	return [{"reach_bits": bits(result)}]

func capture_attack(data: Dictionary, probability: bool) -> Array:
	var world := FixtureWorld.new()
	var combat := Combat.new(world)
	combat.difficulty_override = 0
	var attacker := GameUnit.new()
	var defender := GameUnit.new()
	attacker.world = world
	defender.world = world
	attacker.uid = 100
	defender.uid = 101
	attacker.stats = {"to_hit": int(data.attack), "parry": 0, "hit_random": float(data.spread)}
	defender.stats = {"to_hit": 0, "parry": int(data.defence)}
	attacker.pos = Vector2.ZERO
	defender.pos = Vector2(float(data.distance), 0.0)
	attacker.stats.actions = float(data.attack_actions)
	defender.stats.actions = float(data.defence_actions)
	defender.figure_radius = f32(float(data.radius)) - f32(0.05)
	var result: Dictionary
	if probability:
		result = {"probability": combat.hit_chance(attacker, defender)}
	else:
		result = {"hit": combat.attack_hits(attacker, defender, Combat.aim_penalty(int(data.aim)))}
	attacker.free()
	defender.free()
	combat.world = null
	world.free()
	return [result]
