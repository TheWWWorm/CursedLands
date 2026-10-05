class_name QuestLights
extends Node
## Quest-info dispatch on every peer. refreshes all existing
## objects on creation; refreshes matching names on a q.* change.
## Outer CUnit and the other map-object classes forward through
##  to their class47 logic component's
## state 1 creates a quest light, state 2 removes it; 0 leaves
## it alone. Colour/range are registry Quest Light R/G/B/Radius defaults
## 200/255/255, 10; places it 2 m above its carrier, flag 0x40
## sends it through the additive light pass. The original minimap lists it.
## A unit also pushes white through its figure's
## until that light is removed. Creature controller class48 / 537c00
## is the separate electrical-hit flash, not quest-info dispatch.

const COLOR := Color8(200, 255, 255)
const RADIUS := 10.0

var game: Game
var _world: GameWorld
var lights := {}       # map-object nid -> OmniLight3D
var _objects := {}     # nid -> [Node3D, quest-info name, last GS value]
var _scan := 0.0


func _init(g: Game) -> void:
	game = g
	name = "QuestLights"


func on_world(w: GameWorld) -> void:
	if is_instance_valid(_world) and _world.unit_spawned.is_connected(_unit_created):
		_world.unit_spawned.disconnect(_unit_created)
	for l: OmniLight3D in lights.values():
		if is_instance_valid(l):
			l.queue_free()
	lights.clear()
	_objects.clear()
	_world = w
	if w == null:
		return
	if not w.unit_spawned.is_connected(_unit_created):
		w.unit_spawned.connect(_unit_created)
	# The native initial/current-vars dispatch happens even for a quest
	# whose value did not change while this peer loaded or joined the zone.
	_refresh_objects()


func _unit_created(u: GameUnit) -> void:
	# World.spawn_unit finishes placement after emitting the signal.
	_refresh_created.call_deferred(u)


func _refresh_created(u: Variant) -> void:
	# A queued AddMob unit may be removed before this deferred callback.
	if is_instance_valid(u) and u is GameUnit and u.world == _world and not String(u.info.get("quest_info", "")).is_empty():
		_refresh_objects()


## The part after the second dot is OBJ_QUEST_INFO. is
## _mbscmp / strcmp, not _mbsicmp: both paths preserve the bytes' case.
func quest_changed(key: String, value: float) -> void:
	if _world == null:
		return
	var i1 := key.find(".")
	var i2 := key.find(".", i1 + 1) if i1 >= 0 else -1
	if i2 < 0:
		return
	var info := key.substr(i2 + 1)
	_refresh_objects()
	for nid: int in _objects:
		var row: Array = _objects[nid]
		if row[1] == info:
			_switch(nid, row[0], value)
			# A native notification matches only the suffix, even when its
			# zone differs. Keep the current zone's last observed GS value so
			# the snapshot scan cannot undo that notification immediately.
			row[2] = _value(info)


func _value(info: String) -> float:
	var player := game.session.my_index if not game.session.lmp.is_empty() else 0
	return game.session.state.get_var(player, "q.%s.%s" % [_world.zone.get("id", ""), info])


func _current_carrier(nid: int, obj: Variant) -> bool:
	# Looted bodies stay alive outside the scene tree for VM.WasLooted,
	# but their native world/light registration ends at removal. Also reject
	# a removed/replaced carrier before the quarter-second refresh scan.
	if not is_instance_valid(_world) or not is_instance_valid(obj) or not obj is Node3D:
		return false
	if not obj.is_inside_tree() or obj.is_queued_for_deletion():
		return false
	if obj is GameUnit:
		return obj.world == _world and _world.units.get(nid) == obj
	return _world.objects.get(nid) == obj


func _refresh_objects() -> void:
	if _world == null or game.session == null or game.session.state == null:
		return
	var carriers := _world.objects.duplicate()
	for u: GameUnit in _world.units.values():
		carriers[u.uid] = u
	for nid: int in carriers:
		var obj = carriers[nid]
		if not _current_carrier(nid, obj):
			continue
		var node: Node3D = obj
		var info := String((node as GameUnit).info.get("quest_info", "")) if node is GameUnit \
			else String(node.get_meta("ei", {}).get("quest_info", ""))
		if info.is_empty():
			continue
		# "q." + current zone id + "." + OBJ_QUEST_INFO.
		var value := _value(info)
		if not _objects.has(nid) or _objects[nid][0] != node or _objects[nid][1] != info or _objects[nid][2] != value:
			_objects[nid] = [node, info, value]
			_switch(nid, node, value)
	for nid: int in _objects.keys():
		if not _current_carrier(nid, _objects[nid][0]):
			_remove(nid)
			_objects.erase(nid)


func _switch(nid: int, node: Node3D, value: float) -> void:
	if not _current_carrier(nid, node):
		_remove(nid)
		return
	#  forwards 0 / 1 / everything else as 0 / 1 / 2.
	if value == 0.0:
		return
	if value != 1.0:
		_remove(nid)
		return
	if lights.has(nid):
		return
	var l := OmniLight3D.new()
	l.light_color = COLOR
	l.light_energy = 1.0
	l.omni_range = RADIUS
	l.omni_attenuation = 0.0
	l.shadow_enabled = false
	l.light_cull_mask |= GameUnit.OFFSCREEN_LAYER
	Gfx.mark_additive(l)
	l.add_to_group(Gfx.POINT_LIGHT_GROUP)
	game.add_child(l)
	l.global_position = node.global_position + Vector3(0, 2, 0)
	lights[nid] = l


func _remove(nid: int) -> void:
	var l = lights.get(nid)
	if is_instance_valid(l):
		l.queue_free()
	lights.erase(nid)


func _process(dt: float) -> void:
	if _world != game.world:
		on_world(game.world)
	if _world == null:
		return
	# New AddMob objects and received GS state need the initial refresh too;
	# unit creation also reaches it through the world's deferred signal.
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.25
		_refresh_objects()
	for nid: int in lights.keys():
		var obj = _objects.get(nid, [null])[0]
		var light = lights[nid]
		if not _current_carrier(nid, obj) or not is_instance_valid(light) or not light.is_inside_tree():
			_remove(nid)
			_objects.erase(nid)
			continue
		var node: Node3D = obj
		var l: OmniLight3D = light
		l.global_position = node.global_position + Vector3(0, 2, 0)


func positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for l: OmniLight3D in lights.values():
		if is_instance_valid(l):
			out.append(Vector2(l.global_position.x, -l.global_position.z))
	return out


##  turns a CUnit carrier's figure white while its quest light
## is active. OrderMarks combines this persistent reason with selection and
## temporary electrical flashes, so removing one reason retains the others.
func white_units() -> Array[GameUnit]:
	var out: Array[GameUnit] = []
	for nid: int in lights:
		var obj = _objects[nid][0]
		if _current_carrier(nid, obj) and obj is GameUnit and obj.model:
			out.append(obj)
	return out
