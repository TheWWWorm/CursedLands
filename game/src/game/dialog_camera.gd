class_name DialogCamera
extends RefCounted
## Conversation camera shots, the original (presets) and
## (placement). Actors: a = the partner, b = the second actor (the hero),
## c = the third (Briefings.cast). A unit shot looks at the unit's point
## "dialog cam distance" ahead of it at its "dialog cam height" (prototype
## columns) from `dist` metres in front of it, turned by `angle`, `h` metres
## higher. A two-shot looks at the middle between a and b from the side at a
## multiple of their distance.
## Positions: the original stages the actors at the conversation's
## start and keeps their places (b, a, c) and the
## directions b→a, a→b and c→middle (z 0
## normalised); reads only these, never the moving units, so a
## partner still walking to its place does not drag the camera along. The
## remake's places are the cast's "at" (Briefings._face); a unit's own
## position only when "at" is missing. Optional "at_z" retains the original
## full3D stage height; older casts use the ground under the place.
## The original sets eye and target without an obstacle test. The remake
## retains a clear authored shot, otherwise tries nearby unobstructed angles.

## preset -> [who, angle (rad), distance (x a-b distance for "two"), height]
const PRESETS := {
	1: ["two", 0.0, 3.0, 1.5], 2: ["a", -0.5236, 4.0, 1.5], 3: ["b", 0.5236, 4.0, 1.5], 4: ["c", 0.0, 4.0, 1.5],
	5: ["two", 0.2618, 2.7, 3.0], 6: ["a", -0.7854, 3.5, 3.0], 7: ["b", 0.7854, 3.5, 3.0], 8: ["c", 0.2618, 3.5, 3.0],
	9: ["two", -0.2618, 2.4, 3.0], 10: ["a", -0.2618, 3.0, 1.0], 11: ["b", 0.2618, 3.0, 1.0], 12: ["c", -0.2618, 3.0, 1.0],
}

## Actors a preset takes out of view ((actor
## -100) on them; the dialog screenshots show only the shot's actor).
const HIDE := {2: ["b"], 3: ["a"], 6: ["b"], 7: ["a"], 12: ["b", "a"]}


## [eye, target, actors to hide] in EI coordinates (z up) for a phrase, or [] if the actors
## are missing. `first` = the conversation's first phrase (camera 1 then).
static func shot(w: GameWorld, cast: Dictionary, phrase: Dictionary, first: bool) -> Array:
	var a: GameUnit = w.units.get(int(cast.get("a", -1)))
	if a == null:
		return []
	var b: GameUnit = w.units.get(int(cast.get("b", -1)))
	var c: GameUnit = w.units.get(int(cast.get("c", -1)))
	var n := int(phrase.get("camera", -1))
	var args: Array = phrase.get("cam_args", [])
	var speaker: int = int(Dictionary(cast.get("names", {})).get(String(phrase.get("actor", "")), -1))
	if not args.is_empty():
		# "#camera N angle distance height": N 2 / 3 / 4 = a / b / c, else the two-shot.
		var who := {2: "a", 3: "b", 4: "c"}.get(n, "two") as String
		return _clear_shot(w, _place(w, a, b, c, who, deg_to_rad(float(args[0])), float(args[1]), float(args[2]), false, cast.get("at", {}), cast.get("at_z", {}))) + [[]]
	if n < 1:
		n = 1 if first else 2 if speaker == a.uid else 4 if c and speaker == c.uid else 3
	var p: Array = PRESETS.get(n, PRESETS[1])
	var out := _place(w, a, b, c, p[0], p[1], p[2], p[3], p[0] == "two", cast.get("at", {}), cast.get("at_z", {}))
	out = _clear_shot(w, out)
	out.append(HIDE.get(n, []))
	return out


## Snapshot only nearby scenery for this phrase. Exact triangles keep open
## doors, arches and gaps usable; a large building's bounding box alone must
## not disqualify a shot. Native triangle trees are shared by Mesh, so moving
## lifts and doors cannot leave stale world-space triangles between phrases.
static func _clear_shot(w: GameWorld, shot: Array) -> Array:
	if shot.size() < 2: return shot
	var eye: Vector3 = shot[0]
	var target: Vector3 = shot[1]
	var meshes := []
	var seen := {}
	var objects: Array = w.objects.values()
	if w.map: objects.append_array(w.map.object_nodes)
	var centre := EISpace.vec(target)
	var reach := eye.distance_to(target) + 4.0
	for object in objects:
		if not is_instance_valid(object) or not object is Node3D or not object.is_visible_in_tree(): continue
		if seen.has(object.get_instance_id()): continue
		seen[object.get_instance_id()] = true
		for child: Node in object.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
			var box := mesh.global_transform * mesh.get_aabb()
			if box.get_center().distance_to(centre) > reach + box.size.length() * 0.5: continue
			meshes.append({"mesh":mesh.mesh,"box":box,"inverse":mesh.global_transform.affine_inverse()})
	if _clear(w, meshes, eye, target): return shot
	var delta := eye - target
	# Preserve the authored target and try the smallest angular changes first.
	# A closer camera is the fallback for enclosed spaces.
	for scale: float in [1.0, 0.75, 0.5]:
		for lift: float in [0.0, 1.0, 2.0]:
			for angle: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
				var offset := Vector2(delta.x, delta.y).rotated(deg_to_rad(angle)) * scale
				var candidate := target + Vector3(offset.x, offset.y, delta.z * scale + lift)
				if _clear(w, meshes, candidate, target): return [candidate, target]
	return shot


static func _clear(w: GameWorld, meshes: Array, eye: Vector3, target: Vector3) -> bool:
	if eye.z < w.ground_at(eye.x, eye.y) + 0.3: return false
	# Probe the focal area, not only its centre: thin posts can hide a face.
	var side := Vector2(eye.y-target.y, target.x-eye.x).normalized() * 0.18
	var a := EISpace.vec(eye)
	for offset: Vector3 in [Vector3.ZERO, Vector3(side.x,side.y,0.35), Vector3(-side.x,-side.y,0.35)]:
		var b := EISpace.vec(target + offset)
		if w.terrain:
			var distance := eye.distance_to(target+offset)
			var steps := maxi(1, ceili(distance/0.4))
			for i in range(1,steps):
				var point := eye.lerp(target+offset,float(i)/steps)
				if point.z < w.ground_at(point.x,point.y)+0.05: return false
		for row: Dictionary in meshes:
			if (row.box as AABB).intersects_segment(a,b)==null: continue
			var triangles := (row.mesh as Mesh).generate_triangle_mesh()
			var inverse: Transform3D = row.inverse
			if triangles and not triangles.intersect_segment(inverse*a,inverse*b).is_empty(): return false
	return true


static func _place(w: GameWorld, a: GameUnit, b: GameUnit, c: GameUnit, who: String, angle: float,
		dist: float, h: float, relative: bool, at := {}, at_z := {}) -> Array:
	var pa: Vector2 = _at(at, "a", a)
	var pb: Vector2 = _at(at, "b", b) if b else Vector2.ZERO
	var pc: Vector2 = _at(at, "c", c) if c else Vector2.ZERO
	var target: Vector3
	var dir: Vector2
	if who == "two" or (who == "b" and b == null) or (who == "c" and c == null):
		if b == null:
			who = "a"
		else:
			var mid := (pa + pb) * 0.5
			target = Vector3(mid.x, mid.y, (_height(w, at_z, "a", pa) + _height(w, at_z, "b", pb)) * 0.5)
			dir = Vector2(pa.y - pb.y, pb.x - pa.x)
			if relative:
				dist *= pa.distance_to(pb)
	if who != "two":
		var u: GameUnit = {"a": a, "b": b, "c": c}[who]
		if u == null:
			u = a
		var pu := pa
		if u == a and b:
			dir = pb - pa
		elif u == b:
			pu = pb
			dir = pa - pb
		elif u == c:
			pu = pc
			dir = (pa + pb) * 0.5 - pc
		else:
			dir = Vector2.from_angle(u.facing)
		dir = dir.normalized()
		var p := pu + dir * float(u.proto.get("dialog_cam_distance", 0.0))
		target = Vector3(p.x, p.y, _height(w, at_z, who, pu) + float(u.proto.get("dialog_cam_height", 1.5)))
	dir = dir.normalized()
	var cs := cos(angle)
	var sn := sin(angle)
	var off := Vector2(dir.x * cs + dir.y * sn, dir.y * cs - dir.x * sn) * dist
	return [Vector3(target.x + off.x, target.y + off.y, target.z + h), target]


static func _at(at: Dictionary, k: String, u: GameUnit) -> Vector2:
	var v: Array = at.get(k, [])
	return Vector2(float(v[0]), float(v[1])) if v.size() == 2 else u.pos


static func _height(w: GameWorld, at_z: Dictionary, k: String, p: Vector2) -> float:
	var z: Variant = at_z.get(k)
	if (z is float or z is int) and is_finite(float(z)):
		return float(z)
	return w.ground_at(p.x, p.y)
