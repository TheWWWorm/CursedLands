extends RefCounted
## camera/*.cam consists of 36-byte keys: time, an unused word, EI position,
## quaternion (w,x,y,z). This reads the first authored view without playing
## the track. The village view option is a remake addition.

static func first_pose(bytes: PackedByteArray) -> Variant:
	if bytes.size() < 36:
		return null
	for offset in range(8, 36, 4):
		if not is_finite(bytes.decode_float(offset)):
			return null
	var q := Quaternion(bytes.decode_float(24), bytes.decode_float(28),
		bytes.decode_float(32), bytes.decode_float(20))
	if q.length_squared() < 0.000001:
		return null
	q = q.normalized()
	var rot := EISpace.quat(q.w, q.x, q.y, q.z)
	var basis := Basis(rot * EISpace.vec(Vector3.RIGHT),
		rot * EISpace.vec(Vector3(0, -1, 0)), rot * EISpace.vec(Vector3(0, 0, -1)))
	return Transform3D(basis.orthonormalized(), EISpace.pos(bytes.decode_float(8),
		bytes.decode_float(12), bytes.decode_float(16)))

static func read_first(name: String) -> Variant:
	if name.is_empty() or name.contains("/") or name.contains("\\") or name.contains(".."):
		return null
	var path := GameData.root.path_join("camera/" + name + ".cam")
	return first_pose(GameFiles.read(path, 0, 36)) if GameFiles.exists(path) else null
