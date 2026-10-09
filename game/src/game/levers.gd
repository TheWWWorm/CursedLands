class_name LeverSystem
extends RefCounted
## Levers are map objects with states: switches, gates, doors, portcullises,
## chests, bridges. the original CLeverObject shows a state
## morphing its figure: SetState sets the target t = state
## (states − 1) and the update moves the complexion's second
## component there over the switch time, so the FIG variants hold the
## closed / open shapes (EIFigure.instantiate with morph). SetState also sets
## the morph axis to the target at once and places the object anew in the AI
## map: its footprint is that
## the target state (NavGrid.set_object_t).

var world: GameWorld
var _morph := {}   # nid -> {"nodes": [Node3D with p0 / p1], "meshes": [MeshInstance3D], "t": float}
var _tweens := {}
var _ordinary := {} # nid -> native from/target/duration and elapsed ticks at Tween creation
# Fast mechanisms retain their last committed navigation pose until the
# authoritative world completes the visible drop. Clients only draw it.
const DEFAULT_SCIENCE := [1, 0, 0]
const MOTION_VERSION := 1
const FAST_TICKS := 6
var _physical := {}
var _motions := {}
var _motion_seq := {}
var _motion_state := {}
var _received := {}


func _init(w: GameWorld) -> void:
	world = w
	for nid in w.levers:
		add(nid)


func add(nid: int) -> void:
	var node: Node3D = world.objects.get(nid)
	if node:
		var m := {"nodes": [], "meshes": [], "t": 0.0}
		for n: Node in node.find_children("*", "Node3D", true, false):
			if n.has_meta("p0"):
				m.nodes.append(n)
			if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).mesh.get_blend_shape_count() > 0:
				m.meshes.append(n)
		_morph[nid] = m
		# A fresh map shows the saved figure as placed: the original keeps the.mob
		# complexion until the first SetState (the target starts at it).
		_set_t(nid, float(node.get_meta("ei", {}).get("complexion", Vector3.ZERO).x))
		_physical[nid] = figure_t(nid)


## Restores a saved lever (CampaignState): state plus the figure's t, as the
## original's save / load keep both.
func restore(nid: int, state: int, t: float) -> void:
	if not world.levers.has(nid):
		return
	_cancel(nid)
	_motion_state.erase(nid)
	world.levers[nid].state = state
	_set_t(nid, t)
	_physical[nid] = t
	world.nav.set_object_t(nid, t)


func figure_t(nid: int) -> float:
	return float(_morph.get(nid, {}).get("t", 0.0))


## Whether a hero may try Use on it: switches, chests, gates and doors alike;
## those whose LEVER_SCIENCE_STATS start with 0 ([0, 0, 0] house doors, cave
## doors, bridges, script gates) can never pass and are driven
## by scripts only.
func usable(nid: int) -> bool:
	if not world.levers.has(nid) or not bool(world.levers[nid].get("enabled", true)):
		return false
	var l: Array = world.levers[nid].get("science", DEFAULT_SCIENCE)
	return l.is_empty() or int(l[0]) != 0


## Use on a lever, the original action 0 -> CLeverObject
## . The lever's LEVER_SCIENCE_STATS L and the
## user's key K = [1, 0, round(Use value)], or a tool item's triple with the
## value added to its third number: with u = L[0] & K[0], the lever works when
## (u & 8 and K[1] == L[1]) or (u & 7 and L[2] <= K[2]). So [1, 0, 0] opens for
## anyone, [0, 0, 0] (gates, doors) never by hand, [8, N, 0] needs the quest
## item with script id N, [5, 0, 22] a Use value of 22.
## Approx.: the original takes the tool from the unit; the remake tries the
## plain key and then each quest item in the party bag, as [8, script id, 0]
## (the quest item's native getter returns [8, script id, 0]).
func science_ok(nid: int, use_value: float, quest_items: Array) -> bool:
	var l: Array = world.levers.get(nid, {}).get("science", [1, 0, 0])
	if l.size() < 3:
		return true
	#  stores the value as float32 before nearest-even FISTP.
	var value := float(PackedFloat32Array([use_value])[0])
	var lower := floori(value)
	var fraction := value - float(lower)
	var v := lower if fraction < 0.5 or (fraction == 0.5 and lower % 2 == 0) else lower + 1
	var keys := [[1, 0, v]]
	for it in quest_items:
		var sid := int(Items.info(String(it)).row.get("script_id", 0))
		if sid > 0:
			keys.append([8, sid, v])
	for k: Array in keys:
		var u := int(l[0]) & int(k[0])
		if u & 8 and int(k[1]) == int(l[1]):
			return true
		# (an unsigned compare in the original: a negative Use value passes)
		if u & 7 and (int(l[2]) & 0xFFFFFFFF) <= (int(k[2]) & 0xFFFFFFFF):
			return true
	return false


## Script SwitchLeverState(obj, state) / SwitchLeverStateEx(obj, state, time)
## and Use (state −1, time −10), the original: state < 0 = the next
## one (wrapping only when the lever is cycled, else stopping at the last);
## otherwise clamped to 0..states−1. Time < 0 = the lever's switch_time
## (levers.ldb, 10 without a record); ≤ 0 after that = at once. Returns the
## time used.
func set_state(nid: int, state: int, time := -10.0) -> float:
	var l: Dictionary = world.levers.get(nid, {})
	if l.is_empty():
		return 0.0
	var n := maxi(1, int(l.states))
	if state < 0:
		state = (int(l.state) + 1) % n if int(l.get("cycled", 0)) != 0 else mini(int(l.state) + 1, n - 1)
	else:
		state = clampi(state, 0, n - 1)
	l.state = state
	if time < 0.0:
		time = switch_time(nid)
	if _fast(nid) and time > FAST_TICKS:
		time = FAST_TICKS
	apply(nid, true, time)
	return time


func switch_time(nid: int) -> float:
	var node: Node3D = world.objects.get(nid)
	var row := GameData.db.find("levers", String(node.get_meta("ei", {}).get("template", ""))) if node else {}
	return float(row.get("switch_time", 10.0)) if not row.is_empty() else 10.0


func toggle(nid: int) -> void:
	set_state(nid, -1)


## `time` is in 55 ms ticks, as levers.ldb's T field and SwitchLeverStateEx.
## end = now + time + 1; uses the fractional
## render tick, t = target − (target − start)·(end − now)/time.
## Thus the first whole tick shows start, and time + 1 shows target. Before
## the first tick it extrapolates slightly away from target, as the original does.
func apply(nid: int, animate: bool, time := -1.0) -> void:
	var node: Node3D = world.objects.get(nid)
	if node == null or not is_instance_valid(node):
		return
	var l: Dictionary = world.levers.get(nid, {})
	var n := maxi(1, int(l.get("states", 2)))
	var target := float(l.get("state", 0)) / float(n - 1) if n >= 2 else 0.0
	if animate and _fast(nid):
		_fast_apply(nid, target, time if time >= 0.0 else switch_time(nid))
		return
	_cancel(nid)
	_motion_state.erase(nid)
	var m: Dictionary = _morph.get(nid, {})
	if time < 0.0:
		time = switch_time(nid)
	if animate and time > 0.0 and not m.is_empty() and not is_equal_approx(float(m.t), target):
		_start_ordinary(nid, {"kind": "ordinary", "v": 1, "from": float(m.t),
			"target": target, "ticks": time, "elapsed": 0.0})
	else:
		_set_t(nid, target)
	if animate:
		var row := GameData.db.find("levers", String(node.get_meta("ei", {}).get("template", "")))
		GameSound.at(String(row.get("switch_sound", "")), node.global_position)   # none without a row
	_physical[nid] = target
	world.nav.set_object_t(nid, target)


# Only the proved moving Orc drawbridge model uses the new policy. Static
# approaches and the keyed switches keep their original timing.
func _fast(nid: int) -> bool:
	var node = world.objects.get(nid)
	return world.authority and GameData.option("mechanism_motion") == 0 \
		and int(world.levers.get(nid, {}).get("states", 0)) == 2 \
		and is_instance_valid(node) and String(node.get_meta("ei", {}).get("template", "")) == "stbr9"


func _cancel(nid: int) -> void:
	if _tweens.has(nid):
		var tw: Tween = _tweens[nid]
		if tw.is_valid():
			tw.kill()
		_tweens.erase(nid)
	_ordinary.erase(nid)
	_motions.erase(nid)


## Native52b7a0 keeps the collision figure at the target while52b490
## draws from separate from/target/end/reciprocal fields.52b560/52b650
## serialize those fields. A rendered intermediate pose alone cannot
## restore either the physical target or the remaining animation.
func _start_ordinary(nid: int, data: Dictionary) -> void:
	var node: Node3D = world.objects.get(nid)
	if not is_instance_valid(node):
		return
	var left := float(data.ticks) + 1.0 - float(data.elapsed)
	var target := float(data.target)
	var start := target - (target - float(data.from)) * left / float(data.ticks)
	var tw := node.create_tween()
	_ordinary[nid] = data.duplicate(true)
	_tweens[nid] = tw
	tw.tween_method(func(v: float): _set_t(nid, v), start, target, left * GameUnit.TICK)
	tw.finished.connect(_finish_ordinary.bind(nid, tw))


func _finish_ordinary(nid: int, tween: Tween) -> void:
	if _tweens.get(nid) == tween:
		_tweens.erase(nid)
		_ordinary.erase(nid)


func _ordinary_payload(nid: int) -> Dictionary:
	if not _ordinary.has(nid) or not _tweens.has(nid):
		return {}
	var tw: Tween = _tweens[nid]
	if not tw.is_valid():
		return {}
	var data: Dictionary = _ordinary[nid].duplicate(true)
	data.elapsed = minf(float(data.ticks) + 1.0,
		float(data.elapsed) + tw.get_total_elapsed_time() / GameUnit.TICK)
	return data if float(data.elapsed) < float(data.ticks) + 1.0 else {}


func _valid_ordinary(nid: int, data: Variant) -> bool:
	if not data is Dictionary or data.get("kind") != "ordinary" or not _integer(data.get("v"), 1, 1) \
		or not _number(data.get("from")) or not _endpoint(data.get("target")) \
		or not _number(data.get("ticks")) or not _number(data.get("elapsed")):
		return false
	var duration := float(data.ticks)
	var elapsed := float(data.elapsed)
	if duration <= 0.0 or elapsed < 0.0 or elapsed >= duration + 1.0:
		return false
	var states := maxi(1, int(world.levers[nid].get("states", 2)))
	var target := float(world.levers[nid].state) / float(states - 1) if states >= 2 else 0.0
	# Optional metadata cannot change the authoritative logical state.
	return float(data.target) == target


func _sound(nid: int) -> void:
	var node = world.objects.get(nid)
	if not is_instance_valid(node):
		return
	var row := GameData.db.find("levers", String(node.get_meta("ei", {}).get("template", "")))
	GameSound.at(String(row.get("switch_sound", "")), node.global_position)


func _fast_apply(nid: int, target: float, time: float) -> void:
	# Repeated requests for the same endpoint do not restart a pending drop.
	if _motions.has(nid) and float(_motions[nid].target) == target:
		return
	var start := figure_t(nid)
	_cancel(nid)
	var seq := int(_motion_seq.get(nid, 0)) + 1
	_motion_seq[nid] = seq
	var physical := float(_physical.get(nid, start))
	var total := ceili(minf(time, FAST_TICKS)) if is_finite(time) and time > 0.0 else 0
	# Raising revokes the lowered deck before any visible movement. An
	# interrupted lowering retains the raised endpoint throughout reversal.
	if total == 0 or is_equal_approx(start, target):
		physical = target
	else:
		physical = 1.0
	_physical[nid] = physical
	world.nav.set_object_t(nid, physical)
	var data := {"v": MOTION_VERSION, "seq": seq, "stage": 0,
		"physical": physical, "from": start, "target": target, "elapsed": 0, "total": total}
	_motion_state[nid] = data
	if total == 0 or is_equal_approx(start, target):
		_set_t(nid, target)
		data.stage = 1
	else:
		var m := data.duplicate(true)
		m.born = world._logic_step
		m.resume_from = start
		m.resume_elapsed = 0
		m.draw_elapsed = 0.0
		_motions[nid] = m
	_sound(nid)


func physical_t(nid: int) -> float:
	return float(_physical.get(nid, figure_t(nid)))


func motion_payload(nid: int) -> Dictionary:
	if _motions.has(nid):
		var m: Dictionary = _motions[nid]
		return {"v": MOTION_VERSION, "seq": int(m.seq), "stage": 0,
			"physical": physical_t(nid), "from": float(m.from), "target": float(m.target),
			"elapsed": int(m.elapsed), "total": int(m.total)}
	return _motion_state.get(nid, {}).duplicate(true)


func export_row(nid: int) -> Array:
	var row := [int(world.levers[nid].state), figure_t(nid), bool(world.levers[nid].get("enabled", true))]
	var data := motion_payload(nid)
	if data.is_empty():
		data = _ordinary_payload(nid)
	if not data.is_empty():
		row.append(data)
	return row


# Saved and replicated rows share one importer. A legacy row keeps its
# historical settled interpretation; malformed optional tails are ignored.
func restore_row(nid: int, row: Variant) -> void:
	if not world.levers.has(nid) or not row is Array or row.size() < 2:
		return
	if not _number(row[0]) or not _number(row[1]):
		return
	restore(nid, int(row[0]), float(row[1]))
	if row.size() > 2:
		world.levers[nid].enabled = bool(row[2])
	if row.size() > 3:
		if _valid_ordinary(nid, row[3]):
			var target := float(row[3].target)
			_physical[nid] = target
			world.nav.set_object_t(nid, target)
			_start_ordinary(nid, row[3])
		else:
			_import_motion(nid, row[3], float(row[1]), false)


func receive(nid: int, state: int, data: Variant) -> bool:
	if not world.levers.has(nid) or not _valid_motion(data):
		return false
	var seen: Array = _received.get(nid, [-1, -1, -1])
	var seq := int(data.seq)
	var stage := int(data.stage)
	var elapsed := int(data.elapsed)
	if seq < int(seen[0]) or (seq == int(seen[0]) and (stage < int(seen[1]) \
		or (stage == int(seen[1]) and elapsed <= int(seen[2])))):
		return false
	world.levers[nid].state = state
	var draw := float(data.target) if stage == 1 else lerpf(float(data.from), float(data.target),
		float(elapsed) / float(maxi(1, int(data.total))))
	return _import_motion(nid, data, draw, true)


func _import_motion(nid: int, data: Variant, draw: float, sound: bool) -> bool:
	if not _valid_motion(data):
		return false
	_cancel(nid)
	_motion_seq[nid] = int(data.seq)
	_received[nid] = [int(data.seq), int(data.stage), int(data.elapsed)]
	_motion_state[nid] = data.duplicate(true)
	_physical[nid] = float(data.physical)
	# A commit assigns the final drawing before publishing its floor.
	_set_t(nid, float(data.target) if int(data.stage) == 1 else draw)
	world.nav.set_object_t(nid, float(data.physical))
	if int(data.stage) == 0:
		var m: Dictionary = data.duplicate(true)
		m.born = world._logic_step
		m.resume_from = draw
		m.resume_elapsed = int(data.elapsed)
		m.draw_elapsed = 0.0
		_motions[nid] = m
	if sound and (int(data.stage) == 0 or int(data.total) == 0):
		_sound(nid)
	return true


static func _number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _endpoint(v: Variant) -> bool:
	return _number(v) and float(v) >= 0.0 and float(v) <= 1.0


static func _integer(v: Variant, lo: int, hi: int) -> bool:
	return _number(v) and float(v) == floorf(float(v)) and float(v) >= lo and float(v) <= hi


static func _valid_motion(v: Variant) -> bool:
	if not v is Dictionary or not _integer(v.get("v"), MOTION_VERSION, MOTION_VERSION) \
		or not _integer(v.get("seq"), 1, 2147483647) or not _integer(v.get("stage"), 0, 1) \
		or not _integer(v.get("total"), 0, FAST_TICKS) or not _integer(v.get("elapsed"), 0, FAST_TICKS) \
		or not _endpoint(v.get("physical")) or not _endpoint(v.get("from")) or not _endpoint(v.get("target")):
		return false
	if int(v.elapsed) > int(v.total):
		return false
	if int(v.stage) == 0:
		return int(v.total) > 0 and int(v.elapsed) < int(v.total) \
			and (float(v.target) > 0.0 or float(v.physical) > 0.0)
	return float(v.physical) == float(v.target)


# Called only inside a completed authoritative world tick, before units.
func tick() -> void:
	if not world.authority:
		return
	for nid in _motions.keys():
		if not world.levers.has(nid) or not is_instance_valid(world.objects.get(nid)):
			_cancel(nid)
			_motion_state.erase(nid)
			continue
		var m: Dictionary = _motions[nid]
		if int(m.born) == world._logic_step:
			continue
		m.elapsed = int(m.elapsed) + 1
		_draw_motion(nid, m, 0.0)
		if int(m.elapsed) >= int(m.total):
			_set_t(nid, float(m.target))
			_physical[nid] = float(m.target)
			world.nav.set_object_t(nid, float(m.target))
			var data := motion_payload(nid)
			data.stage = 1
			_motion_state[nid] = data
			_motions.erase(nid)
			if world.session:
				world.session.broadcast({"t": "lever", "nid": nid, "state": int(world.levers[nid].state),
					"time": 0.0, "motion": data})


# Rendering never opens a floor. A client may reach the advertised pose
# before its reliable commit, and still retains the raised physical map.
func draw(dt: float) -> void:
	for nid in _motions.keys():
		if not world.levers.has(nid) or not is_instance_valid(world.objects.get(nid)):
			_cancel(nid)
			continue
		var m: Dictionary = _motions[nid]
		if world.authority:
			_draw_motion(nid, m, world.logic_fraction())
		else:
			m.draw_elapsed = minf(float(m.draw_elapsed) + maxf(0.0, dt) / GameUnit.TICK,
				float(int(m.total) - int(m.resume_elapsed)))
			_draw_motion(nid, m, float(m.draw_elapsed))


func _draw_motion(nid: int, m: Dictionary, fraction: float) -> void:
	var elapsed := int(m.elapsed) - int(m.resume_elapsed) if world.authority else 0
	var remain := maxi(1, int(m.total) - int(m.resume_elapsed))
	var f := clampf((float(elapsed) + fraction) / float(remain), 0.0, 1.0)
	_set_t(nid, lerpf(float(m.resume_from), float(m.target), f))


func _set_t(nid: int, t: float) -> void:
	var m: Dictionary = _morph.get(nid, {})
	if m.is_empty():
		return
	m.t = t
	for n: Node3D in m.nodes:
		if is_instance_valid(n):
			n.position = (n.get_meta("p0") as Vector3).lerp(n.get_meta("p1"), t)
	for mi: MeshInstance3D in m.meshes:
		if is_instance_valid(mi):
			mi.set_blend_shape_value(0, t)
