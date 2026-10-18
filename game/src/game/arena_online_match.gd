class_name ArenaOnlineMatch
extends ArenaPveMatch
## Presentation only. Native movement, damage and outcomes arrive from the host.
var generation := ""
var serial := -1

func _ready() -> void:
	drives_clock = false
	super._ready()
	is_host = false

func prepare() -> void:
	if not is_instance_valid(world):
		formation.clear()
		_rebuild_world()
		world.authority = false
		world.set_meta("expedition_spell_safety", true)
		var scenery := ArenaTerrain.scenery(world.terrain,world)
		world.nav.build(world.terrain,world.terrain.water_base,scenery)

func apply_board(data: Dictionary) -> void:
	if String(data.generation) == generation and int(data.serial) <= serial: return
	if not data.full and (String(data.generation) != generation or int(data.serial) <= serial): return
	prepare()
	var deploying := int(data.phase) == Phase.DEPLOY
	var same_board := generation.get_slice(":", 0) == String(data.generation).get_slice(":", 0)
	if not deploying or not same_board: formation_motion.clear()
	if data.full:
		generation = String(data.generation); serial = -1
		var keep := {}
		for record: Dictionary in data.records:
			var uid := int(record.nid)
			var unit: GameUnit = world.units.get(uid)
			var previous_point: Vector2 = unit.get_meta("arena_placement", {}).get("point", Vector2.INF) if unit else Vector2.INF
			var origin := unit.pos if unit and same_board else Vector2.INF
			if unit and unit.info.prototype != record.prototype:
				formation_motion.movers.erase(unit)
				world.remove_unit(unit); unit = null
			var created := unit == null
			if created: unit = _spawn_record(record)
			elif record.has("snap") and (not deploying or not same_board): unit.apply_snapshot(record.snap, true)
			if unit:
				restore_body(unit, record.online_body)
				unit.set_meta("arena_placement", record.placement)
				unit.display_name = ArenaRules.title(record.prototype)
				unit.stats = record.runtime_stats.duplicate(true)
				keep[uid] = true
				if deploying and rendered:
					var target: Vector2 = record.placement.get("point", unit.pos)
					if created: formation_motion.enter(unit, target, origin)
					elif previous_point != target: formation_motion.move(unit, target)
		for unit: GameUnit in world.unit_rows():
			if not keep.has(unit.uid):
				formation_motion.movers.erase(unit)
				world.remove_unit(unit)
		round_army.assign(data.army.duplicate(true))
	elif not deploying:
		# Preparation destinations arrive in full formation records. Reapplying
		# stationary authority poses here would interrupt the local run-in.
		var snapshots := NetSnapshot.unpack(data.snaps)
		_apply_snap(snapshots, float(data.time), int(data.serial))
		for row: Array in snapshots:
			var unit: GameUnit = world.units.get(int(row[0]))
			if unit and row.size() > 17: restore_body(unit,row[17])
	serial = int(data.serial)
	world.time = float(data.time)
	damage = data.damage.duplicate()
	var previous := phase
	phase = int(data.phase) as Phase
	winner = int(data.winner)
	world.authority = false
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.set_process(true); world.set_physics_process(true)
	if phase == Phase.FINISHED:
		_stop_locomotion()
		if previous != Phase.FINISHED: finished.emit(winner)
	if phase != previous or data.full: changed.emit()

func apply_effects(data: Dictionary) -> void:
	if String(data.generation) != generation or not is_instance_valid(world): return
	for event: Dictionary in data.events:
		# Only visual/combat events are accepted, never campaign state or scripts.
		if String(event.get("t", "")) not in ["arrow", "direct_arrow", "spellfx", "spell_light", "hitnum", "blood", "sound", "unit_sound"] + Array(ParticleFx.EVENTS): continue
		_on_event(event)
		visual_event.emit(event)

func _process(dt: float) -> void:
	_update_death_marks(dt)
	if phase == Phase.FINISHED:
		_finish_effects(dt)
		settle_remaining = maxf(0.0, settle_remaining - dt)

func _physics_process(dt: float) -> void:
	if rendered and phase == Phase.DEPLOY and is_instance_valid(world):
		formation_motion.advance(dt / maxf(Engine.time_scale, 0.001), world)
func start() -> bool: return false
func toggle_pause() -> void: pass
func set_speed(_value: float) -> void: pass

static func restore_body(unit: GameUnit, body: PackedFloat64Array) -> void:
	if body.size() != unit.parts.size() + 1: return
	unit._set_max_hp(body[0])
	for index in unit.parts.size(): unit.parts[index].cur = body[index + 1]
