class_name CameraFade
extends RefCounted
## Remake-only (option cam_see_through, modern camera): map objects (trees,
## houses, rocks…) that stand between the camera and a hero of this player
## dissolve into a screen-door dither and back, eased over FADE_TIME. While an
## object fades its meshes wear a copy of their material whose shader (the
## object's own, with a dither discard put at the top of fragment()) reads the
## instance uniform cam_fade; the opaque pipeline, depth and shadows of the
## figure stay as they were (no dither in the shadow pass). Per player, visual only. Objects whose box holds
## the hero (a bridge, a big rock face the hero stands on) stay as they are.

const ALPHA := 0.65         # share of a hiding object's pixels dropped
const FADE_TIME := 0.25     # seconds to fade fully in / out
const SCAN_TIME := 0.1      # seconds between occlusion tests
const CHEST := 1.2          # metres above a hero's feet tested
const SHRINK := 0.15        # part of each box side left out (bushy box corners)

var _world: Node            # world the cache was built for
var _nodes: Array[Node3D] = []
var _boxes: Array[AABB] = []
var _meshes: Array = []     # per node: Array of GeometryInstance3D
var _faces := {}            # GeometryInstance3D -> PackedVector3Array (world triangles), lazily
var _cur := {}              # node index -> transparency now
var _want := {}             # node index -> target transparency
var _scan := 0.0
static var _derived := {}   # original Material -> dithering ShaderMaterial (null: cannot)
static var _shaders := {}   # original Shader -> derived Shader

const DITHER := """
instance uniform float cam_fade = 0.0;
"""
const DITHER_FRAG := """
	if (cam_fade > 0.0 && !IN_SHADOW_PASS) {
		ivec2 cf_p = ivec2(FRAGCOORD.xy) % 4;
		int cf_i = cf_p.x + cf_p.y * 4;
		float cf_b[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if ((cf_b[cf_i] + 0.5) / 16.0 < cam_fade) {
			discard;
		}
	}
"""


## Drops every fade at once (dialogue camera, style switch, option off).
func clear() -> void:
	for i: int in _cur:
		_set_alpha(i, 0.0)
	_cur.clear()
	_want.clear()


func update(g: Game, eye: Vector3, dt: float) -> void:
	if not is_instance_valid(g.world) or not is_instance_valid(g.world.map):
		clear()   # zone change / quit: the old world may already be freed
		_world = null
		return
	if not is_instance_valid(_world) or _world != g.world:
		clear()
		_build(g.world)
	_scan -= dt
	if _scan <= 0.0:
		_scan = SCAN_TIME
		_find(g, eye)
	var step := dt / FADE_TIME * ALPHA
	for i: int in _cur.keys():
		var w: float = _want.get(i, 0.0)
		var c: float = move_toward(_cur[i], w, step)
		_set_alpha(i, c)
		if c <= 0.0 and w <= 0.0:
			_cur.erase(i)
		else:
			_cur[i] = c
	for i: int in _want:
		if not _cur.has(i):
			_cur[i] = 0.0


func _build(world: Node) -> void:
	_world = world
	_nodes.clear()
	_boxes.clear()
	_meshes.clear()
	_faces.clear()
	for o in world.map.object_nodes:   # untyped: a freed node cannot be assigned to a Node3D variable
		if not is_instance_valid(o):
			continue
		var n := o as Node3D
		if n == null:
			continue
		var ms: Array = []
		var box := AABB()
		var first := true
		for gi: Node in n.find_children("*", "GeometryInstance3D", true, false):
			var g3 := gi as GeometryInstance3D
			var b := g3.global_transform * g3.get_aabb()
			box = b if first else box.merge(b)
			first = false
			ms.append(g3)
		if first or box.size.y < 1.5:
			continue   # nothing drawn, or flat (a rug of stones cannot hide anyone)
		var s := box.size * SHRINK
		box = AABB(box.position + Vector3(s.x, 0.0, s.z), box.size - Vector3(s.x * 2.0, s.y, s.z * 2.0))
		_nodes.append(n)
		_boxes.append(box)
		_meshes.append(ms)


func _find(g: Game, eye: Vector3) -> void:
	_want.clear()
	var targets: Array[Vector3] = []
	for u in g.my_units():
		if is_instance_valid(u) and not u.hidden:
			targets.append(u.global_position + Vector3(0.0, CHEST, 0.0))
	if targets.is_empty():
		return
	var reach := 0.0
	for t in targets:
		reach = maxf(reach, eye.distance_to(t))
	for i in _boxes.size():
		var b: AABB = _boxes[i]
		var c := b.get_center()
		if eye.distance_to(c) > reach + b.size.length() * 0.5:
			continue
		for t in targets:
			if b.has_point(t) or b.has_point(t - Vector3(0.0, CHEST, 0.0)):
				continue
			if b.intersects_segment(eye, t) != null and _hides(i, eye, t):
				_want[i] = ALPHA
				break


## The object's own triangles cross the eye → hero line (its merged box is
## only the first test: a long palisade's box covers ground far from the
## wall itself, which made whole fence rings fade).
func _hides(i: int, eye: Vector3, t: Vector3) -> bool:
	for gi in _meshes[i]:
		var g3 := gi as MeshInstance3D
		if g3 == null or not is_instance_valid(g3) or g3.mesh == null:
			continue
		if (g3.global_transform * g3.get_aabb()).intersects_segment(eye, t) == null:
			continue
		var f: PackedVector3Array = _faces.get(g3, PackedVector3Array())
		if f.is_empty():
			f = g3.global_transform * g3.mesh.get_faces()
			_faces[g3] = f
		for k in range(0, f.size() - 2, 3):
			if Geometry3D.segment_intersects_triangle(eye, t, f[k], f[k + 1], f[k + 2]) != null:
				return true
	return false


func _set_alpha(i: int, a: float) -> void:
	if i >= _meshes.size() or not is_instance_valid(_nodes[i]):
		return
	for gi in _meshes[i]:
		if not is_instance_valid(gi):
			continue
		var g3 := gi as GeometryInstance3D
		if a <= 0.0:
			if g3.has_meta("cam_fade_mat"):
				g3.material_override = g3.get_meta("cam_fade_mat")
				g3.remove_meta("cam_fade_mat")
				g3.set_instance_shader_parameter("cam_fade", 0.0)
			continue
		if not g3.has_meta("cam_fade_mat"):
			var m := _dither_material(g3.material_override)
			if m == null:
				continue
			g3.set_meta("cam_fade_mat", g3.material_override)
			g3.material_override = m
		g3.set_instance_shader_parameter("cam_fade", a)


## The object's material with the dither added (shared per material).
static func _dither_material(orig: Material) -> ShaderMaterial:
	if _derived.has(orig):
		return _derived[orig]
	var out: ShaderMaterial = null
	var sm := orig as ShaderMaterial
	if sm and sm.shader:
		var sh: Shader = _shaders.get(sm.shader)
		if sh == null and not _shaders.has(sm.shader):
			var code := sm.shader.code
			var f := code.find("void fragment()")
			var b := code.find("{", f) if f >= 0 else -1
			if b >= 0:
				sh = Shader.new()
				sh.code = code.substr(0, f) + DITHER + code.substr(f, b + 1 - f) + DITHER_FRAG + code.substr(b + 1)
			_shaders[sm.shader] = sh
		if sh:
			out = ShaderMaterial.new()
			out.shader = sh
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				out.set_shader_parameter(u.name, sm.get_shader_parameter(u.name))
	_derived[orig] = out
	return out
