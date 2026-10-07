class_name GameWorld
extends Node3D
## One loaded zone during play: terrain, static objects, units, navigation,
## AI, combat and the level script. The host runs the simulation; clients
## mirror it from snapshots (see Session).

signal unit_spawned(u: GameUnit)
signal unit_died(u: GameUnit, killer: GameUnit)
signal combat_event(kind: String, a: GameUnit, b: GameUnit, amount: float)
## Host: an equipped item wore past critical or broke (Combat._wear).
signal item_worn(u: GameUnit, item: String, kind: String)

const TICK := GameUnit.TICK
const CorpsePools = preload("res://src/game/corpse_pools.gd")
## Godot4.7 Node's suspend notifications are not bound as script constants.
## The engine enum sends these two values through _notification nonetheless.
const _ENGINE_SUSPENDED := 9003
const _ENGINE_UNSUSPENDED := 9004

var zone := {}
var map: EIMapScene
var terrain: EITerrain
var ground_marks: GroundMarks
var mob: EIMob
var nav := NavGrid.new():
	set(value):
		nav = value
		if nav:
			nav.registry_world = self
var combat: Combat
var ai: UnitAI
var corpse_pools: CorpsePools
var vm: ScriptVM
const EMPTY_UNITS: Dictionary = {}
const EMPTY_ROWS: Array = []
var _units: Dictionary = EMPTY_UNITS
var _unit_rows: Array = EMPTY_ROWS
var units_revision := 0
## Membership and order change only through set_unit/erase_unit or replacement.
## Readers retain an immutable snapshot, so a query never rescans the registry
## to discover same-count replacement or erase/reinsert. Unit fields stay live.
var units: Dictionary:
	get: return _units
	set(value):
		_units = value.duplicate()
		_units.make_read_only()
		_unit_rows = _units.values()
		_unit_rows.make_read_only()
		units_revision += 1
		if ai: ai.activity.invalidate()
var _party_registry_revision := -1
var _party_structure_revision := -1
var _party_revision := -1
var _party_units: Array[GameUnit] = []
## Looted corpses taken off the world (Session.take_loot): uid -> GameUnit,
## out of the tree. the original's drops the object from the server
## but the script variables that hold it keep it, and WasLooted (builtin
## 0xe3) still reads its looted flag; the VM finds them here (and by uid
## after a save, CampaignState "looted").
var looted := {}
var objects := {}        # nid -> Node3D (placed map objects)
var objects_revision := 0   # creation/replacement; removals also validate live registration
var levers := {}         # nid -> {state, states, cycled, door}
var lever_sys: LeverSystem
## .mob MAGIC_TRAP objects (the original CMagicTrapObject), run by the host.
var traps: MagicTraps
## "#weather tornado" zones' tornadoes (host, made on the first tick).
var tornadoes: Tornadoes
var _trap_t := 0.0
var diplomacy := PackedInt32Array()
var time := 0.0
##  accumulates elapsed time and dispatches the entire server
## world once per55ms. Its clock cap is five logic ticks per incoming frame.
## The remainder belongs to this world, including a retained LMP world.
var _logic_accumulator := 0.0
var _logic_step := 0
## A separate simulation process can repay a transient stall without blocking
## the owner's renderer. Keep the same five-tick callback budget, retaining
## the excess outside the fractional presentation clock. Inline worlds keep
## the original cap; paused/loading intervals are excluded by _sample_frame.
var retain_logic_debt := false
var _logic_debt := 0.0
## Godot4.7 discards time beyond max_physics_steps_per_frame from both its
## physics and frame deltas (Main::iteration). Native456440 instead reads
## timeGetTime once per rendered loop, capped at five55/27ms intervals.
## Fixed-FPS tools deliberately retain Godot's deterministic supplied clock:
## isolated.sh forwards the consumed engine flag; direct callers can use
## -- --ei-fixed-step (also implied by Godot's Movie Maker mode).
var _fixed_step := int(OS.get_environment("EI_FIXED_FPS")) > 0 \
	or OS.get_cmdline_user_args().has("--ei-fixed-step") or not Engine.get_write_movie_path().is_empty()
var _frame_ms := -1
## The original has a separate client55ms accumulator (456440,79bc58).
## Only effect presentation advances here; received server time, movement,
## commands, stats and authoritative expiration stay under their old owner.
var _client_effect_accumulator := 0.0
var _client_effect_step := 0
var _client_effect_frame_ms := -1
var _client_placement: Object
## Conversation actors still walking or turning to their spot.
var dialog_movers := {}   # GameUnit -> {to, angle, state, elapsed}
## Unit ids of the running conversation's actors a / b / c (Briefings.cast).
var dialog_actors := {}
## Simulation workers retain animation clocks and queried geometry, but have
## no local particles, HUD, wounds or scene presentation.
var presentation := true
var authority := true
var session: Session
## SetWaterLevel state, the original's list at server (adds
##  ticks): map material -> [ticks left, offset, offset per tick].
var water_levels := {}
var _water_t := 0.0
var _next_uid := 1_500_000_000
var _seq_n := 0   # GameUnit._seq of the last unit put in `units`
## Optional diagnostic timings; inclusive child categories identify CPU
## costs without changing simulation order or the server's55ms cadence.
var profile_simulation := false
var profile_us := {}
var profile_counts := {}
var profile_slow: Array[Dictionary] = []


func profile_record(part: String,started: int,uid := -1) -> void:
	if not profile_simulation: return
	var elapsed := Time.get_ticks_usec()-started
	profile_us[part] = int(profile_us.get(part,0))+elapsed
	profile_counts[part] = int(profile_counts.get(part,0))+1
	if elapsed >= 5000:
		profile_slow.append({"part":part,"uid":uid,"us":elapsed})
		if profile_slow.size() > 32: profile_slow.pop_front()


func _init() -> void:
	nav.registry_world = self
	combat = Combat.new(self)
	ai = UnitAI.new(self)
	corpse_pools = CorpsePools.new(self)
	traps = MagicTraps.new(self)


func _ready() -> void:
	# Physics used to finish the world before any frame/camera/UI callback.
	# Keep that order with native frame delivery and preserve caller overrides.
	if not _fixed_step and process_priority == 0:
		process_priority = -2
	if ClassDB.class_exists("UnitPresentationKernel") and not OS.get_cmdline_user_args().has("--ei-script-presentation"):
		_client_placement = ClassDB.instantiate("UnitPresentationKernel")


## Stable registry order, held until the next explicit membership change.
func unit_rows() -> Array:
	return _unit_rows


## Binding every clip on the first movement tick can stall a crowded map.
## Resolve the fixed rig once under the loading screen. This engine operation
## changes neither playback clocks nor poses and emits no animation events.
func prepare_animation_bindings() -> void:
	if not ClassDB.class_has_method("AnimationPlayer", "prepare_track_caches") \
			or OS.get_cmdline_user_args().has("--ei-lazy-animation-bindings"):
		return
	for u: GameUnit in _unit_rows:
		if is_instance_valid(u) and u.model and u.model.player:
			u.model.player.call("prepare_track_caches")
			NetStatus.keep_alive()


## Registry-only adapters. Spawning/removal also manage navigation and nodes.
func set_unit(id: int, u: GameUnit) -> void:
	if _units.get(id) == u and _units.has(id): return
	var next := _units.duplicate()
	next[id] = u
	units = next


func erase_unit(id: int) -> void:
	if not _units.has(id): return
	var next := _units.duplicate()
	next.erase(id)
	units = next


## Read-only party membership in registry order. Callers still read current
## health, visibility and positions; ownership and freed nodes invalidate it.
func party_units() -> Array[GameUnit]:
	if _party_registry_revision != units_revision or _party_revision != GameUnit.notice_revision \
			or _party_structure_revision != GameUnit.structure_revision:
		_party_registry_revision = units_revision
		_party_structure_revision = GameUnit.structure_revision
		_party_revision = GameUnit.notice_revision
		var selected: Array[GameUnit] = []
		for u in _unit_rows:
			if is_instance_valid(u) and u is GameUnit and u.controller >= 0:
				selected.append(u)
		selected.make_read_only()
		_party_units = selected
	return _party_units


func _register_object(node: Node3D) -> void:
	var o: Dictionary = node.get_meta("ei")
	objects[int(o.get("nid", 0))] = node
	objects_revision += 1
	if o.kind == "LEVER":
		levers[int(o.nid)] = {"state": int(o.get("lever_state", 0)), "states": maxi(1, int(o.get("lever_states", 2))),
			"cycled": int(o.get("lever_cycled", 0)), "door": int(o.get("lever_door", 0)), "enabled": true,
			"science": Array(o.get("lever_science", PackedInt32Array([1, 0, 0])))}
	elif o.kind == "MAGIC_TRAP":
		traps.add(o)
	# Walkable parts are authored BASE figures, classified by NavGrid.
	# Parent names miss LiA's lifts (whose parent is a chest) and retain
	# stale mesh heights after movement, morphing or removal.


## A map object's radius (the original object, computed when
## the figure is built or a lever changes state): the half
## diagonal of the box round all its parts (part offset + part box) about
## the box centre; the object's returns it (CLeverObject
## ). Navigation keeps the authored FIG boxes at the lever's
## target state; a render mesh's box includes other morph states too.
func object_radius(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	var nid := int(node.get_meta("ei", {}).get("nid", 0))
	var radius := nav.object_radius(nid)
	if not is_nan(radius):
		return radius
	var geometry := EIFigureGeometry.of(node)
	if not geometry.is_empty():
		return float(geometry.radius)
	# Procedural remake objects may have no authored figure.
	var box := AABB()
	var first := true
	var inv := node.global_transform.affine_inverse()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := (inv * m.global_transform) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return 0.0 if first else box.size.length() * 0.5


## Places the non-unit objects of an extra .mob (quest maps, AddMob) into the
## running zone. Runs on every peer; units are replicated separately.
func add_mob_objects(file: String) -> void:
	var extra := EIMob.load_bytes(GameData.read_file("maps/" + file))
	if extra == null or map == null:
		return
	var root: Node3D = map.get_node_or_null("Objects")
	for o: Dictionary in extra.objects:
		var nid := int(o.get("nid", 0))
		if o.kind == "UNIT" or String(o.get("template", "")).is_empty() or objects.has(nid):
			continue
		var node := map.place_object(o, root if root else map)
		if node == null:
			node = _trap_marker(o, root if root else map)
		if node == null:
			continue
		_register_object(node)
		nav.add_object(node)
		if lever_sys and levers.has(nid):
			lever_sys.add(nid)


## Script SetCP / SetCPFast on a map object (builtins 0x8e / 0xad →
## ): the object is put at (x, y, z) and re-linked in the world
## grid. z as the .mob's (above the ground, as the placement above).
func move_object(nid: int, p: Vector3) -> void:
	var node = objects.get(nid)
	if node == null or not is_instance_valid(node):
		return
	var o: Dictionary = node.get_meta("ei")
	if not node.has_meta("moved_from"):
		node.set_meta("moved_from", o.position)
	o.position = p
	node.position = EISpace.pos(p.x, p.y, terrain.height_at(p.x, p.y) + p.z)
	nav.remove_object(nid)
	nav.add_object(node)


## A magic trap whose figure (efcu0, an editor marker) has no model still is a
## map object scripts name (ActivateTrap): an empty node in its place.
func _trap_marker(o: Dictionary, parent: Node3D) -> Node3D:
	if o.kind != "MAGIC_TRAP":
		return null
	var node := Node3D.new()
	var p: Vector3 = o.position
	node.position = EISpace.pos(p.x, p.y, terrain.height_at(p.x, p.y) + p.z)
	node.name = String(o.get("name", "MagicTrap")).validate_node_name()
	node.set_meta("ei", o)
	parent.add_child(node)
	return node


## Loads a zone by map name; `mob_name` defaults to the same name.
func load_map(mpr: String, mob_name := "", with_units := true) -> bool:
	map = EIMapScene.load_map(mpr, mob_name, false)
	if map == null:
		return false
	add_child(map)
	terrain = map.terrain
	mob = map.mob
	if mob:
		diplomacy = mob.diplomacy
	for node in map.object_nodes:
		_register_object(node)
	if mob:
		var root: Node3D = map.get_node_or_null("Objects")
		for o: Dictionary in mob.objects:
			if not objects.has(int(o.get("nid", 0))):
				var marker := _trap_marker(o, root if root else map)
				if marker:
					_register_object(marker)
	NetStatus.keep_alive()
	# The original's AI map takes the water from the.sec files and is
	# not rebuilt by SetWaterLevel.
	nav.build(terrain, terrain.water_base, map.object_nodes)
	NetStatus.keep_alive()
	lever_sys = LeverSystem.new(self)
	if with_units:
		for r in map.unit_records:
			NetStatus.keep_alive()
			spawn_unit(r)
			LoadingScreen.object_done()
		# The nav grids of the units' standing classes, built while loading
		# rather than on a unit's first path (NavGrid.layer).
		for u: GameUnit in unit_rows():
			NetStatus.keep_alive()
			nav.layer(u._classes[2])
	LoadingScreen.objects_done()
	return true


func spawn_unit(record: Dictionary) -> GameUnit:
	if not record.has("nid") or int(record.nid) == 0 or units.has(int(record.nid)):
		record.nid = new_uid()
	var u := GameUnit.new()
	if not u.setup(self, record):
		u.free()
		return null
	set_unit(u.uid, u)
	_seq_n += 1
	u._seq = _seq_n
	nav.rebucket(u)
	add_child(u)
	unit_spawned.emit(u)
	return u


func new_uid() -> int:
	_next_uid += 1
	return _next_uid


func remove_unit(u: GameUnit) -> void:
	u._seq = 0
	nav.untrack_unit(u)
	erase_unit(u.uid)
	u.queue_free()


## A looted corpse leaves the world (the original)
## but is kept, out of the tree, for the script VM's WasLooted.
func remove_looted(u: GameUnit) -> void:
	u._seq = 0
	nav.untrack_unit(u)
	erase_unit(u.uid)
	u.set_meta("looted", true)
	looted[u.uid] = u
	if u.get_parent():
		u.get_parent().remove_child(u)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_ENTER_TREE, NOTIFICATION_EXIT_TREE, NOTIFICATION_PAUSED,
			NOTIFICATION_UNPAUSED, NOTIFICATION_DISABLED, NOTIFICATION_ENABLED,
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED,
			_ENGINE_SUSPENDED, _ENGINE_UNSUSPENDED]:
		# A new/retained/resumed world must not consume the loading or paused
		# interval. Its native remainder and pending spell callbacks survive.
		_frame_ms = -1
		_client_effect_frame_ms = -1
	elif what == NOTIFICATION_PREDELETE:
		# Both interpreter objects are RefCounted. Their live reciprocal refs
		# must be broken only when this world is actually being destroyed;
		# cached LMP worlds retain their callbacks and running instances.
		if vm:
			if vm.briefings:
				vm.briefings.vm = null
				vm.briefings = null
			vm = null
		for u in looted.values():
			if is_instance_valid(u):
				u.free()
		looted.clear()


func ground_at(x: float, y: float) -> float:
	# Native client-world (5618e0): terrain, then BASE-part planes.
	if terrain == null:
		return 0.0
	return nav.ground_height(Vector2(x, y), terrain.ground_at(x, y))


## Line of sight between two units' eyes, the original
## (`NavGrid.ray`: ground and object spans, 0 .. 1). Eye points use the
## The observer's scan origin keeps the normal figure height
## the target eye applies its posture (GameUnit.eye_z).
func sight_ray(a: GameUnit, b: GameUnit) -> float:
	return terrain_ray(a.pos, a.eye_z(false), b.pos, b.eye_z())


##  between two given points (x, y, height in m): 0 where the
## segment, walked in 0.5 m steps, runs at or below the ground, else the
## product of the object spans' factors it passes (`NavGrid.ray`).
func terrain_ray(a: Vector2, za: float, b: Vector2, zb: float) -> float:
	if terrain == null:
		return 1.0
	if nav.size.x > 0:
		return nav.ray(a, za, b, zb)
	var n := roundi(Vector3(b.x - a.x, b.y - a.y, zb - za).length() / 0.5)
	for i in range(1, n):
		var t := float(i) / n
		var q := a.lerp(b, t)
		if lerpf(za, zb, t) <= ground_at(q.x, q.y):
			return 0.0
	return 1.0


## The ray from a unit's eyes to a point 1 m above the ground (vision fog).
func sight_ray_point(a: GameUnit, p: Vector2) -> float:
	return terrain_ray(a.pos, a.eye_z(false),
		p, _stand_z(p) + 1.0)


## The height a unit stands at: the ground, or a floor over it.
func _stand_z(p: Vector2) -> float:
	var g := ground_at(p.x, p.y)
	return maxf(g, nav.cell_height(p)) if nav.size.x > 0 else g


var _spatial_rows: Array = []
var _spatial_ranks := {}
var _spatial_nav: NavGrid
var _spatial_registry_rev := -1
var _spatial_units_rev := -1
var _spatial_structure_rev := -1
var _spatial_registered := false


## Registry order remains authoritative, including erase/reinsert and
## synthetic worlds whose _seq values differ. Versions replace repeated
## O(population) snapshots and equality checks on every local query.
func _spatial_order() -> void:
	var revision := nav.registry_rev if nav else -1
	if units_revision == _spatial_units_rev and GameUnit.structure_revision == _spatial_structure_rev \
			and nav == _spatial_nav and revision == _spatial_registry_rev:
		return
	var rows := _unit_rows
	_spatial_rows = rows
	_spatial_units_rev = units_revision
	_spatial_structure_rev = GameUnit.structure_revision
	_spatial_nav = nav
	_spatial_registry_rev = revision
	_spatial_ranks.clear()
	_spatial_registered = nav != null and nav.size.x > 0 and nav.registered_units.size() == rows.size()
	for i in rows.size():
		var candidate: Variant = rows[i]
		if not is_instance_valid(candidate) or not candidate is GameUnit:
			_spatial_registered = false
			continue
		var u: GameUnit = candidate
		var id := u.get_instance_id()
		if _spatial_ranks.has(id):
			_spatial_registered = false   # a fixture may register one value twice
		_spatial_ranks[id] = i
		if nav == null or u.world != self or u._seq == 0 or u._abucket < 0 or nav.registered_units.get(id) != u \
				or not (nav._all_buckets.get(u._abucket, []) as Array).has(u):
			_spatial_registered = false


func order_near_units(list: Array) -> Array:
	if list.size() < 2:
		return list
	_spatial_order()
	return _order_near_units_current(list)


# The synchronous bucket read cannot change membership after units_near
# sampled it. Reuse that order without allocating another registry snapshot.
func _order_near_units_current(list: Array) -> Array:
	if list.size() < 2:
		return list
	if ai and ai._unit_query and list.size() < 1048576:
		return ai._unit_query.order_units(list, _spatial_ranks)
	var keys := PackedInt64Array()
	keys.resize(list.size())
	for i in list.size():
		var id := (list[i] as GameUnit).get_instance_id()
		if not _spatial_ranks.has(id):
			return NavGrid._in_seq_order(list)   # standalone tracked-unit fixtures
		keys[i] = (int(_spatial_ranks[id]) << 20) | i
	keys.sort()
	var out := []
	out.resize(list.size())
	for i in list.size():
		out[i] = list[keys[i] & 0xfffff]
	return out


func units_near(p: Vector2, r: float) -> Array:
	_spatial_order()
	# Retain the exhaustive path for unregistered/synthetic worlds and wide
	# global queries. Negative radii historically use r*r in this API too.
	if authority and _spatial_registered and is_finite(r) and r >= 0.0 \
			and is_finite(p.x) and is_finite(p.y) and nav.local_bucket_query(p, r):
		return _order_near_units_current(nav.units_all_around(p, r, false))
	var out := []
	var r2 := r * r
	for candidate in _spatial_rows:
		if is_instance_valid(candidate) and candidate is GameUnit and candidate.pos.distance_squared_to(p) <= r2:
			out.append(candidate)
	return out


## Exact perception broadphase. Sample membership/order before the query;
## unusual, unregistered and off-map fixtures keep the original two passes.
func notice_units_near(observer: GameUnit, radius: float, cells: Dictionary, alive: bool, tracked: bool) -> Array:
	_spatial_order()
	var p := observer.pos
	var kernel: RefCounted = ai._unit_query if ai else null
	if kernel and authority and _spatial_registered and radius >= NavGrid.WIDE \
			and p.x + radius < 65536.0 and p.y + radius < 65536.0 and nav.local_bucket_query(p, radius):
		return kernel.order_units(kernel.near_cells(nav._call_buckets, p, radius, cells, observer, alive), _spatial_ranks)
	var list := nav.units_all_around(p, radius) if tracked and authority and nav.size.x > 0 else units_near(p, radius)
	if kernel:
		return kernel.in_cells(list, observer, p, cells, alive)
	var out := []
	var center := Vector2i(int(GameUnit._fistp(p.x * 2.0 - 0.5) / 32), int(GameUnit._fistp(p.y * 2.0 - 0.5) / 32))
	for u: GameUnit in list:
		if u == observer or (alive and u.dead): continue
		var cell := Vector2i(int(GameUnit._fistp(u.pos.x * 2.0 - 0.5) / 32), int(GameUnit._fistp(u.pos.y * 2.0 - 0.5) / 32))
		if cells.has(cell - center): out.append(u)
	return out


## Same registry/range/order semantics, with the current living state.
func live_units_near(p: Vector2, r: float) -> Array:
	return units_near(p, r).filter(func(u: GameUnit): return not u.dead)


func relation(fa: int, fb: int) -> int:
	if diplomacy.size() >= 1024 and fa >= 0 and fa < 32 and fb >= 0 and fb < 32:
		return diplomacy[fa * 32 + fb]
	return 0 if fa == fb else 1


func set_relation(fa: int, fb: int, v: int) -> void:
	if fa < 0 or fa >= 32 or fb < 0 or fb >= 32:
		return
	if diplomacy.size() < 1024:
		diplomacy.resize(1024)
		diplomacy.fill(1)
		for i in 32:
			diplomacy[i * 32 + i] = 0   # own-side friend bits
	#  changes only this row. Its notification replaces that
	# side's bit in each affected unit's hostility mask, including hit hate.
	diplomacy[fa * 32 + fb] = v
	ai.activity.invalidate()
	for u: GameUnit in unit_rows():
		if u.faction != fa or not u.has_meta("hate"):
			continue
		var h: Dictionary = u.get_meta("hate")
		if int(h.get("w", 0)) == get_instance_id():
			(h.get("f", []) as Array).erase(fb)


## 0 (night) .. 1 (day) from the campaign clock; caves stay dim.
func daylight() -> float:
	if String(zone.get("sky", "")) == "cave":
		return 0.35
	var hour := session.state.world_time if session and session.state else 12.0
	return clampf(sin((hour - 5.0) / 14.0 * PI) * 1.6, 0.0, 1.0)


## Simulation darkness, separate from rendered daylight.
func darkness() -> float:
	var hour := fmod(float(session.state.world_time), 24.0) if session and session.state else 12.0
	if hour > 20.0:
		return float(PackedFloat32Array([(hour - 20.0) * 0.25])[0])
	return 1.0 if hour < 8.0 else 0.0


##  stores 0.9 while precipitation is active, else 1.
## The replay record holds the authoritative weather event for this world.
func weather_sight_factor() -> float:
	var replay: Dictionary = get_meta("replay", {})
	return 0.8999999761581421 if int(replay.get("weather", {}).get("w", 0)) != 0 else 1.0


func is_enemy(a: GameUnit, b: GameUnit) -> bool:
	# actor AND actor AND target-side bit.
	# Taming clears the tamer's bit in the actor's allowed mask
	# suppressing both diplomacy and hit-induced hate. This is directional:
	# the target's allowed mask does not participate in the actor's query.
	if a.has_meta("peace") and b.faction in a.get_meta("peace"):
		return false
	#  sets a side's bit in a unit's own hostility mask:
	# the unit is then hostile to that side whatever the diplomacy (meta "hate").
	# Kept per zone world: the sides are the zone's (a hero carries no hate on).
	if a.has_meta("hate"):
		var hate: Dictionary = a.get_meta("hate")
		if int(hate.get("w", 0)) == get_instance_id() and b.faction in hate.get("f", []):
			return true
	return relation(a.faction, b.faction) == 2


func draw_frame_enabled() -> bool:
	return not _fixed_step and is_inside_tree() and is_physics_processing()


func frame_clock_enabled() -> bool:
	return authority and draw_frame_enabled()


func _process(_dt: float) -> void:
	if not authority and not _fixed_step:
		_sample_client_effect_frame(Time.get_ticks_msec(), Engine.time_scale)
		if _client_placement and draw_frame_enabled():
			_client_placement.sync_clients(self, _unit_rows, _dt, Engine.get_process_frames())
	if not frame_clock_enabled():
		_frame_ms = -1
		if lever_sys:
			lever_sys.draw(_dt)
		return
	_sample_frame(Time.get_ticks_msec(), Engine.time_scale)
	if lever_sys:
		lever_sys.draw(_dt)


## Full native integer timestamp delivery. Even an empty retained world
## consumes the timestamp, so returning to it cannot catch up its absence.
## First callbacks begin at zero (456440's initial two timeGetTime reads).
func _sample_frame(now_ms: int, rate: float, active := true) -> void:
	var before := _frame_ms
	_frame_ms = now_ms
	if before < 0 or not authority or not active:
		return
	var elapsed := (now_ms - before) & 0xffffffff
	if elapsed > 0x80000000:
		return   # the original DWORD clock's backwards-time guard
	_deliver(float(elapsed) / 1000.0 * rate)


func _physics_process(dt: float) -> void:
	if not authority:
		# Fixed-FPS/off-tree tools retain their deterministic supplied clock.
		# Runtime clients cap raw frame elapsed before the native rate.
		if _fixed_step or not is_inside_tree() or not is_processing():
			_advance_client_effects(dt)
		return
	# Manually supplied callbacks on off-tree/disabled worlds remain useful
	# to fixtures; an active real-time world advances only once per frame.
	if frame_clock_enabled():
		return
	_deliver(dt)


func _client_effect_active() -> bool:
	if authority or (is_inside_tree() and get_tree().paused):
		return false
	return session == null or (session.world == self and not session.loading_game \
		and not session._zone_holding and not session._remote_loading and not session.movie_active())


func _sample_client_effect_frame(now_ms: int, rate: float) -> void:
	var before := _client_effect_frame_ms
	_client_effect_frame_ms = now_ms
	if before < 0 or not _client_effect_active():
		return
	var elapsed := (now_ms - before) & 0xffffffff
	if elapsed > 0x80000000:
		return
	_advance_client_effects(minf(float(elapsed) / 1000.0, TICK * 5.0) * rate)


## Packet application replaces remaining counts without resetting this
## shared phase.510890 decrements only positive counters; it never erases
## at zero. The next authority list is the sole removal/correction source.
func _advance_client_effects(dt: float) -> void:
	if not _client_effect_active() or not is_finite(dt):
		return
	_client_effect_accumulator += maxf(dt, 0.0)
	while _client_effect_accumulator + 0.000000001 >= TICK:
		_client_effect_accumulator = maxf(_client_effect_accumulator - TICK, 0.0)
		_client_effect_step += 1
		for u: GameUnit in unit_rows():
			u.client_tick_effects()


func _deliver(dt: float) -> void:
	if not authority or (session and session.movie_active()):
		return
	if session and session.lmp_travel:
		if session.lmp_travel.can_tick(self):
			session.lmp_travel.with_world(self, _advance.bind(dt))
		return
	_advance(dt)


## Keep network / session processing at its existing physics cadence; only
## the authoritative world consumes completed native logic intervals here.
## Direct _tick calls remain available to bounded simulation tools.
func _advance(dt: float) -> void:
	if not is_finite(dt):
		return
	if retain_logic_debt:
		_logic_debt += maxf(dt, 0.0)
		var incoming := minf(_logic_debt, TICK * 5.0)
		_logic_debt -= incoming
		_logic_accumulator += incoming
	else:
		_logic_accumulator += clampf(dt, 0.0, TICK * 5.0)
	var steps := 0
	while _logic_accumulator + 0.000000001 >= TICK:
		_logic_accumulator = maxf(_logic_accumulator - TICK, 0.0)
		_tick(TICK)
		steps += 1
		if is_queued_for_deletion() or (session and session.movie_active()):
			break
		if retain_logic_debt and steps >= 5:
			break
	if retain_logic_debt and _logic_accumulator + 0.000000001 >= TICK:
		# A movie may interrupt a batch. Its undelivered whole ticks remain
		# pending, while spline interpolation always sees a fraction below one.
		var pending := floori((_logic_accumulator + 0.000000001) / TICK) * TICK
		_logic_debt += pending
		_logic_accumulator = maxf(_logic_accumulator - pending, 0.0)


##  stores the client clock remainder as float32. Rendering
## evaluates the existing spline at that fraction without moving the unit,
## changing its path or repainting its authoritative navigation stamp.
var _fraction_acc := NAN
var _fraction_value := 0.0


func logic_fraction() -> float:
	# Every unit draws from the same remainder. Convert it to native float32
	# once per value, retaining identical results after direct clock edits.
	if _fraction_acc != _logic_accumulator:
		_fraction_acc = _logic_accumulator
		_fraction_value = float(PackedFloat32Array([_logic_accumulator / TICK])[0])
	return _fraction_value


func draw_time() -> float:
	return time + logic_fraction() * TICK


func _tick(dt: float) -> void:
	var started := Time.get_ticks_usec() if profile_simulation else 0
	_logic_step += 1
	_tick_body(dt)
	profile_record("world",started)


func _tick_body(dt: float) -> void:
	var started := Time.get_ticks_usec() if profile_simulation else 0
	corpse_pools.prepare_restore()
	# A conversation does not stop the world: the original pauses it only under a
	# modal screen in single player ((1)); the
	# village screen is entered through, which unpauses
	# ((0)), and its dialog pauses
	# nothing — the partner even walks to its spot through an ordinary AI walk
	# order that only a running world carries out.
	# Every actor keeps its ordinary unit tick too. The village screen tracks
	# its staging orders separately; it never holds their logic.
	var talking := false
	if vm:
		started = Time.get_ticks_usec() if profile_simulation else 0
		vm.tick(dt)
		talking = not vm.briefings.active.is_empty()
		if not talking:
			for u in dialog_movers.keys():
				if not dialog_movers[u].get("restore", false):
					dialog_movers.erase(u)
			dialog_actors.clear()
		_tick_dialog_movers(dt)
		vm.briefings.staging_tick()
		profile_record("script",started)
	if lever_sys:
		lever_sys.tick()
	time += dt
	ai.activity.begin_tick(dt)
	# Native5d53b0 ticks the selected motivation once per completed server
	# dispatch. Counting floor(time/55ms) loses/doubles rolls when the double
	# world clock straddles a rounding boundary. Fractional diagnostic _tick
	# calls retain their existing elapsed-boundary semantics.
	var chat := dt == TICK or floorf(time / TICK) > floorf((time - dt) / TICK)
	started = Time.get_ticks_usec() if profile_simulation else 0
	for u: GameUnit in unit_rows():
		u.tick(dt)
		if chat:
			ai.chatter(u, dt)
	profile_record("units",started)
	ai.activity.end_tick()
	# Magic traps update on the 55 ms server tick.
	_trap_t += dt
	while _trap_t >= GameUnit.TICK:
		_trap_t -= GameUnit.TICK
		started = Time.get_ticks_usec() if profile_simulation else 0
		traps.tick()
		profile_record("traps",started)
		started = Time.get_ticks_usec() if profile_simulation else 0
		ai.tick()
		profile_record("ai_tick",started)
		if tornadoes == null:
			tornadoes = Tornadoes.new(self)
		started = Time.get_ticks_usec() if profile_simulation else 0
		tornadoes.tick()
		profile_record("tornadoes",started)
	#  updates scene objects before water and spell wrappers. In
	# particular a delayed spell sees this tick's completed creature movement.
	started = Time.get_ticks_usec() if profile_simulation else 0
	_tick_water(dt)
	profile_record("water",started)
	var timers := get_node_or_null("SpellTimers") as Spells.WorldTimers
	if timers:
		timers._tick(dt, true)
	corpse_pools.refresh()


## an ordinary walk, then facing, with a 30-second staging
## deadline. Actors are ticked once by the ordinary world loop, including
## after staging finishes and while the phrases are running.
func _tick_dialog_movers(dt: float) -> void:
	for candidate in dialog_movers.keys():
		if not is_instance_valid(candidate) or not (candidate is GameUnit):
			dialog_movers.erase(candidate)
			continue
		var u: GameUnit = candidate
		var m: Dictionary = dialog_movers[u]
		if u.dead:
			dialog_movers.erase(u)
			continue
		m.elapsed = float(m.get("elapsed", 0.0)) + dt
		if float(m.elapsed) > 30.0:
			dialog_place(u, m.to, float(m.angle))
			dialog_movers.erase(u)
		elif int(m.get("state", 1)) == 1:
			if u.pos.distance_squared_to(m.to) < 0.01:
				m.state = 2
				u.command({"type": "rotate", "angle": m.angle, "turn_speed": 1.0 / GameUnit.TICK})
		elif Vector2.from_angle(u.facing).distance_squared_to(Vector2.from_angle(float(m.angle))) < 0.01:
			dialog_movers.erase(u)


##  the staging deadline: try placement, then always face and
## Stop. Static-footprint feasibility still uses the remake's class grid.
func dialog_place(u: GameUnit, point: Vector2, angle: float) -> void:
	var clear := nav.cell_open(point, u.move_class())
	if clear:
		for other: GameUnit in unit_rows():
			if other != u and not other.dead and point.distance_to(other.pos) < u.body_radius() + other.body_radius():
				clear = false
				break
	if clear:
		u.pos = point
	u.facing = angle
	u.command({"type": "wait", "t": 0.0})
	u._anim_lock = 0.0
	u._set_action("idle")


## Authored brief scenes have precise walking marks and distance predicates.
## An extra co-op hero must not turn such a mark into a nearby "successful"
## path endpoint. Let idle guests walk aside before planning the story move.
## Static obstacles and busy/player-commanded units retain ordinary collision.
func prepare_story_move(actor: GameUnit, point: Vector2) -> bool:
	if session == null or not session.online or not session.lmp.is_empty() or zone.get("type", "") != "brief":
		return true
	var ready := true
	for other: GameUnit in party_units():
		if other == actor or other.controller <= 0 or other.dead or other.hidden or not other.has_meta("hero") \
				or other.get_meta("hero").has("merc"):
			continue
		var clearance := actor.body_radius() + other.body_radius() + 0.75
		if other.pos.distance_squared_to(point) >= clearance * clearance:
			continue
		if other.order.get("story_yield", false) or other.orders.any(func(o: Dictionary): return o.get("story_yield", false)):
			ready = false
			continue
		if not other.order.is_empty() or not other.orders.is_empty() or other.blocked or other._anim_lock > 0.0 \
				or (vm and not vm.briefings.active.is_empty() and dialog_actors.has(other.uid)):
			continue
		var away := (other.pos - point).normalized()
		if away.is_zero_approx():
			away = Vector2.from_angle(actor.facing + PI * 0.5)
		var destination := Vector2.INF
		for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI]:
			var target := point + away.rotated(angle) * (clearance + 1.0)
			var route := nav.find_path(other.pos, target, [other], [], 0.0, other.move_class())
			if route.is_empty() or route[-1].distance_squared_to(point) < (clearance + 0.25) * (clearance + 0.25):
				continue
			var length := other.pos.distance_to(route[0])
			for i in range(1, route.size()):
				length += route[i - 1].distance_to(route[i])
			if length <= 6.0:
				destination = route[-1]
				break
		if destination != Vector2.INF:
			other.command({"type": "move", "to": destination, "run": false, "story_yield": true})
			ready = false
	return ready


# ---------------------------------------------------------------- water

## Script SetWaterLevel(material, level, ticks), the original: the
## water of map material `mat` moves linearly to `level` (EI z, relative to the
## map files) over `ticks` logic ticks (at least 1), from where it is now.
func set_water_level(mat: int, level: float, ticks: int) -> void:
	ticks = maxi(ticks, 1)
	var cur := float(water_levels[mat][1]) if water_levels.has(mat) else 0.0
	water_levels[mat] = [ticks, cur, (level - cur) / ticks]
	if authority and session:
		session.publish_water()


## The whole list from the host (the original sends it to the clients after each
## tick that changed it): offsets apply at once.
func set_water_state(levels: Dictionary) -> void:
	if terrain:
		for mat in water_levels:
			if not levels.has(mat):
				terrain.set_water_offset(int(mat), 0.0)
	water_levels = levels.duplicate(true)
	if terrain:
		for mat in water_levels:
			terrain.set_water_offset(int(mat), float(water_levels[mat][1]))


##  on the 55 ms logic tick: each entry with ticks
## left moves by its step; finished entries back at offset 0 are dropped.
## Only the host advances the list. Clients apply its absolute offsets, as
##  do, even if their loading or frame rates differ.
func _tick_water(dt: float) -> void:
	if not authority:
		return
	if water_levels.is_empty():
		_water_t = 0.0
		return
	_water_t += dt
	while _water_t >= GameUnit.TICK:
		_water_t -= GameUnit.TICK
		var changed := false
		for mat in water_levels.keys():
			var e: Array = water_levels[mat]
			if int(e[0]) >= 1:
				changed = true
				e[0] = int(e[0]) - 1
				e[1] = float(e[1]) + float(e[2])
				if terrain:
					terrain.set_water_offset(int(mat), float(e[1]))
			elif float(e[1]) == 0.0:
				water_levels.erase(mat)
				changed = true
		if changed and session:
			session.publish_water()


# ---------------------------------------------------------------- events

func on_attack(a: GameUnit, b: GameUnit) -> void:
	combat_event.emit("attack", a, b, 0.0)


func on_miss(a: GameUnit, b: GameUnit) -> void:
	combat_event.emit("miss", a, b, 0.0)


func on_damage(u: GameUnit, amount: float, source: GameUnit) -> void:
	combat_event.emit("damage", source, u, amount)


func on_death(u: GameUnit, killer: GameUnit) -> void:
	unit_died.emit(u, killer)
	if not authority or session == null:
		return
	# the dead unit's hit hook (call for help)
	# its friends that noticed it see the corpse.
	ai.hit_hook(u, killer)
	ai.on_corpse(u)
	# an AI killer says its kill line (acks.db NPC reaction 0x30)
	# a killer of a player's party (with a player) gets
	# ack 0x30 sent to its player: the Kill line of its record
	# and the portrait's smile.
	if killer and is_instance_valid(killer) and killer.controller < 0 and not killer.has_meta("hero"):
		ai._react(killer, EIAcks.NPC_KILL)
	elif killer and is_instance_valid(killer) and killer != u:
		killer.ack(EIAcks.NPC_KILL)
	if u.has_meta("hero") and not u.get_meta("hero").has("merc"):
		session.hero_died(u)
	if u.has_meta("hero") and u.get_meta("hero").has("merc"):
		var n := int(u.get_meta("hero").merc)
		session.state.set_var(0, "adeadn%d" % n, 1.0)
		if not Revive.keep_fallen(session, u):   # remake option "revive": the record waits
			session.state.mercs.erase(n)
		session.broadcast({"t": "party"})
	if not u.has_meta("hero"):
		# What was not stolen stays in its pockets.
		var loot: Array = u.get_meta("pockets") if u.has_meta("pockets") else Items.roll_loot(u.proto, u.info, combat.rng)
		if not loot.is_empty():
			u.set_meta("loot", loot)
			session.broadcast({"t": "loot", "uid": u.uid, "has": true})
		# the original: the prototype "experience" for
		# the killer's party (XpRules: who gets it and how it is shared).
		XpRules.on_kill(session, u, killer if is_instance_valid(killer) else null)
