class_name ArenaPveMatch
extends ArenaMatch
## The playable expedition and simulator share this native-combat encounter.

var run: ArenaRun
var rendered := true
var contributions := {}
var friendly_damage := {}
var previous_damage := {}
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
var _prepared_enemies := {}
var _environment_root: Node3D
var _ground: ArenaWinterTerrain
var _scenery: Array[Node3D] = []
var _environment_key: Array = []
var _navigation: NavGrid
var external_combat := false
var generation := ""
var serial := -1
var staged_preparation := false
var _queued_formation: Array[Dictionary] = []
var _queued_origins := {}
var _corpse_falls := {}
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
		_fit_figure(unit)
		unit.display_name = ArenaRules.title(placement.id, int(placement.get("family", -1)), int(placement.get("rank", 0)))
		if rendered:
			if phase == Phase.DEPLOY: _entrants[unit] = Vector2.INF
		else:
			unit.set_process(false);unit.set_physics_process(false)
			unit.model.set_process(false)
	return unit


## Native bosses can span an entire board. Keep their proportions and animated
## sockets while fitting them to a formation slot, in Trials only. This is also
## applied on the authority so reach and picking agree with the visible body.
static func _fit_figure(unit: GameUnit) -> void:
	if not unit.has_meta("arena_figure_scale"):
		var geometry := EIFigureGeometry.of(unit.model)
		if geometry.is_empty(): return
		var span: Vector3 = geometry.max - geometry.min
		var top: float = geometry.centre.z + geometry.max.z
		var factor := float(unit.info.get("arena_figure_scale", minf(1.0,minf(5.5/maxf(0.1,maxf(span.x,span.y)),3.6/maxf(0.1,top)))))
		unit.set_meta("arena_figure_scale",factor)
		unit.info["arena_figure_scale"] = factor
		unit.figure_radius*=factor; unit._radius_base*=factor; unit.figure_half_z*=factor
		if unit.move_class()!=0:
			unit._classes.clear()
			for k in [0.2,0.6,1.0]: unit._classes.append(GameUnit._class_of(unit.figure_radius,unit.figure_half_z*2.0*k))
	unit.model.fit_arena(float(unit.get_meta("arena_figure_scale")))


## Warm copied models while the UI can still draw. They are absent from the
## combat registry, navigation, picking and alliance calculations until the bell.
func prepare_opponent_models(limit := 0) -> bool:
	if not rendered or not run.arrivals_at_start() or phase != Phase.DEPLOY: return true
	if not prepare_owned_models(limit): return false
	# Empty companies do not enter native combat, so the worker sends no
	# opponents for that board. Avoid constructing figures it cannot adopt.
	if team_count(0) == 0: return true
	var prepared := 0
	for placement: Dictionary in run.enemy_formation():
		var key := str(placement)
		if _prepared_enemies.has(key): continue
		if limit > 0 and prepared >= limit: return false
		if limit > 0 and not ArenaAnimationWarmup.ready_for(placement.id): return false
		if limit > 0 and not ArenaAnimationWarmup.claim_model_frame(): return false
		var unit := GameUnit.new()
		unit.hide(); unit.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(unit)
		var point: Vector2 = placement.point
		var info := ArenaAppearance.placement_info(placement)
		info.merge({"nid":world.new_uid(), "player":TEAMS[placement.team], "position":Vector3(point.x,point.y,0)})
		if not unit.setup(world, info):
			unit.free(); continue
		# Keep the final parent while hidden and outside the unit registry.
		# Reparenting at the bell invalidates every prepared animation binding.
		if unit.model.player and unit.model.player.has_method("prepare_track_caches"):
			unit.model.player.call("prepare_track_caches")
		_prepared_enemies[key] = unit
		prepared += 1
	world.prepare_animation_bindings()
	return true


func prepare_owned_models(limit := 1) -> bool:
	if _queued_formation.is_empty(): return true
	if limit > 0 and not ArenaAnimationWarmup.ready_for(_queued_formation[0].id): return false
	# All nine boards share a render frame budget, including hidden boards.
	# Keep the normal synchronous path for native simulation and research.
	if limit > 0 and not ArenaAnimationWarmup.claim_model_frame(): return false
	for index in (mini(limit, _queued_formation.size()) if limit > 0 else _queued_formation.size()):
		var placement: Dictionary = _queued_formation.pop_front()
		var key := _placement_key(placement)
		var origin: Vector2 = _queued_origins.get(key, Vector2.INF)
		_queued_origins.erase(key)
		var unit := _spawn(placement)
		if unit:
			if world.is_visible_in_tree() and origin != placement.point:
				formation_motion.enter(unit,unit.get_meta("arena_placement").point,origin)
			_entrants.erase(unit)
	if _queued_formation.is_empty():
		ArenaAlliances.apply(world, run.army, run.enemy_army())
		changed.emit()
	return _queued_formation.is_empty()


func _create_unit(placement: Dictionary) -> GameUnit:
	var lookup := placement.duplicate(); lookup.erase("enemy_slot")
	var key := str(lookup)
	var unit: GameUnit = _prepared_enemies.get(key)
	if not is_instance_valid(unit):
		var info := ArenaAppearance.placement_info(placement)
		var point: Vector2 = placement.point
		info.merge({"player":TEAMS[placement.team], "position":Vector3(point.x,point.y,0)})
		return world.spawn_unit(info)
	_prepared_enemies.erase(key)
	unit.show(); unit.process_mode = Node.PROCESS_MODE_INHERIT
	return world.adopt_prepared_unit(unit)


func _clear_prepared_enemies() -> void:
	for unit: GameUnit in _prepared_enemies.values():
		if is_instance_valid(unit): unit.queue_free()
	_prepared_enemies.clear()


func _make_ground() -> EITerrain:
	world.zone["allod"] = "ingos"
	if not is_instance_valid(_ground):
		_ground = ArenaTerrain.create(rendered)
		_environment_root.add_child(_ground)
		_ground.arena_world = weakref(world)
		world.terrain = _ground
		_scenery = ArenaTerrain.scenery(_ground, _environment_root)
	_ground.arena_world = weakref(world)
	return _ground


func _navigation_objects() -> Array[Node3D]:
	return _scenery


func _build_navigation(ground: EITerrain) -> void:
	if _navigation and _navigation.terrain==ground:
		# All standing stamps and actor buckets belong to the retired battle.
		for unit: GameUnit in _navigation.registered_units.values():
			_navigation.untrack_unit(unit)
		_navigation._path_memo.clear();_navigation._path_memo_order.clear()
		_navigation._path_memo_ints=0
		world.nav=_navigation
	else:
		super._build_navigation(ground)
		_navigation=world.nav


func presentation_root() -> Node3D:
	return _environment_root if is_instance_valid(_environment_root) else world


func _rebuild_world() -> void:
	if staged_preparation and rendered: ArenaAnimationWarmup.claim_model_frame()
	var previous_owned := {}
	if staged_preparation and rendered and is_instance_valid(world):
		for unit: GameUnit in world.unit_rows():
			var placement: Dictionary = unit.get_meta("arena_placement",{})
			if placement.get("team",1)==0 and placement.has("run_uid"):
				previous_owned[_placement_key(placement)] = true
	external_combat = false; is_host = true; generation = ""; serial = -1
	# The courtyard is immutable across rounds. Retire only combat, actors
	# and effects; keep the board's meshes, atlas uploads and scenery alive.
	var key := [rendered, GameData.root, GameData.textures.get_instance_id(), GameData.option("gfx_hd_textures")]
	if not is_instance_valid(_environment_root) or key != _environment_key:
		if is_instance_valid(_environment_root): _environment_root.queue_free()
		_environment_root = Node3D.new()
		_environment_root.name = "ArenaCourtyard"
		_world_parent.add_child(_environment_root)
		_ground = null; _navigation=null; _scenery.clear(); _environment_key = key
	elif is_instance_valid(_ground.details) and is_instance_valid(_ground.details.soft_ground):
		_ground.details.soft_ground.clear()
	_environment_root.process_mode = Node.PROCESS_MODE_INHERIT
	var parent := _world_parent
	_world_parent = _environment_root
	_queued_formation.clear()
	_queued_origins.clear()
	var placements := formation
	if staged_preparation and rendered: formation = []
	super._rebuild_world()
	if staged_preparation and rendered:
		formation = placements
		_queued_formation.assign(formation)
		# Returning companies are already deployed. Only newly recruited units
		# need an entrance; do not path every survivor back in from the edge.
		for placement: Dictionary in formation:
			var identity := _placement_key(placement)
			if previous_owned.has(identity): _queued_origins[identity] = placement.point
	_world_parent = parent


func toggle_pause() -> void:
	super.toggle_pause()
	update_presentation_processing()
	if is_instance_valid(_environment_root):
		_environment_root.process_mode = Node.PROCESS_MODE_DISABLED if phase == Phase.PAUSED else Node.PROCESS_MODE_INHERIT


func update_presentation_processing() -> void:
	if not external_combat or not is_instance_valid(world): return
	# The worker owns hidden boards and sends their current state when scouted.
	# Advancing stale, unseen replicas wastes animation work at the shared bell.
	var stopped := phase == Phase.PAUSED or (external_combat and not world.is_visible_in_tree())
	world.process_mode = Node.PROCESS_MODE_DISABLED if stopped else Node.PROCESS_MODE_INHERIT


func _exit_tree() -> void:
	super._exit_tree()
	if is_instance_valid(_environment_root): _environment_root.queue_free()


func prepare() -> void:
	if is_instance_valid(world) and world.arena_effects:
		world.arena_effects.stop()
		world.arena_effects = null
	if _round_key.is_empty(): previous_damage.clear()
	elif phase in [Phase.FIGHT, Phase.PAUSED, Phase.FINISHED]: _remember_damage()
	if drives_clock: Engine.time_scale = 1.0
	settle_remaining = 0.0
	# Purchases may evolve or consume roster copies while their original
	# figures are still fighting. This snapshot owns this round's bonuses.
	round_army.assign(run.army.duplicate(true))
	formation.clear()
	# An eliminated company no longer fights: its board stays empty instead
	# of lining up its last army (online spectators, the board overview).
	var eliminated := run is ArenaTournamentRun and run.lives <= 0
	for entry: Dictionary in run.army:
		if entry.deployed and not eliminated:
			formation.append({"id": entry.prototype, "team": 0,
				"point": Vector2(entry.point[0], entry.point[1]), "run_uid": int(entry.uid), "rank": int(entry.rank), "family": int(entry.family), "item": String(entry.get("item", ""))})
	var enemies: Array[Dictionary] = []
	if not run.arrivals_at_start(): enemies = run.enemy_formation()
	for index in enemies.size():
		enemies[index]["enemy_slot"] = index
	formation.append_array(enemies)
	var round_key := "%d:%d:%d" % [run.run_seed, run.wave, run.lives]
	var rebuild := not is_instance_valid(world) or phase != Phase.DEPLOY or round_key != _round_key
	if rebuild:
		_clear_prepared_enemies()
		formation_motion.clear()
		_entrants.clear()
		_start_pending = false
		_rebuild_world()
	else:
		_reconcile_formation()
	world.set_meta("expedition_spell_safety", true)
	world.set_meta("arena_wave",run.wave)
	world.presentation = rendered
	world.combat.difficulty_override = 0
	world.combat.rng.seed = run.battle_seed()
	ArenaAlliances.apply(world, run.army, run.enemy_army())
	contributions.clear()
	friendly_damage.clear()
	_round_key = round_key
	for unit: GameUnit in _entrants:
		if world.is_visible_in_tree(): formation_motion.enter(unit, unit.get_meta("arena_placement").point, _entrants[unit])
	_entrants.clear()
	changed.emit()


func _placement_key(placement: Dictionary) -> String:
	if placement.has("run_uid"): return "owned:%d" % int(placement.run_uid)
	return "enemy:%d" % int(placement.get("enemy_slot", -1))


static func _same_appearance(unit: GameUnit, placement: Dictionary) -> bool:
	var appearance := ArenaAppearance.placement_info(placement)
	return ArenaAppearance.same(unit.info, appearance)


## Moving one creature must not recreate the others or restart their clips.
## Keep native IDs, figures and navigation registrations until a form changes.
func _reconcile_formation() -> void:
	_queued_formation.clear()
	_queued_origins.clear()
	var existing := {}
	for unit: GameUnit in world.unit_rows():
		existing[_placement_key(unit.get_meta("arena_placement", {}))] = unit
	for placement: Dictionary in formation:
		var key := _placement_key(placement)
		var unit: GameUnit = existing.get(key)
		existing.erase(key)
		var origin := Vector2.INF
		if is_instance_valid(unit) and not _same_appearance(unit, placement):
			origin = unit.pos
			formation_motion.forget(unit)
			world.remove_unit(unit)
			unit = null
		if not is_instance_valid(unit):
			if staged_preparation and rendered:
				_queued_formation.append(placement)
				if origin.is_finite(): _queued_origins[key] = origin
				continue
			unit = _spawn(placement)
			if rendered and unit: _entrants[unit] = origin
			continue
		var previous: Dictionary = unit.get_meta("arena_placement", {})
		unit.set_meta("arena_placement", placement)
		if rendered and world.is_visible_in_tree():
			if previous.get("point") != placement.point: formation_motion.move(unit, placement.point)
		elif unit.pos != placement.point:
			formation_motion.forget(unit)
			unit.order = {}; unit.orders.clear(); unit.path.clear(); unit._set_action("idle")
			unit.pos = placement.point
			unit._sync_transform(0.0)
			unit.reset_physics_interpolation()
			world.nav.track_unit(unit)
	for unit: GameUnit in existing.values():
		formation_motion.forget(unit)
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
		_clear_prepared_enemies()
		ArenaAlliances.apply(world, round_army, run.enemy_army())
		# The shared bell locks every home board. Preparation walk-ins must not
		# give one company extra combat time while another is still arriving.
		formation_motion.clear()
		for unit: GameUnit in world.unit_rows():
			unit.pos = unit.get_meta("arena_placement").point
			unit.resync_drawn()
			world.nav.track_unit(unit)
	if team_count(1) == 0:
		previous_damage.clear()
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
	previous_damage.clear()
	if not rendered: world.prepare_animation_bindings()
	_start_pending = false
	formation_motion.clear()
	seed(run.battle_seed())
	world.arena_rng.seed=run.battle_seed()
	world.combat.rng.seed = run.battle_seed()
	world.arena_effects = ArenaCombatEffects.new(world, round_army, run.enemy_army())
	return super.start()


func _physics_process(dt: float) -> void:
	if not rendered or phase != Phase.DEPLOY or not is_instance_valid(world): return
	if not world.is_visible_in_tree() and not formation_motion.paused:
		# Unseen walk-ins have no gameplay clock. Keep their exact destinations
		# ready for scouting instead of pathing eight hidden armies every frame.
		formation_motion.settle(world)
	else:
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
		var placement: Dictionary = a.get_meta("arena_placement",{})
		if int(placement.get("team",-1))==0 and placement.has("run_uid"):
			var uid := int(placement.run_uid)
			friendly_damage[uid] = float(friendly_damage.get(uid,0.0)) + maxf(0,amount)


func _resolved(side: int) -> void:
	if world.arena_effects: world.arena_effects.stop()
	_remember_damage()
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
			if placement.get("echo", false): continue
			survivors[int(placement.get("team", 0))] += int(placement.get("rank", 0)) + 1
	if run and not external_combat: run.resolve(side, world.time, damage, survivors)


func _remember_damage() -> void:
	previous_damage = {"army": round_army.duplicate(true), "damage": friendly_damage.duplicate()}


func damage_report(army: Array) -> Dictionary:
	if phase == Phase.DEPLOY and not previous_damage.is_empty(): return previous_damage
	return {"army": army, "damage": friendly_damage}


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
	if phase == Phase.DEPLOY and not formation_motion.paused: prepare_owned_models()
	if external_combat: _update_death_marks(dt)
	else: super._process(dt)
	if not rendered or not is_instance_valid(world) or formation_motion.paused or phase == Phase.PAUSED: return
	if phase != Phase.FINISHED:
		_update_corpse_falls(dt)
		return
	_finish_effects(dt)
	# Combat is frozen by ArenaMatch. Advance only the figure clips so the
	# final death and idle animations continue through results and camp,
	# without late hits, changed HP, or extra income.
	for unit: GameUnit in world.unit_rows():
		unit._anim_acc += dt
		unit.anim_flush()
	_update_corpse_falls(dt)
	if settle_remaining <= 0: return
	settle_remaining = maxf(0, settle_remaining - dt)
	if settle_remaining == 0: presentation_finished.emit()


## Horror's authored cdeath is a hovering cycle, without a descent track.
## Supply the fall in Trials presentation, including after the combat clock
## stops. Navigation, unit positions and the authority's combat stay untouched.
func _update_corpse_falls(dt: float) -> void:
	var present := {}
	for unit: GameUnit in world.unit_rows():
		if not is_instance_valid(unit.model): continue
		var key := unit.get_instance_id()
		if not unit.dead or unit.model.template != "unmocu":
			if _corpse_falls.has(key):
				if _corpse_falls[key].model.get_ref() == unit.model:
					unit.model.position.y = float(_corpse_falls[key].base)
				_corpse_falls.erase(key)
			continue
		present[key] = true
		if not _corpse_falls.has(key) or _corpse_falls[key].model.get_ref() != unit.model:
			_corpse_falls[key] = {"model":weakref(unit.model),"base":unit.model.position.y,
				"age":0.0,"drop":0.0,"landed":false}
		var fall: Dictionary = _corpse_falls[key]
		if fall.landed: continue
		fall.age += maxf(0,dt)
		var drop := 4.9 * float(fall.age) * float(fall.age)
		# A corpse received by scouting/late join is already in its last pose.
		# Fit that pose to the snow immediately instead of replaying the fall.
		var clearance := _corpse_clearance(unit)
		if unit.is_frozen() or drop >= clearance + float(fall.drop):
			unit.freeze_pose(true)
			fall.drop = float(fall.drop) + _corpse_clearance(unit)
			fall.landed = true
		else:
			fall.drop = drop
		unit.model.position.y = float(fall.base) - float(fall.drop)
	for key in _corpse_falls.keys():
		if not present.has(key): _corpse_falls.erase(key)


## Exact rigid mesh vertices avoid leaving wing/foot bounding-box padding
## between the corpse and the floor. Horror has no vertex-morph meshes.
static func _corpse_clearance(unit: GameUnit) -> float:
	unit.model.flush_pending_pose()
	var bottom := INF
	var inverse := unit.global_transform.affine_inverse()
	for mesh: MeshInstance3D in unit.model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null or not mesh.visible: continue
		var transform := inverse * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices: bottom = minf(bottom,(transform * vertex).y)
	return bottom if is_finite(bottom) else 0.0


## Fixed-step native combat for research, including projectiles and world spell
## timers. Call once per 55 ms simulated tick, with automatic processing disabled.
func simulate_tick() -> void:
	if phase != Phase.FIGHT: return
	world.set_process(false)
	world.set_physics_process(false)
	world._advance(GameUnit.TICK)
	for u: GameUnit in world.unit_rows():
		if not rendered:
			u._game_clock=world.time
			u._process(GameUnit.TICK)
			u.model._process(GameUnit.TICK)
		u._sync_transform(0.0)
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


func apply_board(data: Dictionary) -> void:
	if String(data.generation) == generation and int(data.serial) <= serial: return
	if not data.full and (String(data.generation) != generation or int(data.serial) <= serial): return
	if not is_instance_valid(world): prepare()
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
			if unit and not ArenaAppearance.same(unit.info, record):
				formation_motion.forget(unit)
				world.remove_unit(unit); unit = null
			var created := unit == null
			if created: unit = _spawn_record(record)
			elif record.has("snap") and (not deploying or not same_board): unit.apply_snapshot(record.snap, true, PackedFloat64Array(), float(data.time))
			if unit:
				_fit_figure(unit)
				restore_body(unit, record.online_body)
				unit.set_meta("arena_placement", record.placement)
				unit.display_name = RemakeText.t("Spirit echo") if record.placement.get("echo", false) else ArenaRules.title(record.prototype, int(record.placement.get("family", -1)), int(record.placement.get("rank", 0)))
				unit.stats = record.runtime_stats.duplicate(true)
				keep[uid] = true
				if deploying and rendered:
					var target: Vector2 = record.placement.get("point", unit.pos)
					if created: formation_motion.enter(unit, target, origin)
					elif previous_point != target: formation_motion.move(unit, target)
		for unit: GameUnit in world.unit_rows():
			if not keep.has(unit.uid):
				formation_motion.forget(unit)
				world.remove_unit(unit)
		round_army.assign(data.army.duplicate(true))
	elif not deploying:
		# Preparation destinations arrive in full formation records. Reapplying
		# stationary authority poses here would interrupt the local run-in.
		var snapshots := NetSnapshot.unpack(data.snaps)
		_apply_snap(snapshots, float(data.time), int(data.serial),true)
	serial = int(data.serial)
	world.time = float(data.time)
	if data.full: ArenaItemFx.sync_shields(world, data.get("item_shields", []))
	damage = data.damage.duplicate()
	friendly_damage.clear()
	for row: Array in data.get("friendly_damage",[]):
		if row.size()==2: friendly_damage[int(row[0])] = maxf(0.0,float(row[1]))
	var previous := phase
	phase = int(data.phase) as Phase
	if phase == Phase.DEPLOY:
		if not data.get("previous_damage", {}).is_empty(): previous_damage = data.previous_damage.duplicate(true)
	else:
		previous_damage.clear()
	# A worker snapshot already in flight must not undo a local pause.
	# Online matches never set external_combat and keep server-owned phases.
	if external_combat and previous == Phase.PAUSED and phase == Phase.FIGHT:
		phase = Phase.PAUSED
	winner = int(data.winner)
	world.authority = false
	if world.arena_effects:
		world.arena_effects.stop()
		world.arena_effects = null
	world.process_mode = Node.PROCESS_MODE_DISABLED if phase == Phase.PAUSED else Node.PROCESS_MODE_INHERIT
	update_presentation_processing()
	world.set_process(true); world.set_physics_process(true)
	if phase == Phase.FINISHED:
		_stop_locomotion()
		if previous != Phase.FINISHED: finished.emit(winner)
	if phase != previous or data.full: changed.emit()

func apply_effects(data: Dictionary) -> void:
	if String(data.generation) != generation or not is_instance_valid(world): return
	for event: Dictionary in data.events:
		# Only visual/combat events are accepted, never campaign state or scripts.
		if String(event.get("t", "")) not in ["arena_proc", "arrow", "direct_arrow", "spellfx", "spell_light", "hitnum", "blood", "sound", "unit_sound"] + Array(ParticleFx.EVENTS): continue
		_on_event(event)
		visual_event.emit(event)

static func restore_body(unit: GameUnit, body: PackedFloat64Array) -> void:
	if body.size() != unit.parts.size() + 1: return
	unit._set_max_hp(body[0])
	for index in unit.parts.size(): unit.parts[index].cur = body[index + 1]


## The private combat worker has fresh IDs. Reuse the already-warmed figures
## by formation identity before accepting its first snapshot; no model rebuild
## is needed at the bell. Remove every old ID before installing any new ID.
func adopt_replica_formation(data: Dictionary) -> void:
	var available := {}
	for unit: GameUnit in world.unit_rows():
		var placement: Dictionary=unit.get_meta("arena_placement",{})
		available[_replica_key(placement)]=unit
	for record: Dictionary in data.records:
		var key := _replica_key(record.placement)
		if not available.has(key):
			var unit := _spawn(record.placement)
			if unit: available[key]=unit
	for unit: GameUnit in available.values():
		world.nav.untrack_unit(unit);world.erase_unit(unit.uid)
	for record: Dictionary in data.records:
		var key := _replica_key(record.placement)
		var unit: GameUnit=available.get(key)
		if unit:
			available.erase(key);unit.uid=int(record.nid)
			world.set_unit(unit.uid,unit);world.nav.track_unit(unit)
	for unit: GameUnit in available.values(): unit.queue_free()
	formation_motion.clear();_entrants.clear()
	_clear_prepared_enemies()
	external_combat=true;is_host=false;world.authority=false


static func _replica_key(placement: Dictionary) -> String:
	return str([placement.get("team",0),placement.get("id",""),placement.get("point",Vector2.ZERO),placement.get("family",-1),placement.get("rank",0)])
