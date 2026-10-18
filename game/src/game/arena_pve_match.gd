class_name ArenaPveMatch
extends ArenaMatch
## The playable expedition and simulator share this native-combat encounter.

var run: ArenaRun
var rendered := true
var contributions := {}
var selected_run_uid := 0
var settle_remaining := 0.0
var round_army: Array[Dictionary] = []
var formation_motion := ArenaFormationMotion.new()
var _entrants := {}
var _round_key := ""
var _start_pending := false
var _arrival_left := 0.0
var _effects_left := 0.0
var _light_finish_age := {}
var _waiting: Node3D
var _prepared_enemies := {}
signal presentation_finished


func _ready() -> void:
	super._ready()
	# Trials use the remake's shared 80% absorption cap: strong armor remains
	# useful, while low-damage attacks and spells can still make progress.
	mod_config = {"rules": {"armor_formula": 1, "free_run": 0, "stamina_regen": 0}, "values": {}}
	finished.connect(_resolved)


func bounds() -> Rect2:
	return ArenaTerrain.PLAY_AREA


func stalemate_seconds() -> float:
	return 10.0


func time_limit() -> float:
	return ArenaRules.BATTLE_SECONDS


func _spawn(placement: Dictionary) -> GameUnit:
	var unit := super._spawn(placement)
	if unit:
		unit.display_name = ArenaRules.title(placement.id)
		if rendered: _entrants[unit] = Vector2.INF
	return unit


## Warm copied models while the UI can still draw. They are absent from the
## combat registry, navigation, picking and alliance calculations until the bell.
func prepare_opponent_models() -> void:
	if not rendered or not run.arrivals_at_start() or phase != Phase.DEPLOY: return
	if not is_instance_valid(_waiting):
		_waiting = Node3D.new(); _waiting.hide()
		_waiting.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(_waiting)
	for placement: Dictionary in run.enemy_formation():
		var key := str(placement)
		if _prepared_enemies.has(key): continue
		var unit := GameUnit.new()
		var point: Vector2 = placement.point
		if not unit.setup(world, {"nid":world.new_uid(), "prototype":placement.id,
				"player":TEAMS[placement.team], "position":Vector3(point.x,point.y,0)}):
			unit.free(); continue
		_waiting.add_child(unit)
		if unit.model.player and unit.model.player.has_method("prepare_track_caches"):
			unit.model.player.call("prepare_track_caches")
		_prepared_enemies[key] = unit
	world.prepare_animation_bindings()


func _create_unit(placement: Dictionary) -> GameUnit:
	var lookup := placement.duplicate(); lookup.erase("enemy_slot")
	var key := str(lookup)
	var unit: GameUnit = _prepared_enemies.get(key)
	if not is_instance_valid(unit): return super._create_unit(placement)
	_prepared_enemies.erase(key)
	_waiting.remove_child(unit)
	return world.adopt_prepared_unit(unit)


func _make_ground() -> EITerrain:
	world.zone["allod"] = "ingos"
	return ArenaTerrain.create(rendered)


func prepare() -> void:
	settle_remaining = 0.0
	# Purchases may evolve or consume roster copies while their original
	# figures are still fighting. This snapshot owns this round's bonuses.
	round_army.assign(run.army.duplicate(true))
	formation.clear()
	for entry: Dictionary in run.army:
		if entry.deployed:
			formation.append({"id": entry.prototype, "team": 0,
				"point": Vector2(entry.point[0], entry.point[1]), "run_uid": int(entry.uid), "rank": int(entry.rank)})
	var enemies: Array[Dictionary] = []
	if not run.arrivals_at_start(): enemies = run.enemy_formation()
	for index in enemies.size():
		enemies[index]["enemy_slot"] = index
	formation.append_array(enemies)
	var round_key := "%d:%d:%d" % [run.run_seed, run.wave, run.lives]
	var rebuild := not is_instance_valid(world) or phase != Phase.DEPLOY or round_key != _round_key
	if rebuild:
		_prepared_enemies.clear(); _waiting = null
		formation_motion.clear()
		_entrants.clear()
		_start_pending = false
		_rebuild_world()
	else:
		_reconcile_formation()
	world.set_meta("expedition_spell_safety", true)
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
	if run == null or not is_instance_valid(world) or phase != Phase.DEPLOY or team_count(0) == 0: return false
	if not run.start_battle().is_empty(): return false
	if run.arrivals_at_start():
		var enemies := run.enemy_formation()
		for index in enemies.size():
			var placement: Dictionary = enemies[index]
			placement["enemy_slot"] = index
			formation.append(placement)
			var incoming := _spawn(placement)
			_entrants.erase(incoming)
			if rendered and incoming:
				SpellFx.spawn(world, incoming.pos, "teleport", 2, 0.6, {"red":0.35, "green":0.65, "blue":1.0, "light_radius":2.5})
		if is_instance_valid(_waiting): _waiting.queue_free()
		_waiting = null; _prepared_enemies.clear()
		ArenaAlliances.apply(world, round_army, run.enemy_army())
		# The shared bell locks every home board. Preparation walk-ins must not
		# give one company extra combat time while another is still arriving.
		formation_motion.clear()
		for unit: GameUnit in world.unit_rows():
			unit.pos = unit.get_meta("arena_placement").point
			unit.resync_drawn()
			world.nav.track_unit(unit)
	if team_count(1) == 0:
		winner = 0; phase = Phase.FINISHED
		changed.emit(); finished.emit(winner)
		return true
	if not formation_motion.movers.is_empty():
		_start_pending = true
		_arrival_left = 2.0
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
	if _start_pending and not formation_motion.paused:
		_arrival_left -= dt / maxf(Engine.time_scale, 0.001)
		if _arrival_left <= 0: formation_motion.settle(world)
		if formation_motion.movers.is_empty(): _start_combat()


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
	_stop_locomotion()
	settle_remaining = 1.6 if rendered else 0.0
	if rendered:
		_effects_left = 1.5
		_light_finish_age.clear()
		for node in world.get_children():
			if node is ParticleFx: node.finish_emitters()
			elif node is Projectile: node.apply_hit = false
			elif node is SpellFx: _light_finish_age[node] = node._age
	var survivors := [0, 0]
	for unit: GameUnit in world.unit_rows():
		if not unit.dead:
			var placement: Dictionary = unit.get_meta("arena_placement", {})
			survivors[int(placement.get("team", 0))] += int(placement.get("rank", 0)) + 1
	if run: run.resolve(side, world.time, damage, survivors)


## Authority and replicas must agree on the final stationary pose. A stopped
## combat clock cannot clear movement on its next tick, and late snapshots
## must not restart a survivor's walking clip while waiting for other boards.
func _stop_locomotion() -> void:
	formation_motion.clear()
	for unit: GameUnit in world.unit_rows():
		unit.order = {}; unit.orders.clear(); unit.path.clear()
		unit._moving = false; unit._move_speed = 0.0
		unit._draw_motion_active = false; unit._draw_line_goal = Vector2.INF
		unit.net_view.got(unit.pos, true, unit.facing)
		unit.resync_drawn()
		if not unit.dead: unit._set_action("idle")


func _process(dt: float) -> void:
	super._process(dt)
	if not rendered or phase != Phase.FINISHED or not is_instance_valid(world) or formation_motion.paused: return
	_finish_effects(dt)
	# Combat is frozen by ArenaMatch. Advance only the figure clips so the
	# final death and idle animations continue through results and camp,
	# without late hits, changed HP, or extra income.
	for unit: GameUnit in world.unit_rows():
		unit._anim_acc += dt
		unit.anim_flush()
	if settle_remaining <= 0: return
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


func _finish_effects(dt: float) -> void:
	if _effects_left <= 0: return
	_effects_left = maxf(0.0, _effects_left - dt)
	for node in world.get_children():
		if node.is_queued_for_deletion(): continue
		if node is ParticleFx or node is Projectile or node is SpellFx:
			if _effects_left <= 0:
				node.queue_free()
			elif node is ParticleFx: node._process(dt)
			elif node is Projectile: node._tick(dt)
			elif node is SpellFx:
				node.advance(int(_light_finish_age.get(node, node._age)) + floori((1.5 - _effects_left) / GameUnit.TICK))
	if _effects_left <= 0: _light_finish_age.clear()
