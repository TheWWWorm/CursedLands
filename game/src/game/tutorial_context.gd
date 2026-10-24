class_name TutorialContext
extends RefCounted
## Observes local results on either authority or client. No game commands.
## Combat relationships are replicated; the AI's host-only orders aren't used.
var _world := 0
var _previous := {}
var _opponents := {}
var _calm := 0.0
var _victory := false
var _was_combat := false
var _battle_damage := {}
var _camera := Vector3.INF
var _last_wounded := -1

func reset() -> void:
	_world = 0
	_previous.clear()
	_opponents.clear()
	_calm = 0.0
	_victory = false
	_was_combat = false
	_battle_damage.clear()
	_camera = Vector3.INF
	_last_wounded = -1

func sample(game: Game, dt: float) -> Dictionary:
	if not is_instance_valid(game.world): return {}
	if _world != game.world.get_instance_id():
		reset()
		_world = game.world.get_instance_id()
	var mine := game.my_units()
	var ids := {}
	for unit: GameUnit in mine: ids[unit.uid] = true
	var combat := false
	var acted := []
	var moved := false
	var recovered := false
	var wounded: GameUnit
	var healer: GameUnit
	var healing := ""
	var opponents := {}
	for unit: GameUnit in game.world.unit_rows():
		var target: GameUnit = game.world.units.get(unit.combat_target_id())
		if not unit.dead and is_instance_valid(target) and game.world.is_enemy(unit, target):
			if ids.has(unit.uid) or ids.has(target.uid):
				combat = true
				var enemy := target if ids.has(unit.uid) else unit
				opponents[enemy.uid] = weakref(enemy)
	if combat and not _was_combat:
		_victory = false
		_battle_damage.clear()
		_opponents = opponents
	else:
		_opponents.merge(opponents, true)
	for unit: GameUnit in mine:
		if not unit.has_meta("hero"): continue
		var old: Dictionary = _previous.get(unit.uid, {})
		if not old.is_empty():
			if unit.pos.distance_to(old.pos) > 0.2 and not unit.order_failed:
				moved = true
			if unit.gait() != old.gait: acted.append("zt13")
			if unit.aggressive != old.aggressive: acted.append("zt9")
			if unit.uid == _last_wounded and unit.hp > float(old.hp) + 0.1: recovered = true
			if unit.hp < float(old.hp) - 0.1 and (combat or _was_combat): _battle_damage[unit.uid] = true
			if unit._action_serial != old.serial and unit.action == "attack": acted.append("zt5")
		_previous[unit.uid] = {"pos":unit.pos, "hp":unit.hp, "gait":unit.gait(), "aggressive":unit.aggressive, "serial":unit._action_serial}
		if unit.hp < unit.max_hp - 0.5 and _battle_damage.has(unit.uid): wounded = unit
		if healing.is_empty() and unit == game.hud._first_selected() and not unit.cannot_cast():
			for spell: String in unit.get_meta("hero").get("spells", []):
				if spell.is_empty(): continue
				var parsed := Spells.parse(spell)
				if parsed.get("code", "") == "healing" and unit.mana >= float(parsed.mana) and Spells.usable_by(unit.get_meta("hero"), unit.max_mana, spell):
					healing = spell
					healer = unit
					break
	if moved: acted.append("zt1")
	_was_combat = combat
	for id in _opponents.keys():
		var enemy = _opponents[id].get_ref()
		if is_instance_valid(enemy) and enemy.dead:
			_victory = true
			_opponents.erase(id)
		elif not is_instance_valid(enemy): _opponents.erase(id)
	_calm = 0.0 if combat else _calm + dt
	# Camera translation can be automatic follow. Only changed orbit/zoom
	# counts, and callers suspend sampling during movies, loads and menus.
	var camera := Vector3(game.rig.yaw, game.rig.pitch, game.rig.distance)
	if _camera != Vector3.INF and camera.distance_to(_camera) > 0.02: acted.append("zt2")
	_camera = camera
	var needs_healing := wounded != null and healer != null
	_last_wounded = wounded.uid if wounded else -1
	return {"combat":combat, "acted":acted, "recovered":recovered,
		"healing_ready":_victory and _calm >= 2.5 and needs_healing,
		"needs_healing":needs_healing, "battle_damage":not _battle_damage.is_empty(), "spell":healing, "healer":healer, "wounded":wounded}
