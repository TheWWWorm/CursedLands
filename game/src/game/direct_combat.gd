class_name DirectCombat
extends RefCounted
## Experimental attacks use authoritative geometry at impact, rather than a
## target selected at button-down. The ordinary order/combat rules are intact.
## Coordinates here are Godot world coordinates; simulation poses, not drawn
## client interpolation, determine contact. Navigation spans exist in workers.

static func origin(u: GameUnit) -> Vector3:
	return Vector3(u.pos.x, u.world.ground_at(u.pos.x, u.pos.y) + maxf(0.3, u.figure_half_z * 1.4), -u.pos.y)


static func point_clear(w: GameWorld, p: Vector3, margin := 0.0) -> bool:
	var xy := Vector2(p.x, -p.z)
	if p.y <= w.ground_at(xy.x, xy.y) + margin: return false
	var nav := w.nav
	if nav == null or nav.size.x == 0: return true
	var c := nav.cell(xy)
	if not nav._in(c): return false
	for span: Array in nav._spans.get(c.y * nav.size.x + c.x, []):
		# Foliage attenuates sight but is not a solid wall.
		if int(span[2]) == 2: continue
		if (p.y + margin) * nav._alt >= float(span[0]) and (p.y - margin) * nav._alt <= float(span[1]):
			return false
	return true


## A short sweep in the original navigation geometry. Includes the endpoint,
## unlike a sight ray rounded to half-metre steps. Moving floors/doors update
## these same spans, so there is no second scenery cache to go stale.
static func scene_fraction(w: GameWorld, a: Vector3, b: Vector3, margin := 0.0) -> float:
	var n := maxi(1, ceili(a.distance_to(b) / 0.2))
	for i in range(1, n + 1):
		var f := float(i) / n
		var p := a.lerp(b, f)
		if not point_clear(w, p, margin): return float(i - 1) / n
		if margin > 0.0:
			for offset: Vector3 in [Vector3(margin,0,0), Vector3(-margin,0,0), Vector3(0,0,margin), Vector3(0,0,-margin)]:
				if not point_clear(w, p + offset, margin): return float(i - 1) / n
	return 1.0


## First intersection with a body's vertical cylinder, including its caps.
static func body_fraction(a: Vector3, b: Vector3, foot: Vector3, radius: float, height: float) -> float:
	var delta := b - a
	var offset := a - foot
	var lo := 0.0
	var hi := 1.0
	if absf(delta.y) < 0.00001:
		if offset.y < 0.0 or offset.y > height: return INF
	else:
		var f0 := -offset.y / delta.y
		var f1 := (height - offset.y) / delta.y
		lo = maxf(lo, minf(f0, f1)); hi = minf(hi, maxf(f0, f1))
	var aa := delta.x * delta.x + delta.z * delta.z
	var cc := offset.x * offset.x + offset.z * offset.z - radius * radius
	if aa < 0.00001:
		if cc > 0.0: return INF
	else:
		var bb := offset.x * delta.x + offset.z * delta.z
		var disc := bb * bb - aa * cc
		if disc < 0.0: return INF
		lo = maxf(lo, (-bb - sqrt(disc)) / aa)
		hi = minf(hi, (-bb + sqrt(disc)) / aa)
	return lo if lo <= hi else INF


static func ray_body(w: GameWorld, source: GameUnit, a: Vector3, b: Vector3, max_fraction := 1.0) -> Dictionary:
	var best := max_fraction
	var found: GameUnit
	var centre := Vector2((a.x+b.x)*0.5, -(a.z+b.z)*0.5)
	for u: GameUnit in w.live_units_near(centre, a.distance_to(b)*0.5 + 3.0):
		if u == source or u.dead or u.hidden: continue
		var foot := Vector3(u.pos.x, w.ground_at(u.pos.x,u.pos.y), -u.pos.y)
		var f := body_fraction(a,b,foot,maxf(0.15,u.body_radius()),maxf(0.3,u.figure_half_z*2.0))
		if f < best:
			found = u; best = f
	return {"unit":found,"fraction":best}


static func melee_target(u: GameUnit, direction: Vector3) -> GameUnit:
	var forward := Vector2(direction.x, -direction.z).normalized()
	var best := INF
	var found: GameUnit
	var a := origin(u)
	for t: GameUnit in u.world.live_units_near(u.pos, u.body_radius() + maxf(0.6,float(u.stats.get("range",0.0))) + 2.0):
		if t == u or t.dead or t.hidden: continue
		var offset := t.pos - u.pos
		var d := offset.length()
		if d > u.melee_reach(t) or not u._melee_height_clear(t): continue
		# A modest weapon arc, expanded by the target's actual radius.
		if offset.dot(forward) < 0.0 or absf(offset.cross(forward)) > t.body_radius() + d * 0.35: continue
		var b := origin(t)
		var aimed_y := a.y + direction.y * d / maxf(Vector2(direction.x,direction.z).length(),0.1)
		var floor_y := u.world.ground_at(t.pos.x,t.pos.y)
		if aimed_y < floor_y - 0.2 or aimed_y > floor_y + t.figure_half_z*2.0 + 0.2: continue
		if d < best and scene_fraction(u.world,a,b) == 1.0:
			found = t; best = d
	return found


static func contact(u: GameUnit, t: GameUnit, carried := {}) -> void:
	# A geometric hit connects in this mode. Damage, armour, wounds, equipment
	# wear and backstab still use Combat; no client supplies damage or a victim.
	var backstab: bool = u.has_meta("hero") and not u.stats.get("ranged",false) and not t.alert \
		and Vector2.from_angle(t.facing).dot((t.pos-u.pos).normalized()) > 0.5
	var record: Dictionary = carried.duplicate()
	record.merge({"hit":true,"backstab":backstab},true)
	u.world.on_attack(u,t)
	u.world.combat.melee(u,t,record)
	u.world.combat.weapon_spell(u,t)
