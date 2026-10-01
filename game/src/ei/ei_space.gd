class_name EISpace
extends RefCounted
## Evil Islands uses Z-up coordinates; Godot is Y-up.
## EI (x, y, z) maps to Godot (x, z, -y), a proper rotation, so triangle
## handedness and quaternions carry over without mirroring.


static func pos(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func vec(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## EI stores quaternions as (w, x, y, z).
static func quat(w: float, x: float, y: float, z: float) -> Quaternion:
	var q := Quaternion(x, z, -y, w)
	return q.normalized() if q.length_squared() > 0.000001 else Quaternion.IDENTITY
