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


## Restores a saved lever (CampaignState): state plus the figure's t, as the
## original's save / load keep both.
func restore(nid: int, state: int, t: float) -> void:
	if not world.levers.has(nid):
		return
	world.levers[nid].state = state
	_set_t(nid, t)
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
	var l: Array = world.levers[nid].get("science", [1, 0, 0])
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
## (the item's own triple method was not located; the ids match the levers).
func science_ok(nid: int, use_value: float, quest_items: Array) -> bool:
	var l: Array = world.levers.get(nid, {}).get("science", [1, 0, 0])
	if l.size() < 3:
		return true
	var v := roundi(use_value)
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
	apply(nid, true, time)
	return time


func switch_time(nid: int) -> float:
	var node: Node3D = world.objects.get(nid)
	var row := GameData.db.find("levers", String(node.get_meta("ei", {}).get("template", ""))) if node else {}
	return float(row.get("switch_time", 10.0)) if not row.is_empty() else 10.0


func toggle(nid: int) -> void:
	set_state(nid, -1)


## Shows the state: the figure morphs to t = state / (states − 1) over `time`
## seconds (: t = target − (target − start)·(end − now)/time with
## end = start time + time + 1; **approx.**: taken as one second at the start
## value, then linear), plays the switch sound and updates navigation.
func apply(nid: int, animate: bool, time := -1.0) -> void:
	var node: Node3D = world.objects.get(nid)
	if node == null or not is_instance_valid(node):
		return
	var l: Dictionary = world.levers.get(nid, {})
	var n := maxi(1, int(l.get("states", 2)))
	var target := float(l.get("state", 0)) / float(n - 1) if n >= 2 else 0.0
	if _tweens.has(nid) and _tweens[nid].is_valid():
		_tweens[nid].kill()
	var m: Dictionary = _morph.get(nid, {})
	if time < 0.0:
		time = switch_time(nid)
	if animate and time > 0.0 and not m.is_empty() and not is_equal_approx(float(m.t), target):
		var tw := node.create_tween()
		tw.tween_interval(1.0)
		tw.tween_method(func(v: float): _set_t(nid, v), float(m.t), target, time)
		_tweens[nid] = tw
	else:
		_set_t(nid, target)
	if animate:
		var row := GameData.db.find("levers", String(node.get_meta("ei", {}).get("template", "")))
		GameSound.at(String(row.get("switch_sound", "")), node.global_position)   # none without a row
	world.nav.set_object_t(nid, target)


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
