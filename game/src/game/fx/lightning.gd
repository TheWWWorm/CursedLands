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
## Pixel width stays fixed when the viewport grows. Project the points before
## finding the strip tangent, then lift its screen vertices back at the same
## depth for Godot's depth test. The original clip W is sin(pi/7)*view depth.

const CLIP_W_SCALE := 0.4338837391175581
const BRANCH_F := [0.2, 0.3, 0.5, 0.8, 0.9, 0.9]

static var _tables: Array = []   # 32 PackedFloat32Array(400)
static var _mat_strip: Array = [null, null]
static var _mat_glow: Array = [null, null]

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
var _geometry: Object = ClassDB.instantiate("LightningGeometryKernel") if ClassDB.class_exists("LightningGeometryKernel") and not OS.get_cmdline_user_args().has("--ei-script-lightning") else null
var _packed_mesh := ArrayMesh.new()
var _vertices := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _surface_material: Material
var _overview_draw_at := 0
var _surfaces: Array = []
var _surface_sizes := PackedInt32Array()
var _buffer_layout := false
var _dynamic_surfaces := _geometry != null and _geometry.has_method("surface_data") and DisplayServer.get_name() != "headless"


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


func _init(owner, pa: Vector3, pb: Vector3, prm: float, script_geometry := false) -> void:
	if script_geometry: _geometry = null
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
	if _geometry and _geometry.has_method("new_bolts"):
		_bolts = _geometry.new_bolts(a,b,param,fx._rng)
		return
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
		if _geometry and _geometry.has_method("advance_keys"):
			_geometry.advance_keys(_bolts,_amp,fx._rng)
			return
		for bolt: Dictionary in _bolts:
			for ax in 2:
				var k: Array = bolt.keys[ax]
				k.pop_front()
				k.append(_key())


func _points(bolt: Dictionary, frac: float) -> PackedVector3Array:
	var fine := [16 + fx.rnd() % 16, 16 + fx.rnd() % 16]
	if _geometry:
		var packed: PackedVector3Array = _geometry.points(a,b,bolt,_tick,frac,_tables,PackedInt32Array(fine))
		if not packed.is_empty(): return packed
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


static func _glow_mat(dem := false) -> StandardMaterial3D:
	var i := 1 if dem else 0
	if _mat_glow[i] == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.vertex_color_use_as_albedo = true
		m.render_priority = ParticleFx.RENDER_PRIORITY + 1
		m.albedo_texture = GameData.get_texture("demonlight" if dem else "smtglight")
		_mat_glow[i] = m
	var b := ParticleFx.GLOW_BOOST if Gfx.on("gfx_bloom") else 1.0
	_mat_glow[i].albedo_color = Color(b, b, b)
	return _mat_glow[i]


##  00502ac0 / 00502b90, after the camera projection boundary:
## end tangents use one segment, inner tangents span both adjacent segments.
## Points and outputs are XY / Z / RHW. Float32 stores match the native arrays.
static func projected_strip(points: PackedVector4Array, width: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	for i in points.size():
		var p := points[i]
		var first := points[maxi(i - 1, 0)]
		var last := points[mini(i + 1, points.size() - 1)]
		var tangent := Vector2(last.x - first.x, last.y - first.y)
		var extent := float(PackedFloat32Array([width * p.w * 15.0])[0])
		var k := extent / tangent.length() if tangent.length() > 0.0 else 0.0
		out.append(Vector4(p.x + tangent.y * k, p.y - tangent.x * k, p.z, p.w))
		out.append(Vector4(p.x - tangent.y * k, p.y + tangent.x * k, p.z, p.w))
	return out


## Visible strip vertices, preserving each centre's view depth. The renderer
## clips the resulting triangles at its near plane; exact native clipped-strip
## reconstruction remains a separate rendering difference.
static func ribbon(cam: Camera3D, points: PackedVector3Array, width: float) -> PackedVector3Array:
	var projected := PackedVector4Array()
	var depths := PackedFloat32Array()
	var inv := cam.global_transform.affine_inverse()
	for p in points:
		var depth := -(inv * p).z
		if depth == 0.0:
			return PackedVector3Array()   # a non-finite projection has no drawable strip
		var at := cam.unproject_position(p)
		projected.append(Vector4(at.x, at.y, depth, 1.0 / (CLIP_W_SCALE * depth)))
		depths.append(depth)
	var out := PackedVector3Array()
	var strip := projected_strip(projected, width)
	for i in strip.size():
		out.append(cam.project_position(Vector2(strip[i].x, strip[i].y), depths[i / 2]))
	return out


## positive bolts glow only at the end; wall parameter zero
## glows at both ends with an unclamped radius. Negative bolts have no glow.
static func glow_ends(pa: Vector3, pb: Vector3, prm: float) -> PackedVector3Array:
	return PackedVector3Array() if prm < 0.0 else PackedVector3Array([pb, pa] if prm == 0.0 else [pb])


static func glow_size(pa: Vector3, pb: Vector3, prm: float) -> float:
	var size := float(PackedFloat32Array([(pb - pa).length() * float(PackedFloat32Array([0.11])[0])])[0])
	return clampf(size, 0.5, float(PackedFloat32Array([1.2])[0])) if prm > 0.0 else size


##  draws eight billboard slices towards the camera. The frame
## argument supplied by 00467ad0 is unused: phase is world tick + rounded x*15,
## advancing two atlas cells per slice. Every slice has diffuse alpha160/255.
static func glow_slices(point: Vector3, eye: Vector3, size: float, world_tick: int) -> Dictionary:
	var direction := eye - point
	if direction.length() > 0.0:
		direction /= direction.length()
	var phase := world_tick + GameUnit._fistp(float(PackedFloat32Array([point.x * 15.0])[0]))
	var points := PackedVector4Array()
	var uvs := PackedVector4Array()
	for i in 8:
		var f := i * 0.125
		var at := point + direction * f * size
		points.append(Vector4(at.x, at.y, at.z, sqrt(1.0 - f * f) * size))
		var frame := posmod(phase + i * 2, 15)
		var x := (frame & 3) * 0.25
		var y := 0.75 - (frame >> 2) * 0.25
		uvs.append(Vector4(x, y, x + 0.25, y + 0.25))
	return {"points": points, "uvs": uvs}


## Native display equivalent; called with a surface already open.
func _draw_strip(cam: Camera3D, points: PackedVector3Array, width: float, repeat: float, band: float) -> void:
	if _geometry:
		var packed: Array = _geometry.strip(cam.get_camera_transform(),cam.global_transform.affine_inverse(),cam.get_camera_projection(),cam.get_viewport().get_visible_rect().size,points,width,repeat,band)
		if packed.size()==3:
			_vertices.append_array(packed[0]);_uvs.append_array(packed[1]);_colors.append_array(packed[2])
			return
	var n := points.size()
	if n < 2:
		return
	var strip := ribbon(cam, points, width)
	if strip.size() != n * 2:
		return
	var step := float(PackedFloat32Array([repeat / float(n - 1)])[0])
	var s0 := 0.875 if repeat == 0.0 else 0.0
	for i in range(1, n):
		var s1 := float(PackedFloat32Array([s0 + step])[0])
		_quad(strip[(i - 1) * 2], strip[(i - 1) * 2 + 1], strip[i * 2], strip[i * 2 + 1],
			Vector2(s0, band), Vector2(s0, band + 0.25), Vector2(s1, band), Vector2(s1, band + 0.25),
			0.0 if i == 1 else 1.0, 0.0 if i == n - 1 else 1.0)
		s0 = s1


func draw(frac: float) -> void:
	if fx.world and fx.world.arena_overview:
		var now := Time.get_ticks_usec()
		if _overview_draw_at == 0:
			# A one-tick flash can expire before a distant update slot. Draw
			# its first frame immediately, then stagger subsequent geometry.
			_overview_draw_at = now + 1 + int(node.get_instance_id() % 127) * 50000 / 127
		else:
			if now < _overview_draw_at: return
			_overview_draw_at += (int((now-_overview_draw_at) / 50000) + 1) * 50000
	else: _overview_draw_at = 0
	if _geometry:
		_surfaces.clear(); node.mesh=_packed_mesh
	else:
		_mesh.clear_surfaces(); node.mesh=_mesh
	var cam: Camera3D = node.get_viewport().get_camera_3d() if node.is_inside_tree() else null
	if cam == null:
		return
	var origin := fx.display_origin()
	var to_world := Transform3D(Basis(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0)),origin)
	_begin_surface(_strip_mat(demon))
	for bolt: Dictionary in _bolts:
		var pts := _points(bolt, frac)
		var n := pts.size()
		var len := (pts[n - 1] - pts[0]).length()
		var vrep := 0.0 if param < 0.0 else len * 0.6
		var u0: float = 0.0 if param < 0.0 else bolt.band
		var g := to_world * pts
		_draw_strip(cam, g, bolt.width, vrep, u0)
	_end_surface()
	if param >= 0.0:
		var sz := glow_size(a, b, param)
		var now := roundi(fx.world.time / ParticleFx.TICK) if fx.world else fx.tick
		_begin_surface(_glow_mat(demon))
		if _geometry and _geometry.has_method("glows"):
			var packed: Array = _geometry.glows(PackedVector3Array(glow_ends(a,b,param)),ParticleFx.ei(origin),ParticleFx.ei(cam.global_position),cam.global_transform.basis,sz,now)
			if packed.size() == 3:
				_vertices.append_array(packed[0]); _uvs.append_array(packed[1]); _colors.append_array(packed[2])
		else:
			_draw_glows_script(cam,sz,now)
		_end_surface()
	if _geometry:
		_install_surfaces()
		_surfaces.clear()


func _draw_glows_script(cam: Camera3D, sz: float, now: int) -> void:
	for p in glow_ends(a, b, param):
		var slices := glow_slices(p + ParticleFx.ei(fx.display_origin()), ParticleFx.ei(cam.global_position), sz, now)
		for i in 8:
			var v: Vector4 = slices.points[i]
			var uv: Vector4 = slices.uvs[i]
			var c := Vector3(v.x, v.z, -v.y)
			# Display expands size*rhw*viewportHalfWidth pixels:
			# under the original frustum that is size/cos(pi/7) metres.
			var half := v.w / cos(PI / 7.0)
			var right := cam.global_transform.basis.x * half
			var up := cam.global_transform.basis.y * half
			_quad(c - right + up, c + right + up, c - right - up, c + right - up,
				Vector2(uv.x, uv.y), Vector2(uv.z, uv.y), Vector2(uv.x, uv.w), Vector2(uv.z, uv.w),
				160.0 / 255.0, 160.0 / 255.0)


func _begin_surface(material: Material) -> void:
	if _geometry:
		_vertices=PackedVector3Array();_uvs=PackedVector2Array();_colors=PackedColorArray();_surface_material=material
	else: _mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)


func _end_surface() -> void:
	if _geometry:
		if _vertices.is_empty(): return
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=_vertices;arrays[Mesh.ARRAY_TEX_UV]=_uvs;arrays[Mesh.ARRAY_COLOR]=_colors
		_surfaces.append([arrays,_surface_material])
	else: _mesh.surface_end()


func _install_surfaces() -> void:
	var reuse := _dynamic_surfaces and _buffer_layout and _surface_sizes.size() == _surfaces.size()
	if reuse:
		for i in _surfaces.size():
			if _surface_sizes[i] != _surfaces[i][0][Mesh.ARRAY_VERTEX].size(): reuse = false; break
	if not reuse:
		_packed_mesh.clear_surfaces(); _packed_mesh.custom_aabb = AABB()
		_surface_sizes.clear(); _buffer_layout = true
		for surface: Array in _surfaces:
			_packed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface[0],[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
			var index := _packed_mesh.get_surface_count()-1
			_packed_mesh.surface_set_material(index,surface[1])
			var count: int = surface[0][Mesh.ARRAY_VERTEX].size()
			_surface_sizes.append(count)
			_buffer_layout = _buffer_layout and _updatable_layout(_packed_mesh.surface_get_format(index),count)
		return
	var bounds := AABB()
	for i in _surfaces.size():
		var arrays: Array = _surfaces[i][0]
		var data: Array = _geometry.surface_data(arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_TEX_UV],arrays[Mesh.ARRAY_COLOR])
		if data.size() != 3: return
		_packed_mesh.surface_update_vertex_region(i,0,data[0])
		_packed_mesh.surface_update_attribute_region(i,0,data[1])
		bounds = data[2] if i == 0 else bounds.merge(data[2])
		if _packed_mesh.surface_get_material(i) != _surfaces[i][1]: _packed_mesh.surface_set_material(i,_surfaces[i][1])
	_packed_mesh.custom_aabb = bounds


static func _updatable_layout(format: int, count: int) -> bool:
	return not (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) \
		and RenderingServer.mesh_surface_get_format_vertex_stride(format,count) == 12 \
		and RenderingServer.mesh_surface_get_format_attribute_stride(format,count) == 12 \
		and RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_COLOR) == 0 \
		and RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_TEX_UV) == 4


## Two triangles: a-b is one edge, c-d the next (uv per corner).
## a0 / a1: vertex alpha of the a-b and c-d edges.
func _quad(pa: Vector3, pb: Vector3, pc: Vector3, pd: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, a0 := 1.0, a1 := 1.0) -> void:
	if _geometry:
		_vertices.append_array(PackedVector3Array([pa,pb,pc,pc,pb,pd]))
		_uvs.append_array(PackedVector2Array([ua,ub,uc,uc,ub,ud]))
		_colors.append_array(PackedColorArray([Color(1,1,1,a0),Color(1,1,1,a0),Color(1,1,1,a1),Color(1,1,1,a1),Color(1,1,1,a0),Color(1,1,1,a1)]))
		return
	for v in [[pa, ua, a0], [pb, ub, a0], [pc, uc, a1], [pc, uc, a1], [pb, ub, a0], [pd, ud, a1]]:
		_mesh.surface_set_color(Color(1, 1, 1, v[2]))
		_mesh.surface_set_uv(v[1])
		_mesh.surface_add_vertex(v[0])
