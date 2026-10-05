class_name SpellFx
extends Node3D
## Stationary spell lights: native67f780/675d10/678170 keep RGB and range
## constant and move the position. Missile lights belong to ParticleFx.

var light_color := Color.BLACK
var light_radius := 0.0
var light_energy := 1.0
var _light: OmniLight3D
var _local_light := {}
var _world: GameWorld
var _start := 0.0
var _start_age := 0
var _elapsed := 0.0
var _age := 0
var _life := 33
var _move_tick := -1
var _speed := 0.0
var _steps := 0
var _height := 0.0
var _light_id := ""
var _bound: WeakRef
var _bound_required := false


## Tick numbers include state-3 cleanup (67e690).58dcd0 advances existing
## light objects before wrappers enable their velocity for the next tick.
static func profile(sp: Dictionary) -> Dictionary:
	var row: Dictionary = sp.get("proto", {})
	var r := float(row.get("light_radius", 0.0))
	var d := maxi(int(sp.get("duration", 0)), 0)
	var p := {"life": 0, "move": -1, "speed": float(PackedFloat32Array([
		r / maxf(float(row.get("fadeout", 1.0)), 1.0)])[0]),
		"radius": absf(r), "dz": 0.0}
	match String(sp.get("code", "")):
		"lightning", "curse_magic":
			p.life = 90
			p.move = 9
			p.centre = true   # target+1c, +c0, not caster+20
		"inv_lit":
			p.life = 10
			p.move = 1
			p.dz = 2.0
		"acid_column", "healing":
			p.life = 33
			p.move = 1
			p.raw_point = true   # point+24; 58e670 sets its z to ground+0.3
		"firewall", "litnwall", "acid_fog":
			p.life = d + 83
			p.move = d + 3
			p.dz = 1.0
			p.radius = float(PackedFloat32Array([float(sp.get("radius", 0.0)) + r])[0])
		"fireworks":
			p.life = d + 82
			p.move = d + 2
			p.dz = 1.0
		"clairvoyence":
			p.life = d + 2
			p.dz = 1.0
			p.radius = float(sp.get("radius", 0.0))
		"teleport":
			p.life = maxi(d, 1) + 33
			p.dz = -0.2
		_:
			return {}   # no light creator in the native dispatcher
	return p


static func life_ticks(sp: Dictionary) -> int:
	return int(profile(sp).get("life", 0))


## Preserve original placement across movement, save/load and late join.
static func capture_event(w: GameWorld, event: Dictionary, sp: Dictionary) -> void:
	if event.has("light_pos"):
		return
	var p := profile(sp)
	if p.is_empty():
		return
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	var pt := Vector3(at.x, at.y, 0.0)
	if p.get("centre", false):
		var target: GameUnit = w.units.get(int(event.get("tu", -1)))
		if not is_instance_valid(target):
			return
		pt = ParticleFx.of(w).unit_point(target, 0)
	elif p.get("raw_point", false):
		# 58e670 replaces even a supplied point/target z before 67ec70.
		# Explicit z is for an already captured effect record, not casting.
		pt.z = float(event.get("z", PackedFloat32Array([
			w.ground_at(at.x, at.y) + float(PackedFloat32Array([0.3])[0])])[0]))
	elif not p.get("raw_point", false):
		pt.z = float(PackedFloat32Array([w.ground_at(at.x, at.y) + float(p.dz)])[0])
	event.light_pos = [pt.x, pt.y, pt.z]
	if sp.code == "clairvoyence":
		event.light_caster = Spells._caster_ref(w.units.get(int(event.get("a", -1))))


static func spawn_event(w: GameWorld, event: Dictionary) -> SpellFx:
	var sp := Spells.parse(String(event.get("spell", event.get("code", ""))))
	var p := profile(sp)
	if p.is_empty() or event.get("light_cancel", false) or (sp.code == "healing" and event.has("sound_units") and event.sound_units.is_empty()):
		return null   # native automatic full-health healing omits its light too
	var row: Dictionary = sp.proto
	var lc := Color(float(row.get("red", 0.0)), float(row.get("green", 0.0)), float(row.get("blue", 0.0)))
	if lc == Color.BLACK or float(p.radius) == 0.0:
		return null
	var ev := event.duplicate()
	capture_event(w, ev, sp)
	if not ev.has("light_pos"):
		return null
	var fx := SpellFx.new()
	fx._world = w
	fx._start = w.time
	fx._start_age = maxi(int(ev.get("age", 0)), 0)
	fx._life = int(p.life)
	fx._move_tick = int(p.move)
	if sp.code == "teleport" and bool(ev.get("teleport_ok", false)):
		fx._move_tick = 31
	fx._speed = float(p.speed)
	fx._light_id = String(ev.get("light_id", ""))
	if sp.code == "clairvoyence":
		fx._bound_required = true
		fx._bound = Spells._ref(Spells._caster_of(w, ev.get("light_caster", [])))
	fx.light_color = lc
	fx.light_radius = absf(float(p.radius))
	fx._height = float(ev.light_pos[2])
	fx.position = EISpace.pos(float(ev.light_pos[0]), float(ev.light_pos[1]), fx._height)
	w.add_child(fx)
	fx.advance(fx._start_age)
	return fx


## Explicit light for rendering probes; game events use spawn_event.
static func spawn(w: GameWorld, at: Vector2, _subtype: String, _r: float, hold := 0.0, proto := {}) -> void:
	var fx := SpellFx.new()
	fx._world = w
	fx._start = w.time
	fx._life = maxi(33, ceili(hold / GameUnit.TICK))
	fx.light_color = Color(float(proto.get("red", 0.0)), float(proto.get("green", 0.0)), float(proto.get("blue", 0.0)))
	fx.light_radius = absf(float(proto.get("light_radius", 0.0)))
	fx._height = w.ground_at(at.x, at.y) + 1.0
	fx.position = EISpace.pos(at.x, at.y, fx._height)
	w.add_child(fx)


## The authoritative teleport preflight runs at tick30, then enables motion.
static func teleport_result(w: GameWorld, event: Dictionary) -> void:
	for n in w.get_children():
		if n is SpellFx and n._light_id == String(event.get("id", "")):
			if event.get("cancel", false):
				n._life = mini(n._life, n._age + 1)
			elif event.get("ok", false):
				n._move_tick = 31
				n.advance(n._age)


func _ready() -> void:
	if _world == null:
		_height = position.y
	_light = OmniLight3D.new()
	_light.add_to_group(Gfx.POINT_LIGHT_GROUP)
	_light.light_color = light_color
	_light.omni_range = maxf(light_radius, 0.1)
	_light.light_energy = light_energy
	_light.visible = light_radius > 0.0
	Gfx.mark_additive(_light)   # native flag0x840
	_light.light_volumetric_fog_energy = Gfx.torch_fog_energy()
	_light.add_to_group(&"gfx_torch_glow")
	add_child(_light)
	if light_radius > 0.0:
		var halo := Gfx.torch_halo(light_radius, light_color)
		_light.add_child(halo)
		_local_light = {"light": _light, "kind": "spell", "until": -1,
			"pos": global_position, "energy": light_energy, "external_energy": true,
			"halo": halo.material_override}
		LocalLighting.prepare_particle(_local_light)
		_light.set_meta(&"ei_local_light", _local_light)
		_light.add_to_group(&"ei_local_spell")
	else:
		queue_free()


func _process(dt: float) -> void:
	if _world == null:
		_elapsed += dt   # explicit rendering probe
		advance(floori(_elapsed / GameUnit.TICK + 0.000001))
		return
	var age := _start_age + floori((_world.time - _start) / GameUnit.TICK + 0.000001)
	if not _world.authority:
		# Client world time advances on snapshots; interpolate between them.
		# This process inherits the world's pause/loading mode and time scale.
		_elapsed += dt
		age = maxi(age, _start_age + floori(_elapsed / GameUnit.TICK + 0.000001))
	advance(maxi(_age, age))


func advance(age: int) -> void:
	if age > _age and _bound_required and not is_instance_valid(Spells._deref(_bound)):
		_life = mini(_life, _age + 2)   # state3 on first tick, cleanup on next
	_age = maxi(age, _age)
	if _age >= _life:
		queue_free()
		return
	var steps := maxi(_age - maxi(_move_tick, 1) + 1, 0) if _move_tick >= 0 else 0
	while _steps < steps:
		_height = float(PackedFloat32Array([_height + _speed])[0])
		_steps += 1
	position.y = _height
	if not _local_light.is_empty():
		_local_light.pos = global_position
	# Native RGB/range stay constant; attenuation changes with position.
	if _local_light.get("enhanced", false):
		_local_light.halo.set_shader_parameter("strength", float(_local_light.halo_strength))
