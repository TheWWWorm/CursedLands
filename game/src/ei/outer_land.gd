class_name EIOuterLand
extends Node3D
## Outer landscape (remake-only option gfx_outer_land; the original ends the
## map over the clear colour, hidden by its fog). A low-detail ring of land
## around the map, REACH metres wide: the edge heights continued outward,
## smoothed along the edge more the farther out, plus a little noise that
## grows from zero at the seam. Each cell repeats the texture tile of the
## nearest edge tile; where the edge has liquid, a flat sheet of that liquid
## (same material, level and texture) continues too. Drawn with the terrain's
## own materials, so lighting and the view-depth fog are the same and the ring
## melts into the sky at the far plane. Two meshes; the play area is untouched.

const REACH := 300.0     # metres beyond the edge
const RINGS := 24        # rows of cells outward, widening (first ~2 m, last ~20 m)
const STEP := 1.0        # along the edge: the map's own vertex spacing (no cracks)
const SEAM_SMOOTH := 0.7 # edge smoothing window per metre of distance
const NOISE_RAMP := 50.0 # metres over which the noise grows in
## Every map's two outermost vertex rows drop to height 0 (a cliff around the
## map, land and liquid alike), so the ring is seamed to vertex row INSET and
## covers that cliff; the map's own liquid there is not drawn while the ring is
## on (water shaders, `outer_edge`). Outer liquid cells carry material + 64.
const INSET := 2.0
const OUTER_MAT := 64


static func build(t: EITerrain, land_mat: Material, water_mat: Material) -> EIOuterLand:
	var o := EIOuterLand.new()
	o.name = "OuterLand"
	o._build(t, land_mat, water_mat)
	return o


func _build(t: EITerrain, land_mat: Material, water_mat: Material) -> void:
	var size := t.size_ei()
	var w := size.x
	var h := size.y
	var xs := _axis(w)
	var ys := _axis(h)
	var iw := w - 2.0 * INSET   # the inset rectangle the ring starts from
	var ih := h - 2.0 * INSET
	var nx := xs.size()
	var ny := ys.size()
	# Edge heights around the perimeter at 1 m, with prefix sums for smoothing.
	var per := int(2.0 * (iw + ih))
	var pre := PackedFloat64Array()
	pre.resize(per + 1)
	var lo := INF
	var hi := -INF
	for k in per:
		var e := _perimeter_point(float(k), iw, ih) + Vector2(INSET, INSET)
		var z := t.height_at(e.x, e.y)
		lo = minf(lo, z)
		hi = maxf(hi, z)
		pre[k + 1] = pre[k] + z
	var amp := clampf((hi - lo) * 0.15, 1.5, 12.0)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = t.map_name.hash()
	noise.frequency = 1.0 / 70.0
	noise.fractal_octaves = 3
	# Heights on the axis grid (EI z); interior vertices are never used.
	var hz := PackedFloat32Array()
	hz.resize(nx * ny)
	var pxy := PackedVector2Array()   # vertex EI xy (seam: the map's own, jitter included)
	pxy.resize(nx * ny)
	var seam := PackedInt32Array()    # map grid vertex index on the seam, else -1
	seam.resize(nx * ny)
	seam.fill(-1)
	var vcol := PackedColorArray()
	vcol.resize(nx * ny)
	vcol.fill(Color(0, 0, 0, 0))
	var cells_w := int(w)
	for j in ny:
		for i in nx:
			var x := xs[i]
			var y := ys[j]
			var c := Vector2(clampf(x, INSET, w - INSET), clampf(y, INSET, h - INSET))
			var d := Vector2(x, y).distance_to(c)
			var near := t.height_at(c.x, c.y)
			var cell := mini(int(c.y), int(h) - 1) * cells_w + mini(int(c.x), cells_w - 1)
			var wl := t.water_base[cell]
			var m := int(t.water_mat[cell])
			if m >= t.materials.size():
				wl = -INF
			var z := near
			pxy[j * nx + i] = Vector2(x, y)
			if d <= 0.0:
				var gi := int(roundf(y)) * t.grid_w + int(roundf(x))
				seam[j * nx + i] = gi
				pxy[j * nx + i] += t.land_xy[gi]
				z = t.heights[gi]
			else:
				var s := _perimeter_param(c - Vector2(INSET, INSET), iw, ih)
				var avg := _window_mean(pre, per, s, maxf(1.0, d * SEAM_SMOOTH))
				z = lerpf(near, avg, smoothstep(0.0, 8.0, d)) + noise.get_noise_2d(x, y) * amp * smoothstep(0.0, NOISE_RAMP, d)
				# Off a sea edge the bed keeps at least the edge depth, deepening.
				if not is_inf(wl) and near < wl:
					z = minf(z, near - d * 0.15)
			hz[j * nx + i] = z
			# Under liquid: the vertex colour of EITerrain._underwater.
			if not is_inf(wl) and wl > z:
				var a: float = (t.materials[m].color as Color).a
				var k := (wl - z) * (wl - z) / (15.0 * maxf(1.0 - a, 1e-3))
				var e := t.material_e(m)
				vcol[j * nx + i] = Color(e.r, e.g, e.b, minf(k * 0.25, 1.0))
	# Normals: the map's own on the seam, else from the ring's heights.
	var nn := PackedVector3Array()
	nn.resize(nx * ny)
	for j in ny:
		for i in nx:
			var gi := seam[j * nx + i]
			nn[j * nx + i] = t.land_n[gi] if gi >= 0 else _normal(hz, xs, ys, i, j)
	var land := _Builder.new()
	var water := _Builder.new()
	var tw := int(w) / 2
	for j in ny - 1:
		for i in nx - 1:
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var y0 := ys[j]
			var y1 := ys[j + 1]
			if x0 >= INSET and x1 <= w - INSET and y0 >= INSET and y1 <= h - INSET:
				continue   # the map itself
			var c := Vector2(clampf((x0 + x1) * 0.5, INSET, w - INSET - 0.01),
				clampf((y0 + y1) * 0.5, INSET, h - INSET - 0.01))
			var ti := (int(c.y) / 2) * tw + int(c.x) / 2
			var vi := [j * nx + i, j * nx + i + 1, (j + 1) * nx + i, (j + 1) * nx + i + 1]
			var z := [hz[vi[0]], hz[vi[1]], hz[vi[2]], hz[vi[3]]]
			var p := [pxy[vi[0]], pxy[vi[1]], pxy[vi[2]], pxy[vi[3]]]
			var n := [nn[vi[0]], nn[vi[1]], nn[vi[2]], nn[vi[3]]]
			var lc := [vcol[j * nx + i], vcol[j * nx + i + 1], vcol[(j + 1) * nx + i], vcol[(j + 1) * nx + i + 1]]
			# texture tile corners: half a tile on 1 m cells, else the whole tile
			var u := _tile_span(x0, x1)
			var v := _tile_span(y0, y1)
			land.quad(t, p, z, n, t.land_tile[ti], ti, lc, u, v)
			var wf := t.water_tile[ti]
			if wf < 0:
				continue
			var cell := int(c.y) * cells_w + int(c.x)
			var m := int(t.water_mat[cell])
			var lvl := t.water_base[cell]
			if m >= t.materials.size() or is_inf(lvl) or lvl < minf(minf(z[0], z[1]), minf(z[2], z[3])) - 0.1:
				continue
			var up := Vector3.UP
			var wc: Color = t.materials[m].color
			var pw := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)]   # the cut is at exactly INSET
			water.quad(t, pw, [lvl, lvl, lvl, lvl], [up, up, up, up], wf, m + OUTER_MAT, [wc, wc, wc, wc], u, v)
	var lm := land.mesh(land_mat)
	if lm:
		lm.name = "Land"
		lm.layers = EITerrain.SHADOW_RECEIVER_LAYER | EITerrain.DECAL_LAYER
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lm)
	var wm := water.mesh(water_mat)
	if wm:
		wm.name = "Water"
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wm.extra_cull_margin = 8.0
		add_child(wm)


## Cell borders along one map side: RINGS widening rows outside the inset
## rectangle [INSET, length - INSET], STEP inside it.
static func _axis(length: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	for r in range(RINGS, 0, -1):
		a.append(INSET - _ring(r))
	var x := INSET
	while x < length - INSET:
		a.append(x)
		x += STEP
	a.append(length - INSET)
	for r in range(1, RINGS + 1):
		a.append(length - INSET + _ring(r))
	return a


## Tile-relative corner indices (0..2, half tiles) for a cell from a to b.
static func _tile_span(a: float, b: float) -> Vector2i:
	if b - a < 1.5:
		var o := posmod(int(floorf(a + 0.01)), 2)
		return Vector2i(o, o + 1)
	return Vector2i(0, 2)


static func _ring(r: int) -> float:
	return REACH * pow(float(r) / RINGS, 1.6)


## Point on the map border at perimeter distance s (counter-clockwise from 0,0).
static func _perimeter_point(s: float, w: float, h: float) -> Vector2:
	if s < w:
		return Vector2(s, 0.0)
	s -= w
	if s < h:
		return Vector2(w, s)
	s -= h
	if s < w:
		return Vector2(w - s, h)
	s -= w
	return Vector2(0.0, h - s)


static func _perimeter_param(c: Vector2, w: float, h: float) -> float:
	if c.y <= 0.0:
		return c.x
	if c.x >= w:
		return w + c.y
	if c.y >= h:
		return w + h + (w - c.x)
	return 2.0 * w + h + (h - c.y)


## Mean edge height over the perimeter window [s - win, s + win] (wrapping).
static func _window_mean(pre: PackedFloat64Array, per: int, s: float, win: float) -> float:
	var half := mini(int(win), per / 2 - 1)
	var a := int(s) - half
	var b := int(s) + half + 1
	var sum := 0.0
	var n := b - a
	if a < 0:
		sum += pre[per] - pre[per + a]
		a = 0
	if b > per:
		sum += pre[b - per]
		b = per
	sum += pre[b] - pre[a]
	return sum / n


static func _normal(hz: PackedFloat32Array, xs: PackedFloat32Array, ys: PackedFloat32Array, i: int, j: int) -> Vector3:
	var nx := xs.size()
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, nx - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, ys.size() - 1)
	var dzx := (hz[j * nx + i1] - hz[j * nx + i0]) / maxf(xs[i1] - xs[i0], 0.01)
	var dzy := (hz[j1 * nx + i] - hz[j0 * nx + i]) / maxf(ys[j1] - ys[j0], 0.01)
	return EISpace.vec(Vector3(-dzx, -dzy, 1.0)).normalized()


class _Builder:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	## One cell with the whole texture tile `f` (corners as EITerrain._make_mesh).
	func quad(t: EITerrain, p: Array, z: Array, n: Array, f: int, mat: int, color: Array, u: Vector2i, v: Vector2i) -> void:
		var base := pos.size()
		for k in 4:
			var q: Vector2 = p[k]
			pos.append(EISpace.pos(q.x, q.y, z[k]))
			nrm.append(n[k])
			var tuv: Array = t._tile_uv(f, u.y if k & 1 else u.x, v.y if k >> 1 else v.x)
			uv.append(tuv[0])
			uv2.append(Vector2(tuv[1], mat))
			col.append(color[k])
		idx.append_array([base + 2, base + 1, base, base + 1, base + 2, base + 3])

	func mesh(mat: Material) -> MeshInstance3D:
		if pos.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		return mi
