class_name EIFigureGeometry
extends RefCounted
## The FIG header geometry, in EI space. Its boxes are relative to the
## authored centre; its radius is authored separately from the vertices.

const META := &"ei_figure_geometry"
const PARTS := &"ei_figure_parts"


static func _f(v: float) -> float:
	return PackedFloat32Array([v])[0]


static func _v(a: PackedFloat32Array, p: int) -> Vector3:
	return Vector3(a[p], a[p + 1], a[p + 2])


static func _blend(a: PackedFloat32Array, p: int, c: Vector3) -> Vector3:
	# The native vector helpers store their subtract / multiply / add results
	# as floats. Vector3 preserves those stores, unlike scalar double lerp.
	var lo := (_v(a, p + 3) - _v(a, p)) * c.y + _v(a, p)
	var hi := (_v(a, p + 9) - _v(a, p + 6)) * c.y + _v(a, p + 6)
	var low := (hi - lo) * c.x + lo
	lo = (_v(a, p + 15) - _v(a, p + 12)) * c.y + _v(a, p + 12)
	hi = (_v(a, p + 21) - _v(a, p + 18)) * c.y + _v(a, p + 18)
	var high := (hi - lo) * c.x + lo
	return (high - low) * c.z + low


## . Complexion is deliberately not clamped.
static func from_figure(fig: Dictionary, c: Vector3) -> Dictionary:
	var n := int(fig.get("n", 0))
	var data: PackedByteArray = fig.get("data", PackedByteArray())
	if n < 1 or data.size() < 40 + n * 40:
		return {}
	var a := data.slice(40, 40 + n * 40).to_float32_array()
	if n != 8:
		return {"centre": _v(a, 0), "min": _v(a, 3), "max": _v(a, 6), "radius": a[9], "flags": 3}
	# The scalar radius routine keeps the upper interpolation in x87 and
	# stores only its lower half and final result as floats.
	var lo := _f(lerpf(lerpf(a[72], a[73], c.y), lerpf(a[74], a[75], c.y), c.x))
	var hi := lerpf(lerpf(a[76], a[77], c.y), lerpf(a[78], a[79], c.y), c.x)
	return {"centre": _blend(a, 0, c), "min": _blend(a, 24, c), "max": _blend(a, 48, c),
		"radius": _f(lerpf(lo, hi, c.z)), "flags": 3}


static func attach(node: Node3D, figure: Dictionary, complexion: Vector3, parts: Array[WeakRef]) -> void:
	var geometry := from_figure(figure, complexion)
	if not geometry.is_empty():
		node.set_meta(META, geometry)
		parts.append(weakref(node))


## pose origins plus raw boxes, without rotating the boxes.
## Auxiliary parts contribute at origin zero. A saved box is kept when the
## native part lists are empty (e.g. a carrier without a figure).
static func combine(parts: Array, extras: Array = [], saved: Dictionary = {}) -> Dictionary:
	if parts.is_empty() and extras.is_empty():
		return saved.duplicate() if not saved.is_empty() else {"centre": Vector3.ZERO,
			"min": Vector3.ZERO, "max": Vector3.ZERO, "radius": 0.0, "flags": 0}
	var lo := Vector3(3.402823466e38, 3.402823466e38, 3.402823466e38)
	var hi := -lo
	for auxiliary in [false, true]:
		for part: Dictionary in extras if auxiliary else parts:
			var pos: Vector3 = Vector3.ZERO if auxiliary else part.position
			if not auxiliary and float(pos.x) * pos.x + float(pos.y) * pos.y + float(pos.z) * pos.z > 1.0e9:
				continue
			var g: Dictionary = part.geometry
			var centre: Vector3 = g.centre
			var bmin: Vector3 = g.min
			var bmax: Vector3 = g.max
			# Native sums are rounded only when written to the bound locals.
			var pmin := Vector3(float(bmin.x) + pos.x + centre.x, float(bmin.y) + pos.y + centre.y,
				float(bmin.z) + pos.z + centre.z)
			var pmax := Vector3(float(bmax.x) + pos.x + centre.x, float(bmax.y) + pos.y + centre.y,
				float(bmax.z) + pos.z + centre.z)
			lo = lo.min(pmin)
			hi = hi.max(pmax)
	var centre := (lo + hi) * 0.5
	lo -= centre
	hi -= centre
	return {"centre": centre, "min": lo, "max": hi,
		"radius": _f(sqrt(float(lo.x) * lo.x + float(lo.y) * lo.y + float(lo.z) * lo.z)), "flags": 3}


## Current part positions in the unit/model's own space. Metadata stays on
## the authored parts even when optional head or joint renderers replace them.
static func of(model: Node3D) -> Dictionary:
	if not is_instance_valid(model) or not model.has_meta(PARTS):
		return {}
	var parts: Array = []
	var inside := model.is_inside_tree()
	var inv := model.global_transform.affine_inverse() if inside else Transform3D.IDENTITY
	for ref: WeakRef in model.get_meta(PARTS):
		var node = ref.get_ref()
		if not is_instance_valid(node) or not node is Node3D or not model.is_ancestor_of(node):
			continue
		var p: Vector3
		if inside:
			p = inv * node.global_position
		else:
			# Unit setup measures figures before adding them to the tree.
			# Compose the authored pose without requesting global transforms.
			var relative: Transform3D = node.transform
			var parent: Node3D = node.get_parent_node_3d()
			while parent and parent != model:
				relative = parent.transform * relative
				parent = parent.get_parent_node_3d()
			p = relative.origin
		parts.append({"position": Vector3(p.x, -p.z, p.y), "geometry": node.get_meta(META)})
	return combine(parts)


static func box(g: Dictionary) -> AABB:
	var lo: Vector3 = g.centre + g.min
	var hi: Vector3 = g.centre + g.max
	var a := EISpace.vec(lo)
	var b := EISpace.vec(hi)
	return AABB(a.min(b), (b - a).abs())


## . A missing carrier has offset zero and radius 0.1.
static func carrier(g: Dictionary) -> Vector2:
	if g.is_empty():
		return Vector2(0.0, 0.1)
	var radius: float = g.radius
	if int(g.get("flags", 0)) & 1 == 0:
		var v: Vector3 = g.max - g.min
		radius = _f(sqrt(float(v.x) * v.x + float(v.y) * v.y + float(v.z) * v.z) * 0.5)
	return Vector2(g.centre.z, radius)
