extends Node
## Optional local visual water contacts. No simulation actors, collision,
## save data, network packets or additional water draws are introduced.
const Surface = preload("res://src/game/fx/water_surface.gd")
const MAX_UNITS := 16
const MAX_CANDIDATES := 32
const DISTANCE := 55.0
const ENTER_SECONDS := 0.35
const LEAVE_SECONDS := 0.7
const TURN_SECONDS := 0.22
var game: Game
var _world: GameWorld
var _surface: Surface
var _contacts := {}
var _clock := 0.0
var _enabled := false
var last_update_us := 0

class Contact:
	var unit: WeakRef
	var root := Vector3.ZERO
	var position := Vector3.ZERO
	var heading := Vector2(0,1)
	var radius := 0.2
	var speed := 0.0
	var motion := 0.0
	var presence := 0.0
	var phase := 0.0


func _init(g: Game = null) -> void:
	game = g; name = "WaterInteraction"
	# Game itself runs while paused. These visual histories do not.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 3 # after unit presentation, UnitFog and step effects


func _ready() -> void:
	GameData.options_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	clear()


func refresh() -> void:
	_enabled = Gfx.on("gfx_water_interaction") and Gfx.on("gfx_water")
	if not _enabled: clear()
	set_process(_enabled and DisplayServer.get_name() != "headless")


func clear() -> void:
	if is_instance_valid(_world) and is_instance_valid(_world.terrain) and _world.terrain._water_mat:
		_world.terrain._water_mat.set_shader_parameter("water_contact_count",0)
	_contacts.clear(); _surface = null; _world = null; _clock = 0.0


func _process(dt: float) -> void:
	var world: GameWorld = game.world if is_instance_valid(game) else null
	if not is_instance_valid(world) or not is_instance_valid(game.rig):
		clear(); return
	if not world.can_process(): return # travel map retains a frozen zone
	var session := world.session
	if session and (session.loading_game or session._zone_holding or session._remote_loading or session.movie_active()):
		return
	if session and session.lmp_travel and not session.lmp_travel.can_tick(world): return
	step(world,game.rig.camera,dt)


static func shown(u: GameUnit) -> bool:
	return is_instance_valid(u) and u.is_inside_tree() and u.is_visible_in_tree() \
		and not u.hidden and not u.fogged and not u.dead and is_instance_valid(u.model) and u.model.is_visible_in_tree()


## Visible, posed part boxes, not a locomotion-class guess. A levitating
## model may have a navigation root on the bed while every part is above water.
static func vertical_bounds(u: GameUnit) -> Vector2:
	var lo := INF; var hi := -INF
	for part in u._geoms:
		if not is_instance_valid(part) or not part is MeshInstance3D or not part.is_visible_in_tree() or part.mesh == null: continue
		var bounds: AABB = part.get_global_transform_interpolated()*part.get_aabb()
		lo = minf(lo,bounds.position.y); hi = maxf(hi,bounds.end.y)
	return Vector2(lo,hi)

static func near_water(terrain: EITerrain, p: Vector3) -> bool:
	if is_finite(terrain.water_at(p.x,-p.z)): return true
	# Animated vertices can cross the edge of a dry navigation cell. This is
	# only a cheap candidate test; the deformed triangle query decides contact.
	for offset: Vector2 in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1),
		Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
		if is_finite(terrain.water_at(p.x+offset.x,-p.z+offset.y)): return true
	return false


static func advance(contact: Contact, root: Vector3, height: float, dt: float) -> void:
	var delta := Vector2(root.x-contact.root.x,root.z-contact.root.z)
	var distance := delta.length()
	# Same presentation cut scale as GameUnit: do not draw a connecting wake
	# across teleports, loading placement or large snapshot corrections.
	if distance > 2.0:
		contact.motion = 0.0; contact.presence = 0.0; contact.speed = 0.0
		distance = 0.0
	var speed := distance/maxf(dt,0.00001)
	var moving := speed > 0.25
	contact.presence = move_toward(contact.presence,1.0,dt/ENTER_SECONDS)
	contact.motion = move_toward(contact.motion,1.0 if moving else 0.0,dt/(ENTER_SECONDS if moving else LEAVE_SECONDS))
	if moving:
		var angle := lerp_angle(contact.heading.angle(),delta.angle(),1.0-exp(-dt/TURN_SECONDS))
		contact.heading = Vector2.from_angle(angle)
		contact.speed = minf(speed,6.0)
	contact.root = root
	contact.position = Vector3(root.x,height,root.z)


func step(world: GameWorld, camera: Camera3D, dt: float) -> void:
	if not is_instance_valid(_world) or world != _world:
		clear(); _world = world
	if not is_instance_valid(world) or not is_instance_valid(world.terrain) or camera == null: return
	if not _enabled or dt <= 0.0 or not is_finite(dt): return
	if dt > 0.5:
		_contacts.clear(); dt = 0.0 # resume without a long stale motion segment
	var started := Time.get_ticks_usec()
	_clock += dt
	if _surface == null: _surface = Surface.new(world.terrain)
	_surface.begin_frame()
	var candidates := []
	var cam := camera.global_position
	for u: GameUnit in world.visible_units():
		if not shown(u) or not u.near_screen(): continue
		var root := u.get_global_transform_interpolated().origin
		var p := world.terrain.to_local(root)
		if p.x < 0.0 or -p.z < 0.0 or p.x >= world.terrain.size_ei().x or -p.z >= world.terrain.size_ei().y: continue
		var distance := root.distance_squared_to(cam)
		if distance > DISTANCE*DISTANCE: continue
		# Cheap broad phase only; the actual admission uses rendered triangles.
		if not near_water(world.terrain,p): continue
		var id := u.get_instance_id()
		candidates.append({"unit":u,"root":root,"id":id,"score":distance*(0.85 if _contacts.has(id) else 1.0)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.score < b.score if a.score != b.score else a.id < b.id)
	var inputs := {}
	for i in mini(MAX_CANDIDATES,candidates.size()):
		var c: Dictionary = candidates[i]
		var hit: Dictionary = _surface.sample(Vector2(c.root.x,c.root.z))
		if hit.is_empty() or hit.lava: continue
		var local := world.terrain.to_local(c.root)
		var width := world.terrain.sectors_x*32
		var cell := floori(-local.z)*width+floori(local.x)
		if cell >= world.terrain.liquid_ground.size() or world.terrain.liquid_ground[cell] in [13,14]: continue
		var bound := vertical_bounds(c.unit)
		if bound.x > float(hit.height)+0.04 or bound.y < float(hit.height)-0.04: continue
		c.height = hit.height; inputs[c.id] = c
		if inputs.size() == MAX_UNITS: break
	for id: int in _contacts.keys():
		var contact: Contact = _contacts[id]
		var u := contact.unit.get_ref() as GameUnit
		if not shown(u) or not world.is_ancestor_of(u):
			_contacts.erase(id); continue # never reveal a hidden or retired actor
		if not inputs.has(id):
			contact.presence = move_toward(contact.presence,0.0,dt/LEAVE_SECONDS)
			contact.motion = move_toward(contact.motion,0.0,dt/LEAVE_SECONDS)
			if contact.presence == 0.0: _contacts.erase(id)
	for id: int in inputs:
		var input: Dictionary = inputs[id]
		if not _contacts.has(id):
			if _contacts.size() >= MAX_UNITS:
				for old: int in _contacts.keys():
					if not inputs.has(old): _contacts.erase(old); break
			if _contacts.size() >= MAX_UNITS: break
			var contact := Contact.new(); contact.unit = weakref(input.unit)
			contact.root = input.root
			contact.heading = Vector2.from_angle(-input.unit.facing)
			contact.radius = clampf(input.unit.figure_radius*0.6,0.06,1.5)
			contact.phase = fposmod(float(input.unit.uid)*2.399963,TAU)
			_contacts[id] = contact
		advance(_contacts[id],input.root,float(input.height),dt)
	_bind()
	last_update_us = Time.get_ticks_usec()-started


func _bind() -> void:
	if not is_instance_valid(_world) or _world.terrain._water_mat == null: return
	var positions := PackedVector4Array(); var motion := PackedVector4Array(); var presence := PackedVector2Array()
	positions.resize(MAX_UNITS); motion.resize(MAX_UNITS); presence.resize(MAX_UNITS)
	var index := 0
	for c: Contact in _contacts.values():
		positions[index] = Vector4(c.position.x,c.position.z,c.position.y,c.radius)
		motion[index] = Vector4(c.heading.x,c.heading.y,c.speed,c.motion)
		presence[index] = Vector2(c.presence,c.phase); index += 1
	var material := _world.terrain._water_mat
	material.set_shader_parameter("water_contact_count",index)
	material.set_shader_parameter("water_contact_position",positions)
	material.set_shader_parameter("water_contact_motion",motion)
	material.set_shader_parameter("water_contact_presence",presence)
	material.set_shader_parameter("water_contact_phase",fposmod(_clock*4.0,TAU))
