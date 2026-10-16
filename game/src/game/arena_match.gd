class_name ArenaMatch
extends Session
## An ephemeral combat session. Deliberately bypass Session's campaign,
## network, autosave, mod attachment, worker and menu-clock lifecycle.
## Session's type lets the existing combat dispatch its local visual events.

signal changed
signal finished(winner: int)
signal visual_event(event: Dictionary)
signal world_replacing

enum Phase { DEPLOY, FIGHT, PAUSED, FINISHED }
const LIMIT := 24
const TIME_LIMIT := 300.0
const FIELD := Rect2(2.5, 2.5, 27.0, 27.0)
const TEAMS := [1, 2]

var phase := Phase.DEPLOY
var winner := -1
var formation: Array[Dictionary] = []
var catalog := ArenaCatalog.new()
var damage := [0.0, 0.0]
var _world_parent: Node
var _previous_speed := 1.0
var speed := 1.0


func _ready() -> void:
	name = "ArenaMatch"
	state = CampaignState.new()
	players = {}
	_previous_speed = Engine.time_scale
	catalog.rebuild()


func create_world(parent: Node) -> void:
	_world_parent = parent
	_rebuild_world()


func _rebuild_world() -> void:
	world_replacing.emit()
	if is_instance_valid(world):
		world.session = null
		world.get_parent().remove_child(world)
		world.queue_free()
	world = GameWorld.new()
	world.name = "ArenaWorld"
	world.zone = {"id": "arena", "type": "arena", "allod": "gipat"}
	# IDs in [1e9, 2e9) identify scripted party actors to the original AI
	# and disable their monster spells. Arena fighters use ordinary mob IDs.
	world._next_uid = 100000
	world.session = self
	_world_parent.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.ai.distant.enabled = false
	world.ai.activity.enabled = false
	var ground := _make_ground()
	world.add_child(ground)
	world.terrain = ground
	world.nav.build(ground, ground.water_base, [])
	world.set_relation(1, 2, 2)
	world.set_relation(2, 1, 2)
	world.combat_event.connect(_combat_event)
	damage = [0.0, 0.0]
	winner = -1
	phase = Phase.DEPLOY
	for placement: Dictionary in formation:
		_spawn(placement)
	changed.emit()


func bounds() -> Rect2:
	return FIELD


func _make_ground() -> EITerrain:
	var ground := EITerrain.new()
	ground.sectors_x = 1
	ground.sectors_y = 1
	ground.grid_w = 33
	ground.heights.resize(33 * 33)
	ground.heights.fill(0.0)
	ground.surface.resize(32 * 32)
	ground.surface.fill(0.0)
	ground.ground.resize(32 * 32)
	ground.ground.fill(NavGrid.FLOOR_GROUND)
	ground.water.resize(32 * 32)
	ground.water.fill(-100.0)
	ground.water_base = ground.water.duplicate()
	ground.liquid_ground.resize(32 * 32)
	ground.liquid_ground.fill(255)
	ground.water_mat.resize(32 * 32)
	ground.water_mat.fill(255)
	ground.set_process(false)
	return ground


func _spawn(placement: Dictionary) -> GameUnit:
	var p: Vector2 = placement.point
	var u := world.spawn_unit({"prototype": placement.id, "player": TEAMS[placement.team],
		"position": Vector3(p.x, p.y, 0.0)})
	if u:
		u.controller = -1
		u.mode = "aggression"
		u.facing = 0.0 if placement.team == 0 else PI
		u.display_name = String(catalog.by_id.get(placement.id, {}).get("title", RemakeText.t("Creature")))
		u.set_meta("arena_placement", placement)
		world.ai.set_post(u, bounds().get_center())
		u._sync_transform()
		world.nav.track_unit(u)
	return u


func placement_error(point: Vector2, radius := 0.8, except: GameUnit = null) -> String:
	if not is_finite(point.x) or not is_finite(point.y) or not bounds().grow(-radius).has_point(point):
		return RemakeText.t("Place creatures inside the arena boundary.")
	for u: GameUnit in world.unit_rows():
		if u == except: continue
		if point.distance_to(u.pos) < radius + u.body_radius() + 0.25:
			return RemakeText.t("Leave more space between creatures.")
	return ""


func place(id: String, team: int, point: Vector2) -> String:
	if phase != Phase.DEPLOY: return RemakeText.t("Return to deployment to change the teams.")
	if not team in [0, 1] or not catalog.by_id.has(id): return RemakeText.t("Choose a creature from the roster.")
	if team_count(team) >= LIMIT: return RemakeText.t("Each team can have up to %d creatures.") % LIMIT
	var error := placement_error(point)
	if error: return error
	var placement := {"id": id, "team": team, "point": point}
	var u := _spawn(placement)
	if u == null: return RemakeText.t("This creature's model is unavailable in the loaded game files.")
	error = placement_error(point, u.body_radius(), u)
	if error:
		world.remove_unit(u)
		return error
	formation.append(placement)
	changed.emit()
	return ""


func remove(u: GameUnit) -> void:
	if phase != Phase.DEPLOY or not is_instance_valid(u): return
	formation.erase(u.get_meta("arena_placement", {}))
	world.remove_unit(u)
	changed.emit()


func clear_team(team: int) -> void:
	if phase != Phase.DEPLOY: return
	for u: GameUnit in world.unit_rows():
		if u.faction == TEAMS[team]: remove(u)


func undo() -> void:
	if phase != Phase.DEPLOY or formation.is_empty(): return
	var last: Dictionary = formation.back()
	for u: GameUnit in world.unit_rows():
		if u.get_meta("arena_placement", {}) == last:
			remove(u)
			return


func team_count(team: int, alive_only := false) -> int:
	var count := 0
	for u: GameUnit in world.unit_rows():
		if u.faction == TEAMS[team] and (not alive_only or not u.dead): count += 1
	return count


func health_fraction(team: int) -> float:
	var total := 0.0
	var left := 0.0
	for u: GameUnit in world.unit_rows():
		if u.faction != TEAMS[team]: continue
		total += u.max_hp
		if not u.dead: left += maxf(0.0, u.hp)
	return left / maxf(1.0, total)


func start() -> bool:
	if phase != Phase.DEPLOY or team_count(0) == 0 or team_count(1) == 0: return false
	# Open combat: every fighter knows its opponents from the start. Normal
	# AI still chooses attacks, spells, targets, reachability and movement.
	for u: GameUnit in world.unit_rows():
		var noticed := {}
		for other: GameUnit in world.unit_rows():
			if world.is_enemy(u, other): noticed[other.get_instance_id()] = other
		u.set_meta("noticed", noticed)
		u.set_meta("arena_opening", true)
	phase = Phase.FIGHT
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.set_process(true)
	world.set_physics_process(true)
	Engine.time_scale = speed
	changed.emit()
	return true


func toggle_pause() -> void:
	if not phase in [Phase.FIGHT, Phase.PAUSED]: return
	phase = Phase.PAUSED if phase == Phase.FIGHT else Phase.FIGHT
	world.process_mode = Node.PROCESS_MODE_DISABLED if phase == Phase.PAUSED else Node.PROCESS_MODE_INHERIT
	changed.emit()


func set_speed(value: float) -> void:
	speed = clampf(value, 0.5, 2.0)
	Engine.time_scale = speed if phase in [Phase.FIGHT, Phase.PAUSED] else _previous_speed
	changed.emit()


func reset() -> void:
	Engine.time_scale = _previous_speed
	_rebuild_world()


func rematch() -> void:
	reset()
	start()


func _process(_dt: float) -> void:
	if phase != Phase.FIGHT or world == null: return
	var blue := team_count(0, true)
	var red := team_count(1, true)
	if blue > 0 and red > 0 and world.time < TIME_LIMIT: return
	winner = 0 if blue > 0 and red == 0 else 1 if red > 0 and blue == 0 else -1
	phase = Phase.FINISHED
	world.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = _previous_speed
	changed.emit()
	finished.emit(winner)


func _physics_process(_dt: float) -> void:
	pass # The world owns combat. There are no campaign/network ticks.


func _combat_event(kind: String, a: GameUnit, _b: GameUnit, amount: float) -> void:
	if kind == "damage" and is_instance_valid(a) and a.faction in TEAMS:
		damage[TEAMS.find(a.faction)] += maxf(0.0, amount)


func broadcast(event: Dictionary) -> void:
	if not is_instance_valid(world): return
	var kind := String(event.get("t", ""))
	if world.presentation:
		if kind == "spellfx":
			SpellFx.spawn_event(world, event)
			ParticleFx.of(world).spell_cast(event)
		elif kind == "spell_light":
			SpellFx.teleport_result(world, event)
		elif kind in ParticleFx.EVENTS:
			ParticleFx.of(world).on_event(event)
	visual_event.emit(event)


func _exit_tree() -> void:
	Engine.time_scale = _previous_speed
	if is_instance_valid(world): world.session = null
