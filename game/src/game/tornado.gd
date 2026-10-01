class_name Tornadoes
extends RefCounted
## The tornadoes of a "#weather tornado" zone (Suslanger gz15h, gz17h, gz18h,
## gz19h), the original CEffectTornado (class 0x65). Host only
## each tornado goes to the peers as a "tornado" event (the original streams the
## same four fields,: position, step, life, start tick) and the
## clients move its sound themselves (Weather.on_tornado).
##
## Spawn (server, the weather run every 64 world ticks
## (tick & 0x3f) == 3, only in a game zone, world weather == 3): a point
## x, y = random · 2⁻²³ (0..512 m), z 0, whose AI map cell has ground type 1
## or 3 and no water; a step dx, dy = random ·
## 140 / 2³² − 70 each, longer than 30 m (dx² + dy² > 900); the line to
## there must have no height step of 1 m or more between successive 0.5 m
## cells (< 1). Then: speed 0.096 + 0.12 · random
## · 9.3132e-11 (0.096..0.144 m per tick), step = the direction · speed,
## life = round(distance / speed) ticks, start tick = now.
## Update (every world tick): position += step; on the server
## while life > 20 and life % 8 == 0, every unit within 5 m (2D,
## ) that belongs to a player takes the hit record
## {type 6 factor 1, to-hit 100, damage 5, armour factor 1, part 1 (torso)}
## through its logic's hit (=, no attacker); then
## life −= 1 and the tornado is removed below 0.
## Saved with the zone (the original keeps them among the world's saved objects
##  stream slot; loaded
## ): `save_state` / the world meta
## "restored_tornado".
## Approx.: the remake's randoms are Godot's, not the original's table

const RUN_MASK := 0x3f
const RUN_AT := 3
const HIT_RADIUS := 5.0
##  hit record: damage-type factors (type 6), to-hit, damage
## armour factor, body part.
const HIT_TYPES := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0]
const HIT_TO_HIT := 100.0
const HIT_DAMAGE := 5.0
const HIT_PART := 1

var world: GameWorld
var on := false
var _tick := 0
var _next_id := 1
## id -> {p: Vector3, v: Vector3, life: int}
var list := {}


func _init(w: GameWorld) -> void:
	world = w
	on = String(w.zone.get("weather", "")).to_lower() == "tornado" if w.zone else false
	if w.has_meta("restored_tornado"):
		for r: Array in w.get_meta("restored_tornado"):
			_add(Vector3(r[0], r[1], 0.0), Vector3(r[2], r[3], 0.0), int(r[4]))
		w.remove_meta("restored_tornado")


## [x, y, vx, vy, life] per running tornado.
func save_state() -> Array:
	var out := []
	for t: Dictionary in list.values():
		out.append([t.p.x, t.p.y, t.v.x, t.v.y, t.life])
	return out


## Host, every 55 ms world tick.
func tick() -> void:
	_tick += 1
	if not on and list.is_empty():
		return
	if on and (_tick & RUN_MASK) == RUN_AT and String(world.zone.get("type", "")) == "game":
		_spawn()
	for id in list.keys():
		var t: Dictionary = list[id]
		t.p += t.v
		if t.life > 20 and (t.life & 7) == 0:
			_hit(Vector2(t.p.x, t.p.y))
		t.life -= 1
		if t.life < 0:
			list.erase(id)


func _spawn() -> void:
	var nav := world.nav
	if nav == null:
		return
	var p := Vector2(randi() / 8388608.0, randi() / 8388608.0)
	var g := nav.cell_ground(p)
	if (g != 3 and g != 1) or nav.cell_wet(p):
		return
	var d := Vector2(randi() * 3.259629011913116e-08 - 70.0, randi() * 3.259629011913116e-08 - 70.0)
	if d.length_squared() <= 900.0:
		return
	if nav.max_step(p, p + d) >= 1.0:
		return
	var speed := randi() * 9.313226580990458e-11 * 0.12 + 0.096
	var dist := d.length()
	_add(Vector3(p.x, p.y, 0.0), Vector3(d.x, d.y, 0.0) * (speed / dist), maxi(roundi(dist / speed), 0))


func _add(p: Vector3, v: Vector3, life: int) -> void:
	var t := {"p": p, "v": v, "life": life}
	var id := _next_id
	_next_id += 1
	list[id] = t
	if world.session:
		world.session.broadcast({"t": "tornado", "id": id, "x": t.p.x, "y": t.p.y,
			"vx": t.v.x, "vy": t.v.y, "life": t.life})


func _hit(at: Vector2) -> void:
	for u: GameUnit in world.live_units_near(at, HIT_RADIUS):
		if u.dead or u.controller < 0 or u.pos.distance_squared_to(at) >= HIT_RADIUS * HIT_RADIUS:
			continue
		world.combat.record_hit(u, PackedFloat32Array(HIT_TYPES), HIT_TO_HIT, HIT_DAMAGE, HIT_PART)
