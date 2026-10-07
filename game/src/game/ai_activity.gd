class_name AIActivity
extends RefCounted
## Shared broad activity pass and deadline-driven quiet AI. This is derived
## state, rebuilt after scripts each server tick; it is never saved/networked.
## A negative activity result only permits deferring an otherwise inert calm
## decision. Movement, perception of active actors, combat and timers keep
## their ordinary update rate. No camera or client visibility is consulted.

const CELL := 32.0
## A pair can close by at most this much while the batch is valid: each
## actor gets half the envelope. A longer move immediately invalidates the
## batch in moved(), so fast movement and teleports use live decisions.
## Sixteen metres kept distant actors scanning despite their short steps.
const MOTION_MARGIN := 2.0
const EMPTY: Dictionary = {}
var world: GameWorld
var enabled := not OS.get_cmdline_user_args().has("--ei-legacy-ai")
var coarse := OS.get_cmdline_user_args().has("--ei-coarse-activity")
var _kernel: RefCounted
var _quiet := {}
var _origins := {}
var _revision := -1
var _registry_revision := -1
var _structure_revision := -1
var _valid := false
var _owned_batch := false
var _diplomacy := PackedInt32Array()
var _side_masks := PackedInt64Array()
var deferred := 0
var considered := 0
var batch_usec := 0
var batches := 0


func _init(w: GameWorld) -> void:
	world = w
	if ClassDB.class_exists("AIActivityKernel") and not OS.get_cmdline_user_args().has("--ei-script-activity"):
		_kernel = ClassDB.instantiate("AIActivityKernel")


func begin_tick(dt: float) -> void:
	_valid = false
	_owned_batch = false
	if not enabled or not world.authority or dt != GameUnit.TICK:
		return
	if not world.dialog_actors.is_empty() or (world.vm != null and not world.vm.briefings.active.is_empty()):
		return
	var start := Time.get_ticks_usec()
	var rows: Array = world.unit_rows()
	_quiet.clear()
	_origins.clear()
	# Fighting/scripted populations cannot benefit from an idle batch. Do
	# not pack senses or query the grid when there is no potential waiter.
	var needed := false
	for u: GameUnit in rows:
		if is_instance_valid(u) and u.controller < 0 and not u.dead and not u.hidden and not u.alert \
				and not bool(u.info.get("use_in_script", false)) and u.mode in UnitAI.CALM_MODES and u.has_meta("calm"):
			needed = true
			break
	if not needed:
		return
	if _side_masks.is_empty() or _diplomacy != world.diplomacy:
		# Packed arrays are shared references in GDScript. Keep an owned
		# copy so an in-place diplomacy edit remains detectable next tick.
		_diplomacy = world.diplomacy.duplicate()
		_side_masks.resize(32); _side_masks.fill(0)
		for side in 32:
			for other in 32:
				if world.relation(side, other) == 2: _side_masks[side] |= 1 << other
	if not coarse and _kernel and _kernel.has_method("begin_world"):
		if not _kernel.begin_world(rows, _side_masks, world.darkness(), world.weather_sight_factor(), MOTION_MARGIN, GameUnit):
			return
		_owned_batch = true
	else:
		for u: GameUnit in rows:
			if not is_instance_valid(u):
				return
			_origins[u.get_instance_id()] = u.pos
		var active: PackedByteArray
		if not coarse and _kernel and _kernel.has_method("evaluate_world"):
			active = _kernel.evaluate_world(rows, _side_masks, world.darkness(), world.weather_sight_factor(), MOTION_MARGIN)
		else:
			active = _capture_script(rows)
		for i in rows.size():
			if active[i] == 0:
				_quiet[rows[i].get_instance_id()] = true
	_revision = GameUnit.notice_revision
	_registry_revision = world.units_revision
	_structure_revision = GameUnit.structure_revision
	_valid = true
	batches += 1
	batch_usec += Time.get_ticks_usec() - start


func _capture_script(rows: Array) -> PackedByteArray:
	var positions := PackedVector2Array()
	var radii := PackedFloat64Array()
	var terms := PackedFloat64Array()
	var factions := PackedInt64Array()
	var flags := PackedByteArray()
	var masks := PackedInt64Array()
	positions.resize(rows.size()); radii.resize(rows.size()); terms.resize(rows.size() * 5)
	factions.resize(rows.size()); flags.resize(rows.size()); masks.resize(rows.size())
	for i in rows.size():
		var u: GameUnit = rows[i]
		positions[i] = u.pos
		factions[i] = u.faction
		masks[i] = _side_masks[u.faction] if u.faction >= 0 and u.faction < 32 else -1
		flags[i] = (1 if u.controller >= 0 else 0) | (2 if u.dead else 0) | (4 if u.hidden else 0)
		var sight := (float(u.stats.get("sight", 0.0)) + u.sense_bonus(0)) * u.sight_factor()
		var life := u.sense(2)
		if coarse:
			var grid := UnitAI._friend_grid(maxf(sight, life) / 16.0)
			radii[i] = maxf(64.0, (float(grid.reach) + 1.0) * 24.0 + MOTION_MARGIN)
		else:
			var detection: Array = Array(u.proto.get("detection", []))
			terms[i * 5] = sight
			terms[i * 5 + 1] = life
			terms[i * 5 + 2] = float(u.proto.get("peripheral_skills", 0.0))
			var high := [0.0, 0.0, 0.0]
			for buff: Dictionary in u.buffs.values():
				if buff.has("detect") and buff.detect.size() >= 2:
					var index := int(buff.detect[0])
					if index >= 0 and index < 3:
						high[index] = maxf(high[index], float(buff.detect[1]))
			terms[i * 5 + 3] = maxf(0.0, (float(detection[0]) if detection.size() > 0 else 1.0) + high[0]) * 1.5
			terms[i * 5 + 4] = maxf(0.0, (float(detection[2]) if detection.size() > 2 else 1.0) + high[2])
	if coarse:
		return _kernel.evaluate(positions, radii, factions, flags, masks) if _kernel else evaluate_script(positions, radii, factions, flags, masks)
	return evaluate_senses_script(positions, terms, factions, flags, masks, MOTION_MARGIN)


func end_tick() -> void:
	_valid = false


func invalidate() -> void:
	_valid = false


func moved(u: GameUnit) -> void:
	if not _valid:
		return
	var beyond: bool = _kernel.moved_beyond(u, u.pos, MOTION_MARGIN * MOTION_MARGIN * 0.25) if _owned_batch \
		else u.pos.distance_squared_to(_origins.get(u.get_instance_id(), Vector2.INF)) > MOTION_MARGIN * MOTION_MARGIN * 0.25
	if beyond:
		# Teleports and unusually large moves cannot outrun the snapshot's
		# margin (half for the observer, half for its target). Remaining
		# decisions in this tick immediately fall back.
		_valid = false


func defer_decision(u: GameUnit) -> bool:
	considered += 1
	if not _valid or _revision != GameUnit.notice_revision or _registry_revision != world.units_revision \
			or _structure_revision != GameUnit.structure_revision \
			or not _owned_batch and not _quiet.has(u.get_instance_id()):
		return false
	if _owned_batch:
		if not _kernel.can_defer_in_batch(u, world.ai, world.time, GameUnit, UnitAI):
			return false
	elif _kernel and _kernel.has_method("can_defer_owned"):
		if not _kernel.can_defer_owned(u, world.ai, world.time, GameUnit, UnitAI):
			return false
	elif _kernel and _kernel.has_method("can_defer"):
		if not _kernel.can_defer(u, world.ai, world.time):
			return false
	elif not _eligible_script(u):
		return false
	# A wake-up must sample current neighbours, never a pre-sleep cached
	# candidate list. It can react on its very next normal decision tick.
	u.remove_meta("ai_near_t")
	u.remove_meta("perceived")
	u.ai_next = world.time + GameUnit.TICK - 0.0001
	deferred += 1
	return true


## Independent live-state oracle and fallback. No eligibility is cached:
## a wound, order, alarm or script edit earlier in this tick must wake AI.
func _eligible_script(u: GameUnit) -> bool:
	# Health is derived from body parts. _hp is only the fallback for units
	# without parts; co-op scaling changes max HP without updating that field.
	if u.controller >= 0 or u.dead or u.hidden or u.alert or u.has_meta("hero") \
			or not u.mode in UnitAI.CALM_MODES or bool(u.info.get("use_in_script", false)) \
			or not u.orders.is_empty() or u.order_failed or u._anim_lock > 0.0 \
			or not u._pending_hit.is_empty() or not u.buffs.is_empty() or u.hp < u.max_hp:
		return false
	if u.has_meta("suspect") or u.has_meta("fear_on") or u.has_meta("attacker") \
			or u.has_meta("um") or u.has_meta("alerted") or u.has_meta("hate") or u.has_meta("peace") \
			or not (u.get_meta("noticed", EMPTY) as Dictionary).is_empty() \
			or not (u.get_meta("seen_corpses", EMPTY) as Dictionary).is_empty() \
			or not world.ai.dangers.is_empty() or not world.ai._spell_list(u)[1].is_empty():
		return false
	var fear: Dictionary = u.get_meta("fear", EMPTY)
	if float(fear.get("r", 10.0)) != 10.0 or float(fear.get("j", 3.0)) != 3.0 or fear.has("danger"):
		return false
	var calm: Dictionary = u.get_meta("calm", EMPTY)
	if u.mode == "standard" and not int(world.ai.logic(u).get("logic_model", 3)) in [1, 2, 3, 5]:
		return false
	if not calm.get("busy", false):
		return false
	if u.order.is_empty():
		if float(calm.get("until", -1.0)) <= world.time:
			return false # Patrol/glance deadline: choose the next action now.
	elif not u.order.get("calm", false) or u.order.get("type", "") != "move":
		return false
	return true


static func evaluate_script(positions: PackedVector2Array, radii: PackedFloat64Array,
		factions: PackedInt64Array, flags: PackedByteArray, masks: PackedInt64Array) -> PackedByteArray:
	var n := positions.size()
	var active := PackedByteArray()
	active.resize(n); active.fill(1)
	if radii.size() != n or factions.size() != n or flags.size() != n or masks.size() != n:
		return active
	var cells := {}
	for i in n:
		var p := positions[i]
		if not p.is_finite() or absf(p.x) > 1e7 or absf(p.y) > 1e7 or factions[i] < 0 or factions[i] >= 32:
			return active
		if flags[i] & 4:
			continue
		var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		var cell: PackedInt64Array = cells.get(key, PackedInt64Array([0, 0]))
		cell[0] |= 1 << factions[i]
		if flags[i] & 3: cell[1] = 1
		cells[key] = cell
	for i in n:
		var p := positions[i]
		var r := radii[i]
		if flags[i] != 0 or not is_finite(r) or r < 0.0 or r > 512.0:
			continue
		var found := false
		for y in range(floori((p.y - r) / CELL), floori((p.y + r) / CELL) + 1):
			for x in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
				var dx := maxf(maxf(x * CELL - p.x, p.x - (x + 1.0) * CELL), 0.0)
				var dy := maxf(maxf(y * CELL - p.y, p.y - (y + 1.0) * CELL), 0.0)
				if dx * dx + dy * dy > r * r:
					continue
				var key := Vector2i(x, y)
				if not cells.has(key): continue
				var c: PackedInt64Array = cells[key]
				if c[1] != 0 or (c[0] & masks[i]) != 0:
					found = true
					break
			if found: break
		active[i] = 1 if found else 0
	return active


## Deliberately independent all-pairs oracle / fallback for the native grid.
## The envelope permits either actor to move up to half the margin this tick.
static func evaluate_senses_script(positions: PackedVector2Array, terms: PackedFloat64Array,
		factions: PackedInt64Array, flags: PackedByteArray, masks: PackedInt64Array, margin: float) -> PackedByteArray:
	var n := positions.size()
	var active := PackedByteArray()
	active.resize(n); active.fill(1)
	if terms.size() != n * 5 or factions.size() != n or flags.size() != n or masks.size() != n \
			or not is_finite(margin) or margin < 0.0 or margin > 512.0:
		return active
	var max_sight := 0.0
	var max_life := 0.0
	for i in n:
		var p := positions[i]
		if not p.is_finite() or absf(p.x) > 1e7 or absf(p.y) > 1e7 or factions[i] < 0 or factions[i] >= 32:
			return active
		for k in 5:
			if not is_finite(terms[i * 5 + k]) or terms[i * 5 + k] < 0.0: return active
		if not flags[i] & 4:
			max_sight = maxf(max_sight, terms[i * 5 + 3])
			max_life = maxf(max_life, terms[i * 5 + 4])
	for i in n:
		if flags[i] != 0: continue
		var bound := maxf(maxf(terms[i * 5] * max_sight, terms[i * 5 + 1] * max_life), terms[i * 5 + 2]) + margin
		if not is_finite(bound) or bound > 512.0: continue
		active[i] = 0
		for j in n:
			if i == j or flags[j] & 4: continue
			if not flags[j] & 3 and not masks[i] & (1 << factions[j]): continue
			var reach := maxf(maxf(terms[i * 5] * terms[j * 5 + 3],
					0.0 if flags[j] & 2 else terms[i * 5 + 1] * terms[j * 5 + 4]), terms[i * 5 + 2]) + margin
			var dx := float(positions[i].x) - float(positions[j].x)
			var dy := float(positions[i].y) - float(positions[j].y)
			if dx * dx + dy * dy <= reach * reach:
				active[i] = 1
				break
	return active
