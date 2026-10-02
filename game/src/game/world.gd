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

const TICK := 1.0 / 20.0

var zone := {}
var map: EIMapScene
var terrain: EITerrain
var mob: EIMob
var nav := NavGrid.new()
var combat: Combat
var ai: UnitAI
var vm: ScriptVM
var units := {}          # uid -> GameUnit
## Looted corpses taken off the world (Session.take_loot): uid -> GameUnit,
## out of the tree. the original's drops the object from the server
## but the script variables that hold it keep it, and WasLooted (builtin
## 0xe3) still reads its looted flag; the VM finds them here (and by uid
## after a save, CampaignState "looted").
var looted := {}
var objects := {}        # nid -> Node3D (placed map objects)
var levers := {}         # nid -> {state, states, cycled, door}
var lever_sys: LeverSystem
## .mob MAGIC_TRAP objects (the original CMagicTrapObject), run by the host.
var traps: MagicTraps
## "#weather tornado" zones' tornadoes (host, made on the first tick).
var tornadoes: Tornadoes
var _trap_t := 0.0
var diplomacy := PackedInt32Array()
var time := 0.0
## Conversation actors still walking to their spot.
var dialog_movers := {}   # GameUnit -> {to: Vector2, angle: float}
## Unit ids of the running conversation's actors a / b / c (Briefings.cast),
## held while it runs; the rest of the world goes on.
var dialog_actors := {}
var authority := true
var session: Session
## SetWaterLevel state, the original's list at server (adds
##  ticks): map material -> [ticks left, offset, offset per tick].
var water_levels := {}
var _water_t := 0.0
var _next_uid := 1_500_000_000
var _seq_n := 0   # GameUnit._seq of the last unit put in `units`


func _init() -> void:
	combat = Combat.new(self)
	ai = UnitAI.new(self)
	traps = MagicTraps.new(self)


func _register_object(node: Node3D) -> void:
	var o: Dictionary = node.get_meta("ei")
	objects[int(o.get("nid", 0))] = node
	if o.kind == "LEVER":
		levers[int(o.nid)] = {"state": int(o.get("lever_state", 0)), "states": maxi(1, int(o.get("lever_states", 2))),
			"cycled": int(o.get("lever_cycled", 0)), "door": int(o.get("lever_door", 0)), "enabled": true,
			"science": Array(o.get("lever_science", PackedInt32Array([1, 0, 0])))}
	elif o.kind == "MAGIC_TRAP":
		traps.add(o)
	if "bridge" in String(o.get("parent_template", "")).to_lower():
		terrain.add_surface(node)


## A map object's radius (the original object, computed when
## the figure is built or a lever changes state): the half
## diagonal of the box round all its parts (part offset + part box) about
## the box centre; the object's returns it (CLeverObject
## ). Here: the node-local box of its meshes.
func object_radius(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
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
	LoadingScreen.tick()
	NetStatus.keep_alive()
	# The original's AI map takes the water from the.sec files and is
	# not rebuilt by SetWaterLevel.
	nav.build(terrain, terrain.water_base, map.object_nodes)
	LoadingScreen.tick()
	NetStatus.keep_alive()
	lever_sys = LeverSystem.new(self)
	if with_units:
		for r in map.unit_records:
			LoadingScreen.tick()
			NetStatus.keep_alive()
			spawn_unit(r)
		# The nav grids of the units' standing classes, built while loading
		# rather than on a unit's first path (NavGrid.layer).
		for u: GameUnit in units.values():
			NetStatus.keep_alive()
			nav.layer(u._classes[2])
	return true


func spawn_unit(record: Dictionary) -> GameUnit:
	if not record.has("nid") or int(record.nid) == 0 or units.has(int(record.nid)):
		record.nid = new_uid()
	var u := GameUnit.new()
	if not u.setup(self, record):
		u.free()
		return null
	units[u.uid] = u
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
	units.erase(u.uid)
	u.queue_free()


## A looted corpse leaves the world (the original)
## but is kept, out of the tree, for the script VM's WasLooted.
func remove_looted(u: GameUnit) -> void:
	u._seq = 0
	nav.untrack_unit(u)
	units.erase(u.uid)
	u.set_meta("looted", true)
	looted[u.uid] = u
	if u.get_parent():
		u.get_parent().remove_child(u)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for u in looted.values():
			if is_instance_valid(u):
				u.free()
		looted.clear()


func ground_at(x: float, y: float) -> float:
	return terrain.ground_at(x, y) if terrain else 0.0


## Line of sight between two units' eyes, the original
## (`NavGrid.ray`: ground and object spans, 0 .. 1). Approx.: eyes at the
## ground (or floor) + 1.5 m x race "head height".
func sight_ray(a: GameUnit, b: GameUnit) -> float:
	return terrain_ray(a.pos, _stand_z(a.pos) + 1.5 * float(a.race.get("head_height", 1.0)),
		b.pos, _stand_z(b.pos) + 1.5 * float(b.race.get("head_height", 1.0)))


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
	return terrain_ray(a.pos, _stand_z(a.pos) + 1.5 * float(a.race.get("head_height", 1.0)),
		p, _stand_z(p) + 1.0)


## The height a unit stands at: the ground, or a floor over it.
func _stand_z(p: Vector2) -> float:
	var g := ground_at(p.x, p.y)
	return maxf(g, nav.cell_height(p)) if nav.size.x > 0 else g


func units_near(p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	for u: GameUnit in units.values():
		if u.pos.distance_squared_to(p) <= r2:
			out.append(u)
	return out


## The living units within `r` of `p`, from the unit grid buckets on the
## host (NavGrid.units_around), else a scan of every unit.
func live_units_near(p: Vector2, r: float) -> Array:
	if authority and nav and nav.size.x > 0:
		var out := []
		for u: GameUnit in nav.units_around(p, r):
			if not u.dead:
				out.append(u)
		return out
	return units_near(p, r).filter(func(u: GameUnit): return not u.dead)


func relation(fa: int, fb: int) -> int:
	if fa == fb:
		return 0
	if diplomacy.size() >= 1024 and fa < 32 and fb < 32:
		return diplomacy[fa * 32 + fb]
	return 1


func set_relation(fa: int, fb: int, v: int) -> void:
	if diplomacy.size() < 1024:
		diplomacy.resize(1024)
		diplomacy.fill(1)
	diplomacy[fa * 32 + fb] = v
	diplomacy[fb * 32 + fa] = v


## 0 (night) .. 1 (day) from the campaign clock; caves stay dim.
func daylight() -> float:
	if String(zone.get("sky", "")) == "cave":
		return 0.35
	var hour := session.state.world_time if session and session.state else 12.0
	return clampf(sin((hour - 5.0) / 14.0 * PI) * 1.6, 0.0, 1.0)


func is_enemy(a: GameUnit, b: GameUnit) -> bool:
	#  sets a side's bit in a unit's own hostility mask:
	# the unit is then hostile to that side whatever the diplomacy (meta "hate").
	# Kept per zone world: the sides are the zone's (a hero carries no hate on).
	if a.has_meta("hate"):
		var hate: Dictionary = a.get_meta("hate")
		if int(hate.get("w", 0)) == get_instance_id() and b.faction in hate.get("f", []):
			return true
	# A partly tamed unit keeps the peace with its tamer's side (Spells.tame).
	if relation(a.faction, b.faction) != 2:
		return false
	return not ((a.has_meta("peace") and b.faction in a.get_meta("peace")) \
		or (b.has_meta("peace") and a.faction in b.get_meta("peace")))


func _physics_process(dt: float) -> void:
	_tick_water(dt)
	if not authority:
		return
	# A conversation does not stop the world: the original pauses it only under a
	# modal screen in single player ((1)); the
	# village screen is entered through, which unpauses
	# ((0)), and its dialog pauses
	# nothing — the partner even walks to its spot through an ordinary AI walk
	# order that only a running world carries out.
	# So the other units keep walking, fighting and thinking. Remake
	# (**approx.**): the conversation's actors are held; held actors stand
	# instead of keeping a walk clip going. The script VM runs on (ScriptVM._tick).
	var talking := false
	if vm:
		vm.tick(dt)
		talking = not vm.briefings.active.is_empty()
		if talking:
			_tick_dialog_movers(dt)
		else:
			dialog_movers.clear()
			dialog_actors.clear()
	time += dt
	for u: GameUnit in units.values():
		if talking and (dialog_movers.has(u) or dialog_actors.has(u.uid)):
			if not dialog_movers.has(u) and u.action in ["walk", "run", "crawl"]:
				u._set_action("idle")
			continue
		u.tick(dt)
		ai.chatter(u, dt)
	# Magic traps update on the 55 ms server tick.
	_trap_t += dt
	while _trap_t >= GameUnit.TICK:
		_trap_t -= GameUnit.TICK
		traps.tick()
		ai.tick()
		if tornadoes == null:
			tornadoes = Tornadoes.new(self)
		tornadoes.tick()


## The conversation partner walking to its spot (Briefings._face). The
## script VM is held during the conversation, so the walk is re-issued until
## done; the mover is ticked here, apart from the other units.
func _tick_dialog_movers(dt: float) -> void:
	for u: GameUnit in dialog_movers.keys():
		var m: Dictionary = dialog_movers[u]
		if u.dead:
			dialog_movers.erase(u)
			continue
		# Arrived, or stopped short of a blocked spot for half a second.
		var left := u.pos.distance_to(m.to)
		if left < float(m.get("best", INF)) - 0.02:
			m.best = left
			m.still = 0.0
		else:
			m.still = float(m.get("still", 0.0)) + dt
		if left > 0.3 and float(m.still) < 0.5:
			if String(u.order.get("type", "")) != "move" or u.order.get("to") != m.to:
				u.command({"type": "move", "to": m.to, "run": false})
				u._anim_lock = 0.0   # an idle / scripted animation gives way
		elif absf(angle_difference(u.facing, m.angle)) > 0.05:
			if String(u.order.get("type", "")) != "rotate":
				u.command({"type": "rotate", "angle": m.angle})
				u._anim_lock = 0.0
		else:
			u.command({"type": "wait", "t": 0.1})
			dialog_movers.erase(u)
			continue
		u.tick(dt)


# ---------------------------------------------------------------- water

## Script SetWaterLevel(material, level, ticks), the original: the
## water of map material `mat` moves linearly to `level` (EI z, relative to the
## map files) over `ticks` logic ticks (at least 1), from where it is now.
func set_water_level(mat: int, level: float, ticks: int) -> void:
	ticks = maxi(ticks, 1)
	var cur := float(water_levels[mat][1]) if water_levels.has(mat) else 0.0
	water_levels[mat] = [ticks, cur, (level - cur) / ticks]


## The whole list from the host (the original sends it to the clients after each
## tick that changed it): offsets apply at once.
func set_water_state(levels: Dictionary) -> void:
	water_levels = levels.duplicate(true)
	if terrain:
		for mat in water_levels:
			terrain.set_water_offset(int(mat), float(water_levels[mat][1]))


##  on the 55 ms logic tick: each entry with ticks
## left moves by its step; finished entries back at offset 0 are dropped.
## Runs on every peer (the surface is visual; the AI map does not change).
func _tick_water(dt: float) -> void:
	if water_levels.is_empty():
		_water_t = 0.0
		return
	_water_t += dt
	while _water_t >= GameUnit.TICK:
		_water_t -= GameUnit.TICK
		for mat in water_levels.keys():
			var e: Array = water_levels[mat]
			if int(e[0]) >= 1:
				e[0] = int(e[0]) - 1
				e[1] = float(e[1]) + float(e[2])
				if terrain:
					terrain.set_water_offset(int(mat), float(e[1]))
			elif float(e[1]) == 0.0:
				water_levels.erase(mat)


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
	ai.seen_murder(u, killer)   #  "has seen murder"
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
