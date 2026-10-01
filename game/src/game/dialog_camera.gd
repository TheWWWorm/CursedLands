class_name DialogCamera
extends RefCounted
## Conversation camera shots, the original (presets) and
## (placement). Actors: a = the partner, b = the second actor (the hero),
## c = the third (Briefings.cast). A unit shot looks at the unit's point
## "dialog cam distance" ahead of it at its "dialog cam height" (prototype
## columns) from `dist` metres in front of it, turned by `angle`, `h` metres
## higher. A two-shot looks at the middle between a and b from the side at a
## multiple of their distance.

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
		return _place(w, a, b, c, who, deg_to_rad(float(args[0])), float(args[1]), float(args[2]), false) + [[]]
	if n < 1:
		n = 1 if first else 2 if speaker == a.uid else 4 if c and speaker == c.uid else 3
	var p: Array = PRESETS.get(n, PRESETS[1])
	var out := _place(w, a, b, c, p[0], p[1], p[2], p[3], p[0] == "two")
	out.append(HIDE.get(n, []))
	return out


static func _place(w: GameWorld, a: GameUnit, b: GameUnit, c: GameUnit, who: String, angle: float,
		dist: float, h: float, relative: bool) -> Array:
	var target: Vector3
	var dir: Vector2
	if who == "two" or (who == "b" and b == null) or (who == "c" and c == null):
		if b == null:
			who = "a"
		else:
			var mid := (a.pos + b.pos) * 0.5
			target = Vector3(mid.x, mid.y, (w.ground_at(a.pos.x, a.pos.y) + w.ground_at(b.pos.x, b.pos.y)) * 0.5)
			dir = Vector2(a.pos.y - b.pos.y, b.pos.x - a.pos.x)
			if relative:
				dist *= a.pos.distance_to(b.pos)
	if who != "two":
		var u: GameUnit = {"a": a, "b": b, "c": c}[who]
		if u == null:
			u = a
		if u == a and b:
			dir = b.pos - a.pos
		elif u == b:
			dir = a.pos - b.pos
		elif u == c:
			dir = (a.pos + b.pos) * 0.5 - c.pos
		else:
			dir = Vector2.from_angle(u.facing)
		dir = dir.normalized()
		var p := u.pos + dir * float(u.proto.get("dialog_cam_distance", 0.0))
		target = Vector3(p.x, p.y, w.ground_at(u.pos.x, u.pos.y) + float(u.proto.get("dialog_cam_height", 1.5)))
	dir = dir.normalized()
	var cs := cos(angle)
	var sn := sin(angle)
	var off := Vector2(dir.x * cs + dir.y * sn, dir.y * cs - dir.x * sn) * dist
	return [Vector3(target.x + off.x, target.y + off.y, target.z + h), target]
