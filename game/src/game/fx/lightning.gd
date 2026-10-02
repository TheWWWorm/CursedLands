class_name FxLightning
extends RefCounted
## A lightning bolt: the original CEffectLightning / CLightning (
## setup, geometry, noise
##  draw). Noise tables come from gfx.res/lightning.dat
## (32 x 400 floats: 0-15 coarse, 16-31 fine). Points are in EI space.
## The strip (display =) is built
## screen space: each point is offset across the projected segment by
## width * 15 * rhw pixels, the first and last points get diffuse alpha 0
## (the bolt fades out over its end segments), tu runs along the bolt
## (fixed 0.875 when the V repeat is 0, i.e. param < 0), tv across.
## The pixel width does not scale with the resolution; the remake takes the
## 800 x 600 view (viewport half-width 400, x scale cos(pi / 7)): half-width
## = width * 15 / (400 * cos(pi / 7)) m in view space. Additive.

const WIDTH_SCALE := 0.0416218
const BRANCH_F := [0.2, 0.3, 0.5, 0.8, 0.9, 0.9]

static var _tables: Array = []   # 32 PackedFloat32Array(400)
static var _mat_strip: Array = [null, null]
static var _mat_glow: StandardMaterial3D

var fx: ParticleFx
var a := Vector3.ZERO
var b := Vector3.ZERO
var param := 0.0
var demon := false
var from: Object = null    # tracked start unit (hit point)
var to: Object = null      # tracked end unit (+1 z)
var until := -1
var node := MeshInstance3D.new()
var _mesh := ImmediateMesh.new()
var _amp := 1.0
var _bolts: Array = []     # {a_f, b_f, shift, width, keys: [[k0,k1,k2],[k0,k1,k2]], band}
var _tick := 0


static func _load_tables() -> void:
	if not _tables.is_empty():
		return
	var arc := EIResArchive.open_path(GameData.root.path_join("res/gfx.res"))
	var d := arc.read("lightning.dat") if arc and arc.has("lightning.dat") else PackedByteArray()
	for i in 32:
		var t := PackedFloat32Array()
		if d.size() >= (i + 1) * 1600:
			t = d.slice(i * 1600, (i + 1) * 1600).to_float32_array()
		else:
			t.resize(400)
		_tables.append(t)


func _init(owner, pa: Vector3, pb: Vector3, prm: float) -> void:
	_load_tables()
	fx = owner
	a = pa
	b = pb
	param = prm
	node.mesh = _mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	node.extra_cull_margin = 16384.0
	_amp = 1.5 if param > 0.0 else (2.0 if param == 0.0 else 1.0)
	var w := absf(param) * (1.5 if param < 0.0 else 1.0)
	if param == 0.0:
		w = 4.0
	_bolts.append(_new_bolt(0.0, Vector3.ZERO, w))
	var L := (b - a).length()
	for i in 6:
		if param == 0.0:
			var sh := Vector3(_u2(), _u2(), _u2()) * 0.05 * L
			_bolts.append(_new_bolt(0.0, sh, 2.45 + _u01() * 2.8))
		else:
			_bolts.append(_new_bolt(BRANCH_F[i], Vector3.ZERO, (0.7 + _u01() * 0.8) * absf(param) * 0.5))


func _u01() -> float:
	return float(fx.rnd()) * 2.3283064e-10


func _u2() -> float:
	return float(fx.rnd()) * 4.656613e-10 - 1.0


func _key() -> Array:
	var w := Vector2(_u2(), _u2())
	w = w.normalized() * _amp if w.length() > 0.0001 else Vector2(_amp, 0)
	return [fx.rnd() % 16, fx.rnd() % 16, w.x, w.y]


func _new_bolt(f: float, shift: Vector3, width: float) -> Dictionary:
	return {"f": f, "shift": shift, "width": width, "band": (fx.rnd() & 3) * 0.25,
		"keys": [[_key(), _key(), _key()], [_key(), _key(), _key()]]}


## CEffectLightning update: the ends follow their units; a new
## noise key every 4 ticks.
func update_tick() -> void:
	_tick += 1
	if from and is_instance_valid(from) and from is GameUnit and from.is_inside_tree():
		a = fx.unit_point(from, 0)
	if to and is_instance_valid(to) and to is GameUnit and to.is_inside_tree():
		b = fx.unit_point(to, 0)
	if _tick % 4 == 0:
		for bolt: Dictionary in _bolts:
			for ax in 2:
				var k: Array = bolt.keys[ax]
				k.pop_front()
				k.append(_key())


func _points(bolt: Dictionary, frac: float) -> PackedVector3Array:
	var pa: Vector3 = b.lerp(a, bolt.f) if bolt.f > 0.0 else a
	pa += bolt.shift
	var pb: Vector3 = b + bolt.shift
	var d := pb - pa
	var L := minf(d.length(), 15.0)
	var n := 72
	if L < 10.0:
		n = 48
	elif L <= 15.0:
		n = clampi(roundi(5.0 * L) & ~3, 4, 400)
	var P := Vector3(d.y + 0.0666 * d.z, 0.013 * d.z - d.x, -0.0666 * d.x - 0.013 * d.y)
	var Q := d.cross(P).normalized() * P.length()
	var t := fmod(float(_tick) + frac, 4.0) / 4.0
	var bw := [0.5 - t + t * t * 0.5, t + 0.5 - t * t, t * t * 0.5]
	var fine := [16 + fx.rnd() % 16, 16 + fx.rnd() % 16]
	var out := PackedVector3Array()
	out.resize(n + 1)
	var step := d / float(n)
	for i in n + 1:
		var off := [0.0, 0.0]
		for ax in 2:
			var s := 0.0
			var keys: Array = bolt.keys[ax]
			for k in 3:
				var key: Array = keys[k]
				s += bw[k] * (key[2] * _tables[key[0]][i] + key[3] * _tables[key[1]][i])
			s += _tables[fine[ax]][i]
			off[ax] = s
		out[i] = pa + step * i + P * off[0] + Q * off[1]
	return out


static func _strip_mat(dem: bool) -> StandardMaterial3D:
	var i := 1 if dem else 0
	if _mat_strip[i] == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.vertex_color_use_as_albedo = true
		m.texture_repeat = true
		m.render_priority = ParticleFx.RENDER_PRIORITY + 1   # after the particles
		m.albedo_texture = GameData.get_texture("demonlightning" if dem else "lightning")
		_mat_strip[i] = m
	# Option gfx_bloom: the bolt passes the bloom threshold (ParticleFx.GLOW_BOOST).
	var b := ParticleFx.GLOW_BOOST if Gfx.on("gfx_bloom") else 1.0
	_mat_strip[i].albedo_color = Color(b, b, b)
	return _mat_strip[i]


static func _glow_mat() -> StandardMaterial3D:
	if _mat_glow == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.render_priority = ParticleFx.RENDER_PRIORITY + 1
		m.albedo_texture = GameData.get_texture("smtglight")
		_mat_glow = m
	var b := ParticleFx.GLOW_BOOST if Gfx.on("gfx_bloom") else 1.0
	_mat_glow.albedo_color = Color(b, b, b)
	return _mat_glow


func draw(frac: float) -> void:
	_mesh.clear_surfaces()
	var cam: Camera3D = node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	if cam == null:
		return
	var eye := cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _strip_mat(demon))
	for bolt: Dictionary in _bolts:
		var pts := _points(bolt, frac)
		var hw: float = bolt.width * WIDTH_SCALE
		var n := pts.size()
		var len := (pts[n - 1] - pts[0]).length()
		var vrep := 0.0 if param < 0.0 else len * 0.6
		var u0: float = 0.0 if param < 0.0 else bolt.band
		var g := PackedVector3Array()
		for p in pts:
			g.append(Vector3(p.x, p.z, -p.y))
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in n:
			var tg := g[mini(i + 1, n - 1)] - g[maxi(i - 1, 0)]
			var side := tg.cross(eye - g[i]).normalized() * hw
			var l := g[i] - side
			var r := g[i] + side
			if i > 0:
				var s0 := vrep * float(i - 1) / float(n - 1)
				var s1 := vrep * float(i) / float(n - 1)
				if param < 0.0:
					s0 = 0.875
					s1 = 0.875
				_quad(prev_l, prev_r, l, r, Vector2(s0, u0), Vector2(s0, u0 + 0.25), Vector2(s1, u0), Vector2(s1, u0 + 0.25),
					0.0 if i == 1 else 1.0, 0.0 if i == n - 1 else 1.0)
			prev_l = l
			prev_r = r
	_mesh.surface_end()
	if param > 0.0:
		# End glows: frame (tick / 2) % 15 of SmtgLight.
		var L := (b - a).length()
		var sz := clampf(0.11 * L, 0.5, 1.2)
		var f := (_tick / 2) % 15
		var cx := f & 3
		var ry := f >> 2
		var uv0 := Vector2(cx * 0.25, 1.0 - (ry + 1) * 0.25)
		var uv1 := Vector2((cx + 1) * 0.25, 1.0 - ry * 0.25)
		var right := cam.global_transform.basis.x * sz
		var up := cam.global_transform.basis.y * sz
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _glow_mat())
		for p in [a, b]:
			var c := Vector3(p.x, p.z, -p.y)
			_quad(c - right + up, c + right + up, c - right - up, c + right - up,
				uv0, Vector2(uv1.x, uv0.y), Vector2(uv0.x, uv1.y), uv1)
		_mesh.surface_end()


## Two triangles: a-b is one edge, c-d the next (uv per corner).
## a0 / a1: vertex alpha of the a-b and c-d edges.
func _quad(pa: Vector3, pb: Vector3, pc: Vector3, pd: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, a0 := 1.0, a1 := 1.0) -> void:
	for v in [[pa, ua, a0], [pb, ub, a0], [pc, uc, a1], [pb, ub, a0], [pd, ud, a1], [pc, uc, a1]]:
		_mesh.surface_set_color(Color(1, 1, 1, v[2]))
		_mesh.surface_set_uv(v[1])
		_mesh.surface_add_vertex(v[0])
