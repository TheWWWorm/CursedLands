class_name DetailedHead
extends RefCounted
## Remake option gfx_detailed_heads ("Portrait heads"; default on, off under
## "Original look"): a character's world figure wears its HUD face model in
## place of its own head. the original never does this: the bottom HUD draws the
## separately authored interface face "infa<race model><th|me|fa><hair + 1>face"
## (see Portrait) with its own 128² texture "face<m|f><skin>"
## while the figure draws the race model's "hd" part plus the hair variant
## "hr.<hair>" from the 256² body atlas.
## Measured (Zak, 2026-10-03): the two are equally detailed. Face 201
## triangles / ~18 200 texels on 0.33 m² (2.36 texels per cm); hd + hr.01
## 181 triangles / ~18 600 texels (2.45 / 2.57 per cm). The face texture is
## the same layout and painting as the atlas's head region, a little darker.
## The HUD face looks sharper because it is drawn unlit without mipmaps
## (Portrait), not because of its data.
##
## The interface face is one static part (no bones, no vertex morphs; the
## HUD's expressions are whole texture swaps a / b / c), head and hair in
## one mesh, about 5.7× the body head's size, looking along its +Y (Godot).
## It is fitted once per face model, race model and hair to the body's
## hd + hair meshes at complexion FIT_C (iterative closest points with a
## similarity transform: scale, pitch, offset), then stretched per axis
## with the unit's own hd box, so thin / fat / tall builds keep their head
## size. It is a child of the "hd" node, so it follows every animation,
## and SeveredLimb copies it with the rest of the head chain.
##
## Kept original: units without an interface face (creatures, orcs, most
## women: 8 of the 57 unhufe prototypes have a face texture), any worn helmet
## (the hd.armorNN meshes and the armoured hair variants are authored around
## the original hd; the face model's hair is part of its one mesh, so it
## would poke through), and the welded body (EIUnitModel.smooth_joints).

## Complexion the fit is computed at (the body head's shape varies with it;
## the result is mapped to the unit's head box afterwards).
const FIT_C := Vector3(0.5, 0.5, 0.5)
const ICP_STEPS := 12
## Correspondences beyond this fraction of the worst are dropped (hair cuts
## differ a little between the two models).
const TRIM := 0.8

## "fig|mask|hair" -> [Transform3D face -> hd at FIT_C, AABB of hd at FIT_C]
## or [] when the fit failed.
static var _fits := {}
## face figure -> ArrayMesh with the HUD atlas UVs mapped to the texture.
static var _meshes := {}
## texture (+ "|ui") -> material
static var _materials := {}
static var _surface: ImageTexture


## Interface face figure and texture for a character (Portrait.face_names,
## with the hair the body actually wears); empty when it has none.
static func face_names(proto: Dictionary, race: Dictionary, c: Vector3, hair: int) -> PackedStringArray:
	var model := String(race.get("mask", "")).to_lower()
	var sex: String = {"unhuma": "m", "unhufe": "f"}.get(model, "")
	if sex == "":
		return PackedStringArray()
	if c == Vector3.ZERO:
		c = GameUnit.proto_complexion(proto)
	var build := "th" if c.x < 0.2 else ("fa" if c.x > 0.8 else "me")
	var fig := "infa%s%s%dface" % [model, build, hair + 1]
	var tex := "face%s%02d" % [sex, int(proto.get("skin", 0))]
	var face_model := EIFigure.get_model(fig)
	if face_model.is_empty() or GameData.get_texture(tex) == null:
		return PackedStringArray()
	# Only the original interface-atlas heads support this replacement.
	# Lost in Astral supplies group-4 portrait meshes with different UVs
	# and proportions. They fit its custom portrait paintings, but not
	# the ordinary NPC faces or the world figure's head/neck attachment.
	# Keep the authored body head and hair for those models, including Kir.
	for part: Dictionary in face_model.parts.values():
		if part.get("texture_group", 0) != 8:
			return PackedStringArray()
	return PackedStringArray([fig, tex])


## Adds the face under `hd` (hidden; EIUnitModel.set_detailed_head shows it).
## `head_mesh` is the body's hd mesh at the unit's complexion. Returns the
## MeshInstance3D, or null when the face cannot be fitted.
static func attach(hd: Node3D, names: PackedStringArray, model: Dictionary, mask: String,
		hair_part: String, head_mesh: Mesh, ui_preview: bool) -> MeshInstance3D:
	var fit := _fit(names[0], model, mask, hair_part)
	if fit.is_empty() or head_mesh == null:
		return null
	var box0: AABB = fit[1]
	var box := head_mesh.get_aabb()
	if box0.size.x <= 0.0 or box0.size.y <= 0.0 or box0.size.z <= 0.0:
		return null
	# Per-axis stretch from the fitted build's head box to this unit's.
	var k := box.size / box0.size
	var stretch := Transform3D(Basis.from_scale(k), box.get_center() - box0.get_center() * k)
	var mi := MeshInstance3D.new()
	mi.name = "DetailedHead"
	mi.mesh = _mesh(names[0])
	mi.transform = stretch * (fit[0] as Transform3D)
	mi.material_override = _material(names[1], ui_preview)
	mi.set_meta("detailed_head", true)   # UnitWounds: the body atlas's wound layers do not fit it
	mi.visible = false
	hd.add_child(mi)
	return mi


## The face mesh with its UVs in the 128² texture: puts the
## face texture in a 256² atlas cell whose V starts at 0.5 (Portrait).
static func _mesh(fig: String) -> ArrayMesh:
	if _meshes.has(fig):
		return _meshes[fig]
	var src := EIFigure.build_mesh(EIFigure.get_model(fig).parts.values()[0], FIT_C)
	var mesh := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in uv.size():
			uv[i] = Vector2(uv[i].x * 2.0, uv[i].y * 2.0 - 1.0)
		arrays[Mesh.ARRAY_TEX_UV] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[fig] = mesh
	return mesh


## The world unit material (lighting, shadows, fog, selection highlight) with
## the face texture; skin surface response everywhere (gfx_materials).
static func _material(tex: String, ui_preview: bool) -> Material:
	var key := tex + ("|ui" if ui_preview else "")
	if _materials.has(key):
		return _materials[key]
	var m = EIUnitModel._material(ui_preview)
	m.albedo_texture = GameData.get_texture(tex)
	if m is EIUnitModel.LitMaterial:
		if _surface == null:
			var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			var s := EIUnitModel.SurfaceResponse.SKIN
			img.fill(Color(s.x, s.y, s.z))
			_surface = ImageTexture.create_from_image(img)
		m.set_shader_parameter("surface_tex", _surface)
	_materials[key] = m
	return m


static func clear_cache() -> void:
	_fits.clear()
	_meshes.clear()
	_materials.clear()
	_surface = null


# ------------------------------------------------------------------ fitting

static func _fit(fig: String, model: Dictionary, mask: String, hair_part: String) -> Array:
	var key := "%s|%s|%s" % [fig, mask, hair_part]
	if _fits.has(key):
		return _fits[key]
	var res := []
	var parts: Dictionary = model.parts
	var face_model := EIFigure.get_model(fig)
	if parts.has("hd") and not face_model.is_empty():
		var head := EIFigure.build_mesh(parts.hd, FIT_C)
		var dst := _points(head, Transform3D())
		if hair_part != "" and parts.has(hair_part):
			var hb: PackedFloat32Array = model.bones.get(hair_part, PackedFloat32Array())
			var off := EISpace.vec(EIFigure.bone_pos(hb, FIT_C)) if hb.size() >= 24 else Vector3.ZERO
			dst.append_array(_points(EIFigure.build_mesh(parts[hair_part], FIT_C), Transform3D(Basis(), off)))
		var src := _points(_mesh(fig), Transform3D())
		if dst.size() >= 4 and src.size() >= 4:
			res = [_icp(src, dst), head.get_aabb()]
	_fits[key] = res
	return res


## The distinct vertex positions of a mesh (the FIG components repeat them
## once per normal / UV).
static func _points(mesh: Mesh, xf: Transform3D) -> PackedVector3Array:
	var seen := {}
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var p := xf * v
			var k := p.snappedf(1e-5)
			if not seen.has(k):
				seen[k] = true
				out.append(p)
	return out


static func _box(p: PackedVector3Array, xf: Transform3D) -> AABB:
	var b := AABB(xf * p[0], Vector3.ZERO)
	for v in p:
		b = b.expand(xf * v)
	return b


## Similarity transform taking `src` (face) onto `dst` (body head and hair):
## a start from the boxes, the face turned upright (it looks along its +Y in
## the HUD, the body along +Z) and tipped 5° forward, then ICP steps with
## closest points both ways and Horn's closed-form fit.
static func _icp(src: PackedVector3Array, dst: PackedVector3Array) -> Transform3D:
	var r0 := Basis(Vector3.RIGHT, deg_to_rad(-5.0)) * Basis(Vector3.RIGHT, PI * 0.5)
	var bs := _box(src, Transform3D(r0, Vector3.ZERO))
	var bd := _box(dst, Transform3D())
	var ratio := bd.size / bs.size
	var s0 := (ratio.x + ratio.y + ratio.z) / 3.0
	var xf := Transform3D(r0.scaled(Vector3.ONE * s0), bd.get_center() - bs.get_center() * s0)
	var cur := PackedVector3Array()
	cur.resize(src.size())
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var d := PackedFloat32Array()
	for step in ICP_STEPS:
		for i in src.size():
			cur[i] = xf * src[i]
		a.clear()
		b.clear()
		d.clear()
		for i in cur.size():
			var j := _nearest(cur[i], dst)
			a.append(src[i])
			b.append(dst[j])
			d.append(cur[i].distance_squared_to(dst[j]))
		for j in dst.size():
			var i := _nearest(dst[j], cur)
			a.append(src[i])
			b.append(dst[j])
			d.append(cur[i].distance_squared_to(dst[j]))
		var sorted := d.duplicate()
		sorted.sort()
		var limit := sorted[mini(sorted.size() - 1, int(sorted.size() * TRIM))]
		var fa := PackedVector3Array()
		var fb := PackedVector3Array()
		for i in a.size():
			if d[i] <= limit:
				fa.append(a[i])
				fb.append(b[i])
		xf = _horn(fa, fb)
	return xf


static func _nearest(p: Vector3, q: PackedVector3Array) -> int:
	var best := 0
	var bd := INF
	for i in q.size():
		var dd := p.distance_squared_to(q[i])
		if dd < bd:
			bd = dd
			best = i
	return best


## Horn (1987): the rotation is the dominant eigenvector of the 4×4 matrix of
## the cross-covariance (power iteration on a shifted, positive matrix),
## reduced to its pitch; the scale the ratio of projected spreads.
static func _horn(a: PackedVector3Array, b: PackedVector3Array) -> Transform3D:
	var n := a.size()
	var ca := Vector3.ZERO
	var cb := Vector3.ZERO
	for i in n:
		ca += a[i]
		cb += b[i]
	ca /= n
	cb /= n
	var sxx := 0.0; var sxy := 0.0; var sxz := 0.0
	var syx := 0.0; var syy := 0.0; var syz := 0.0
	var szx := 0.0; var szy := 0.0; var szz := 0.0
	var spread := 0.0
	for i in n:
		var p := a[i] - ca
		var q := b[i] - cb
		sxx += p.x * q.x; sxy += p.x * q.y; sxz += p.x * q.z
		syx += p.y * q.x; syy += p.y * q.y; syz += p.y * q.z
		szx += p.z * q.x; szy += p.z * q.y; szz += p.z * q.z
		spread += p.length_squared()
	var m := [
		[sxx + syy + szz, syz - szy, szx - sxz, sxy - syx],
		[syz - szy, sxx - syy - szz, sxy + syx, szx + sxz],
		[szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy],
		[sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz]]
	var shift := 0.0
	for r in 4:
		for c in 4:
			shift += absf(m[r][c])
	for r in 4:
		m[r][r] += shift
	var v := [1.0, 0.0, 0.0, 0.0]
	for it in 100:
		var w := [0.0, 0.0, 0.0, 0.0]
		var len := 0.0
		for r in 4:
			for c in 4:
				w[r] += m[r][c] * v[c]
			len += w[r] * w[r]
		len = sqrt(len)
		for r in 4:
			v[r] = w[r] / len
	var rot := Basis(Quaternion(v[1], v[2], v[3], v[0]).normalized())
	# Both heads are mirror-symmetric about x = 0: only the pitch is kept
	# (a free fit turns the face a few degrees after the asymmetric hair).
	rot = Basis(Vector3.RIGHT, rot.get_euler().x)
	var num := 0.0
	for i in n:
		num += (b[i] - cb).dot(rot * (a[i] - ca))
	var s := num / spread if spread > 0.0 else 1.0
	var basis := rot.scaled(Vector3.ONE * s)
	return Transform3D(basis, cb - basis * ca)
