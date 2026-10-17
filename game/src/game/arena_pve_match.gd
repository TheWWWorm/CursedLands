class_name ArenaPveMatch
extends ArenaMatch
## The playable expedition and simulator share this native-combat encounter.

var run: ArenaRun
var rendered := true
var contributions := {}
var selected_run_uid := 0
var settle_remaining := 0.0
var formation_motion := ArenaFormationMotion.new()
var _entrants := {}
var _round_key := ""
var _start_pending := false
signal presentation_finished


func _ready() -> void:
	super._ready()
	mod_config = {"rules": {"armor_formula": 0, "free_run": 0, "stamina_regen": 0}, "values": {}}
	finished.connect(_resolved)


func bounds() -> Rect2:
	return Rect2(18.5, 18.5, 27, 27)


func _spawn(placement: Dictionary) -> GameUnit:
	var unit := super._spawn(placement)
	if unit:
		unit.display_name = ArenaRules.title(placement.id)
		if rendered: _entrants[unit] = Vector2.INF
	return unit


func _make_ground() -> EITerrain:
	world.zone["allod"] = "ingos"
	return ArenaTerrain.create(rendered)


func prepare() -> void:
	settle_remaining = 0.0
	formation.clear()
	for entry: Dictionary in run.army:
		if entry.deployed:
			formation.append({"id": entry.prototype, "team": 0,
				"point": Vector2(entry.point[0], entry.point[1]), "run_uid": int(entry.uid), "rank": int(entry.rank)})
	var enemies := run.enemy_formation()
	for index in enemies.size():
		enemies[index]["enemy_slot"] = index
	formation.append_array(enemies)
	var round_key := "%d:%d:%d" % [run.run_seed, run.wave, run.lives]
	var rebuild := not is_instance_valid(world) or phase != Phase.DEPLOY or round_key != _round_key
	if rebuild:
		formation_motion.clear()
		_entrants.clear()
		_start_pending = false
		_rebuild_world()
	else:
		_reconcile_formation()
	world.presentation = rendered
	world.combat.difficulty_override = 0
	world.combat.rng.seed = run.battle_seed()
	ArenaAlliances.apply(world, run.army, run.enemy_army())
	contributions.clear()
	# Scenery geometry participates in both rendered and headless navigation.
	if rebuild:
		var objects := ArenaTerrain.scenery(world.terrain, world)
		world.nav.build(world.terrain, world.terrain.water_base, objects)
		for u: GameUnit in world.unit_rows(): world.nav.track_unit(u)
	_round_key = round_key
	for unit: GameUnit in _entrants:
		formation_motion.enter(unit, unit.get_meta("arena_placement").point, _entrants[unit])
	_entrants.clear()
	changed.emit()


func _placement_key(placement: Dictionary) -> String:
	if placement.has("run_uid"): return "owned:%d" % int(placement.run_uid)
	return "enemy:%d" % int(placement.get("enemy_slot", -1))


## Moving one creature must not recreate the others or restart their clips.
## Keep native IDs, figures and navigation registrations until a form changes.
func _reconcile_formation() -> void:
	var existing := {}
	for unit: GameUnit in world.unit_rows():
		existing[_placement_key(unit.get_meta("arena_placement", {}))] = unit
	for placement: Dictionary in formation:
		var key := _placement_key(placement)
		var unit: GameUnit = existing.get(key)
		existing.erase(key)
		var origin := Vector2.INF
		if is_instance_valid(unit) and unit.info.prototype != placement.id:
			origin = unit.pos
			formation_motion.movers.erase(unit)
			world.remove_unit(unit)
			unit = null
		if not is_instance_valid(unit):
			unit = _spawn(placement)
			if rendered and unit: _entrants[unit] = origin
			continue
		var previous: Dictionary = unit.get_meta("arena_placement", {})
		unit.set_meta("arena_placement", placement)
		if rendered:
			if previous.get("point") != placement.point: formation_motion.move(unit, placement.point)
		elif unit.pos != placement.point:
			unit.pos = placement.point
			unit._sync_transform(0.0)
			unit.reset_physics_interpolation()
			world.nav.track_unit(unit)
	for unit: GameUnit in existing.values():
		formation_motion.movers.erase(unit)
		world.remove_unit(unit)


func recruitment_clear(point: Vector2) -> bool:
	return is_instance_valid(world) and placement_error(point, 0.8, null, false).is_empty()


func placement_error(point: Vector2, radius := 0.8, except: GameUnit = null, use_selection := true) -> String:
	if not ArenaRun.DEPLOY.has_point(point): return RemakeText.t("Deploy inside the blue half of the battlefield.")
	if except == null and use_selection and is_instance_valid(world):
		for u: GameUnit in world.unit_rows():
			if int(u.get_meta("arena_placement", {}).get("run_uid", 0)) == selected_run_uid and selected_run_uid > 0:
				except = u
	if not bounds().grow(-radius).has_point(point): return RemakeText.t("Place creatures inside the arena boundary.")
	for unit: GameUnit in world.unit_rows():
		if unit == except: continue
		# Reserve destinations, not the temporary positions along a run-in.
		var target: Vector2 = unit.get_meta("arena_placement", {}).get("point", unit.pos)
		if point.distance_to(target) < radius + unit.body_radius() + 0.25:
			return RemakeText.t("Leave more space between creatures.")
	var movement_class := except.move_class() if except else NavGrid.WALK_CLASS
	if not world.nav.cell_open(point, movement_class): return RemakeText.t("Choose clear ground for this creature.")
	if except:
		var ignored: Array = [except]
		for unit in formation_motion.movers:
			if is_instance_valid(unit) and unit != except: ignored.append(unit)
		var path := world.nav.find_path(except.pos, point, ignored, [], 0.0, movement_class)
		if path.is_empty() or path[-1].distance_to(point) > 0.3:
			return RemakeText.t("Choose clear ground for this creature.")
	return ""


func start() -> bool:
	if run == null or not is_instance_valid(world) or phase != Phase.DEPLOY or team_count(0) == 0 or team_count(1) == 0: return false
	if not run.start_battle().is_empty(): return false
	if not formation_motion.movers.is_empty():
		_start_pending = true
		changed.emit()
		return true
	return _start_combat()


func _start_combat() -> bool:
	_start_pending = false
	formation_motion.clear()
	seed(run.battle_seed())
	world.combat.rng.seed = run.battle_seed()
	return super.start()


func _physics_process(dt: float) -> void:
	if not rendered or phase != Phase.DEPLOY or not is_instance_valid(world): return
	formation_motion.advance(dt / maxf(Engine.time_scale, 0.001), world)
	if _start_pending and formation_motion.movers.is_empty() and not formation_motion.paused:
		_start_combat()


func expire_preparation() -> void:
	if run == null or run.stage != "prepare" or run.preparation_left > 0: return
	# A purchased company should not lose because its first deployment was missed.
	if run.deployed_count() == 0 and not run.army.is_empty():
		run.arrange()
		prepare()
	if team_count(0) > 0:
		start()
	elif run.start_battle(true).is_empty():
		winner = 1
		phase = Phase.FINISHED
		world.process_mode = Node.PROCESS_MODE_DISABLED
		changed.emit()
		finished.emit(winner)


func _combat_event(kind: String, a: GameUnit, b: GameUnit, amount: float) -> void:
	super._combat_event(kind, a, b, amount)
	if kind == "damage" and is_instance_valid(a):
		contributions[a.uid] = float(contributions.get(a.uid, 0.0)) + maxf(0, amount)


func _resolved(side: int) -> void:
	settle_remaining = 1.6 if rendered else 0.0
	if rendered:
		for unit: GameUnit in world.unit_rows():
			if not unit.dead: unit._set_action("idle")
	var survivors := [0, 0]
	for unit: GameUnit in world.unit_rows():
		if not unit.dead:
			var placement: Dictionary = unit.get_meta("arena_placement", {})
			survivors[int(placement.get("team", 0))] += int(placement.get("rank", 0)) + 1
	if run: run.resolve(side, world.time, damage, survivors)


func _process(dt: float) -> void:
	super._process(dt)
	if settle_remaining <= 0: return
	# Combat is frozen by ArenaMatch. Advance only the figure clips so the
	# final death can finish, without late hits, changed HP, or extra income.
	for unit: GameUnit in world.unit_rows():
		unit._anim_acc += dt
		unit.anim_flush()
	settle_remaining = maxf(0, settle_remaining - dt)
	if settle_remaining == 0: presentation_finished.emit()


## Fixed-step native combat for research, including projectiles and world spell
## timers. Call once per 55 ms simulated tick, with automatic processing disabled.
func simulate_tick() -> void:
	if phase != Phase.FIGHT: return
	world.set_process(false)
	world.set_physics_process(false)
	world._advance(GameUnit.TICK)
	for u: GameUnit in world.unit_rows(): u._sync_transform(0.0)
	for node in world.get_children():
		if node is Projectile and not node.is_queued_for_deletion():
			node.set_physics_process(false)
			node._tick(GameUnit.TICK)
	_process(0)


func presents_world() -> bool:
	return rendered
