class_name TerrainDetails
extends Node3D
## Optional remake ground geometry. Grass is deterministic, streamed around
## the view and casts the normal sun shadows. Tracks use the existing animated
## footfalls on every peer. Neither effect changes terrain/navigation data.

const CHUNK := 8.0
const SPACING := 0.30
const RANGE := 36.0
const MAX_CHUNKS := 80
const BUILD_US := 2500
const GRASS_TYPES := [0, 5, 11]
const BLADES := 14
const BLADE_ROWS := 8
const NEAR_RANGE := 18.0
# Full leaf envelope, including the largest width/lean and wind offset.
# Roots alone can be outside a wall while their curved tips pass through it.
const SCENERY_RADIUS := 0.56
const SCENERY_HEIGHT := 0.88
const GRASS_SHADER := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
#define EI_GRASS_LIGHT
render_mode cull_disabled, ambient_light_disabled;
uniform vec3 view_position;
uniform float breeze = 1.0;
varying vec3 blade_colour;
varying vec3 blade_normal;
varying vec3 ei_e;
varying float ei_k;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(vec3(0.0), 1.0)).xyz;
	float fade = 1.0 - smoothstep(28.0, 36.0, distance(origin.xz, view_position.xz));
	float tip = UV.y;
	float blade = floor(UV.x);
	float seed = INSTANCE_CUSTOM.x;
	float shape = fract(sin(seed * 91.73 + blade * 31.17) * 43758.5453);
	float turn = (shape - 0.5) * 0.55;
	mat2 rotate = mat2(vec2(cos(turn), -sin(turn)), vec2(sin(turn), cos(turn)));
	VERTEX.xz = rotate * VERTEX.xz * max(INSTANCE_CUSTOM.w, 0.85);
	NORMAL.xz = rotate * NORMAL.xz;
	VERTEX.y *= 0.90 + shape * 0.20;
	vec2 lean = normalize(vec2(sin(blade * 2.4 + seed), cos(blade * 2.4 + seed)));
	VERTEX.xz += lean * tip * tip * max(INSTANCE_CUSTOM.z, 0.04);
	float present = step(blade + 0.5, clamp(INSTANCE_CUSTOM.y, 10.0, 14.0));
	VERTEX *= fade * present;
	VERTEX.xz += vec2(1.0, 0.35) * sin(TIME * 1.6 + origin.x * 0.8 + origin.z * 0.6 + seed * 4.0)
		* tip * tip * 0.035 * breeze * fade * present;
	// A grass bed follows the ground's diffuse palette. Keep the actual
	// curved normal for the two-sided leaf response and transmission.
	blade_normal = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * NORMAL, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.80));
	blade_colour = COLOR.rgb;
	ei_e = vec3(0.0);
	ei_k = 0.0;
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	ALBEDO = OUTPUT_IS_SRGB ? blade_colour : ei_lin(blade_colour);
	NORMAL = normalize(blade_normal) * (FRONT_FACING ? 1.0 : -1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Both sides of a thin leaf transmit a little of the same scene light.
	// Native diffuse maxima and the sun's real shadow remain the base draw.
	ei_leaf = 0.35;
}
"""

var terrain: EITerrain
var soft_ground: SoftGroundDeform
var _grass := false
var _chunks := {} # Vector2i -> MultiMeshInstance3D
var _queue: Array[Vector2i] = []
var _images := {} # only original atlases actually visited by the grass
var _mesh: ArrayMesh
var _far_mesh: ArrayMesh
var _material: ShaderMaterial
var _growth_noise: FastNoiseLite
var _focus := Vector2i(-1000, -1000)
var _sample_p := Vector2(INF, INF)
var _sample := {}
var _scenery := {} # chunk -> local expanded mesh boxes and inverse transforms
var _scenery_signature := []


static func create(t: EITerrain) -> TerrainDetails:
	var n := TerrainDetails.new()
	n.name = "TerrainDetails"
	n.terrain = t
	t.add_child(n)
	n.apply_options()
	return n


func _ready() -> void:
	GameData.options_changed.connect(apply_options)


func _exit_tree() -> void:
	_clear_grass()
	if is_instance_valid(soft_ground):
		soft_ground.clear()


func apply_options() -> void:
	_grass = Gfx.on("gfx_grass")
	if not _grass:
		_clear_grass()
	elif _material:
		_material.set_shader_parameter("breeze", float(Gfx.on("gfx_wind")))
	if Gfx.on("gfx_soft_ground"):
		if not is_instance_valid(soft_ground):
			soft_ground = SoftGroundDeform.new()
			soft_ground.name = "SoftGround"
			soft_ground.terrain = terrain
			add_child(soft_ground)
		soft_ground.refresh_materials()
	elif is_instance_valid(soft_ground):
		soft_ground.clear()
		soft_ground.queue_free()
		soft_ground = null


func add_step(x: float, y: float, a: float, b: float, angle: float) -> void:
	if is_instance_valid(soft_ground) and Gfx.on("gfx_soft_ground"):
		soft_ground.add_step(Vector2(x, y), Vector2(a, b), angle)


func water_changed() -> void:
	# Scripted flooding must not leave blades emerging from submerged grass.
	_clear_grass()
	if is_instance_valid(soft_ground):
		soft_ground.refresh_materials()


func _process(_dt: float) -> void:
	if not _grass or not is_instance_valid(terrain):
		return
	_update_scenery()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Ground intersection follows a tilted field/menu camera, rather than its
	# elevated position. This also puts visible grass in the graphics test.
	var p := camera.global_position
	var ray := -camera.global_basis.z
	if ray.y < -0.05:
		var h := terrain.height_at(p.x, -p.z)
		p += ray * maxf((h - p.y) / ray.y, 0.0)
		p += ray * maxf((terrain.height_at(p.x, -p.z) - p.y) / ray.y, 0.0)
	var focus := Vector2i(floori(p.x / CHUNK), floori(-p.z / CHUNK))
	if focus != _focus:
		_focus = focus
		_stream(focus)
	if _material:
		_material.set_shader_parameter("view_position", p)
	var start := Time.get_ticks_usec()
	while not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		if not _chunks.has(key):
			_build_chunk(key)
		if Time.get_ticks_usec() - start >= BUILD_US:
			break


func _clear_grass() -> void:
	for n: MultiMeshInstance3D in _chunks.values():
		if is_instance_valid(n):
			n.queue_free()
	_chunks.clear()
	_queue.clear()
	_images.clear()
	_sample.clear()
	_sample_p = Vector2(INF, INF)
	_focus = Vector2i(-1000, -1000)
	_scenery.clear()
	_scenery_signature.clear()


## Keep a small spatial index of the placed scenery's individual mesh boxes.
## Whole-object boxes would empty courtyards and the ground under tree crowns.
## The native map revision changes for moved objects and lever states, but not
## walking creatures. This also covers the menu's map, which has no GameWorld.
func _update_scenery() -> void:
	var map := terrain.get_parent() as EIMapScene
	var root: Node3D = map.get_node_or_null("Objects") if map else null
	var world := map.get_parent() as GameWorld if map else null
	var signature := [root.get_instance_id() if root else 0,
		root.get_child_count() if root else 0, world.nav.map_rev if world else 0]
	if signature == _scenery_signature:
		return
	if not _scenery_signature.is_empty():
		_clear_grass()
	else:
		_scenery.clear()
	_scenery_signature = signature
	if root == null or not root.is_inside_tree() or not terrain.is_inside_tree():
		return
	var land_inverse := terrain.global_transform.affine_inverse()
	for object: Node3D in root.get_children():
		var info: Dictionary = object.get_meta("ei", {})
		if String(info.get("kind", "OBJECT")) == "UNIT":
			continue
		# Effect carriers are not solid scenery.
		if String(info.get("template", "")).to_lower().begins_with("ef"):
			continue
		for mesh: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			_index_scenery_box(mesh.get_aabb(), land_inverse * mesh.global_transform)


func _index_scenery_box(box: AABB, transform: Transform3D) -> void:
	if absf(transform.basis.determinant()) < 1e-10:
		return
	var inverse := transform.affine_inverse()
	# Transform the horizontal circular clearance into each local box axis.
	# Expanding an axis-aligned world box instead would over-clear diagonal walls.
	var b := inverse.basis
	var padding := Vector3(Vector2(b.x.x, b.z.x).length(), Vector2(b.x.y, b.z.y).length(),
		Vector2(b.x.z, b.z.z).length()) * SCENERY_RADIUS
	var expanded := AABB(box.position - padding, box.size + padding * 2.0)
	var bounds: AABB = transform * box
	var lo := Vector2(bounds.position.x, -bounds.end.z) - Vector2.ONE * SCENERY_RADIUS
	var hi := Vector2(bounds.end.x, -bounds.position.z) + Vector2.ONE * SCENERY_RADIUS
	var first := Vector2i((lo / CHUNK).floor())
	var last := Vector2i((hi / CHUNK).floor())
	var record := {"inverse": inverse, "box": expanded}
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			if not _scenery.has(key):
				_scenery[key] = []
			_scenery[key].append(record)


func scenery_clear(p: Vector2, height: float) -> bool:
	var key := Vector2i((p / CHUNK).floor())
	for record: Dictionary in _scenery.get(key, []):
		var inverse: Transform3D = record.inverse
		var from := inverse * Vector3(p.x, height - 0.025, -p.y)
		var to := inverse * Vector3(p.x, height + SCENERY_HEIGHT, -p.y)
		var box: AABB = record.box
		if box.intersects_segment(from, to) != null:
			return false
	return true


func _stream(focus: Vector2i) -> void:
	var wanted: Array[Vector2i] = []
	var size := terrain.size_ei()
	for y in range(focus.y - 5, focus.y + 6):
		for x in range(focus.x - 5, focus.x + 6):
			var k := Vector2i(x, y)
			if x < 0 or y < 0 or x * CHUNK >= size.x or y * CHUNK >= size.y:
				continue
			if Vector2(k - focus).length_squared() <= 25.0:
				wanted.append(k)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - focus).length_squared() < Vector2(b - focus).length_squared())
	if wanted.size() > MAX_CHUNKS:
		wanted.resize(MAX_CHUNKS)
	for k: Vector2i in _chunks.keys():
		if not wanted.has(k):
			(_chunks[k] as MultiMeshInstance3D).queue_free()
			_chunks.erase(k)
		else:
			# Keep every tuft in the near bed. Distant chunks use fewer curve
			# segments and leaves rather than thinning their ground coverage.
			(_chunks[k] as MultiMeshInstance3D).multimesh.mesh = _chunk_mesh(k)
	_queue.clear()
	for k in wanted:
		if not _chunks.has(k):
			_queue.append(k)


static func green_colour(c: Color) -> bool:
	# Green ground materials include painted paths and grey boulders. Test
	# their authored colour too; brightness alone would fill those with grass.
	return c.g > 0.075 and c.g > c.r * 1.035 + 0.008 and c.g > c.b * 1.10 + 0.008


func ground_colour(x: float, y: float) -> Color:
	var sample := surface_sample(Vector2(x, y))
	if sample.is_empty():
		return Color.TRANSPARENT
	var code: int = sample.code
	var atlas := (code >> 6) & 255
	if not _images.has(atlas):
		if _images.size() >= 8:
			_images.erase(_images.keys()[0])
		_images[atlas] = GameData.load_image("%s%03d" % [terrain.resource_prefix, atlas])
	var image: Image = _images[atlas]
	if image == null:
		return Color.TRANSPARENT
	var uv: Vector2 = sample.uv
	return image.get_pixelv(Vector2i(uv * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE))


## The actual jittered triangle beneath a blade, not a bilinear cell height.
## Using its UVs also avoids spreading grass across a shifted painted path.
func surface_sample(p: Vector2) -> Dictionary:
	if p == _sample_p:
		return _sample
	_sample_p = p
	_sample = {}
	var size := terrain.size_ei()
	if p.x < 0.0 or p.y < 0.0 or p.x >= size.x or p.y >= size.y:
		return _sample
	var cell := Vector2i(p.floor())
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1),
			Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var q := cell + offset
		if q.x < 0 or q.y < 0 or q.x >= int(size.x) or q.y >= int(size.y):
			continue
		var corners := [q, q + Vector2i(1, 0), q + Vector2i(0, 1), q + Vector2i.ONE]
		var points: Array[Vector2] = []
		var heights: Array[float] = []
		for c: Vector2i in corners:
			var id := c.y * terrain.grid_w + c.x
			points.append(Vector2(c) + terrain.land_xy[id])
			heights.append(terrain.heights[id])
		for tri: Array in [[2, 1, 0], [1, 2, 3]]:
			var a: Vector2 = points[tri[0]]
			var b: Vector2 = points[tri[1]]
			var c: Vector2 = points[tri[2]]
			var determinant := (b - a).cross(c - a)
			if absf(determinant) < 1e-7:
				continue
			var u := (p - a).cross(c - a) / determinant
			var v := (b - a).cross(p - a) / determinant
			if u < -1e-5 or v < -1e-5 or u + v > 1.00001:
				continue
			var code: int = terrain.land_tile[(q.y / 2) * terrain.sectors_x * EITerrain.TILES + q.x / 2]
			var uv := Vector2.ZERO
			var h := 0.0
			var weights := [1.0 - u - v, u, v]
			var vertices: Array[Vector3] = []
			for j in 3:
				var at: int = tri[j]
				var corner: Vector2i = corners[at] - Vector2i(q.x / 2, q.y / 2) * 2
				uv += (terrain._tile_uv(code, corner.x, corner.y)[0] as Vector2) * weights[j]
				h += heights[at] * weights[j]
				vertices.append(Vector3(points[at].x, heights[at], -points[at].y))
			var normal := (vertices[2] - vertices[0]).cross(vertices[1] - vertices[0]).normalized()
			_sample = {"code": code, "uv": uv, "height": h, "normal": normal}
			return _sample
	return _sample


func grass_allowed(p: Vector2, include_scenery := true) -> bool:
	var size := terrain.size_ei()
	if p.x < 0.0 or p.y < 0.0 or p.x >= size.x or p.y >= size.y:
		return false
	if not terrain.ground_type(p.x, p.y) in GRASS_TYPES:
		return false
	var sample := surface_sample(p)
	if sample.is_empty() or absf((sample.normal as Vector3).y) < 0.80:
		return false
	var h: float = sample.height
	if terrain.ground_at(p.x, p.y) > h + 0.08 or terrain.water_at(p.x, p.y) > h - 0.035:
		return false
	return green_colour(ground_colour(p.x, p.y)) and (not include_scenery or scenery_clear(p, h))


func _build_chunk(key: Vector2i) -> void:
	if _mesh == null:
		_mesh = blade_mesh()
		_far_mesh = blade_mesh(false)
		_material = ShaderMaterial.new()
		_material.shader = Gfx.make_shader(GRASS_SHADER, true, true)
		_material.set_shader_parameter("breeze", float(Gfx.on("gfx_wind")))
		_material.set_shader_parameter("view_position", Vector3(_focus.x * CHUNK, 0.0, -_focus.y * CHUNK))
	var data := instances(key)
	var transforms: Array[Transform3D] = data.transforms
	var colours: Array[Color] = data.colours
	var custom: Array[Color] = data.custom
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = _chunk_mesh(key)
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		multi.set_instance_color(i, colours[i])
		multi.set_instance_custom_data(i, custom[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Grass_%d_%d" % [key.x, key.y]
	node.multimesh = multi
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	node.extra_cull_margin = 0.15
	# Layer1 participates in the existing sun caster mask; land's excluded
	# receiver/decal layers would silently suppress the grass shadows.
	node.layers = 1
	add_child(node)
	_chunks[key] = node


func _chunk_mesh(key: Vector2i) -> ArrayMesh:
	return _mesh if Vector2(key - _focus).length_squared() * CHUNK * CHUNK <= NEAR_RANGE * NEAR_RANGE else _far_mesh


## Coherent growth patches cross chunk boundaries; the independent seeded
## tuft shapes keep even one patch from looking like repeated copies.
func growth(p: Vector2) -> float:
	if _growth_noise == null:
		_growth_noise = FastNoiseLite.new()
		_growth_noise.seed = terrain.map_name.hash() & 0x7fffffff
		_growth_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_growth_noise.frequency = 0.10
		_growth_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_growth_noise.fractal_octaves = 2
	return smoothstep(-0.45, 0.55, _growth_noise.get_noise_2d(p.x, p.y))


func instances(key: Vector2i) -> Dictionary:
	_update_scenery()
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	var custom: Array[Color] = []
	var first := Vector2(key) * CHUNK
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d" % [terrain.map_name, key.x, key.y])
	for y in ceili(CHUNK / SPACING):
		for x in ceili(CHUNK / SPACING):
			var p := first + Vector2((x + rng.randf_range(0.08, 0.92)) * SPACING,
				(y + rng.randf_range(0.08, 0.92)) * SPACING)
			var lush := growth(p)
			if rng.randf() > lerpf(0.78, 1.0, lush):
				continue
			if p.x >= first.x + CHUNK or p.y >= first.y + CHUNK or not grass_allowed(p, false):
				continue
			var c := ground_colour(p.x, p.y)
			# The authored atlas supplies the palette. Patch ripeness changes its
			# warmth gently rather than replacing native greens with a flat tint.
			c *= Color(lerpf(1.20, 0.97, lush), lerpf(1.02, 1.14, lush), 0.94)
			c *= rng.randf_range(0.96, 1.14)
			c.r = minf(c.r, 0.75)
			c.g = minf(c.g, 0.80)
			c.b = minf(c.b, 0.60)
			c.a = 1.0
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			var width := rng.randf_range(0.86, 1.22)
			var height := rng.randf_range(0.88, 1.12) * lerpf(0.80, 1.05, lush)
			basis = basis.scaled(Vector3(width, height, width))
			var tr := Transform3D(basis, Vector3(p.x, float(surface_sample(p).height) - 0.008, -p.y))
			var shape := Color(rng.randf(), float(rng.randi_range(10, BLADES)), rng.randf_range(0.04, 0.11), rng.randf_range(0.85, 1.15))
			# Consume the complete tuft's seeded variation before rejecting it:
			# moving a door only clears its grass, without rearranging the meadow.
			if not scenery_clear(p, tr.origin.y + 0.008):
				continue
			colours.append(c)
			transforms.append(tr)
			custom.append(shape)
	return {"transforms": transforms, "colours": colours, "custom": custom}


static func blade_mesh(detailed: bool = true) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var count := BLADES if detailed else 6
	var rows := BLADE_ROWS if detailed else 4
	for i in count:
		var blade := i if detailed else int(i * BLADES / float(count))
		var turn := Basis(Vector3.UP, blade * 2.39996 + sin(blade * 2.1) * 0.24)
		var base := vertices.size()
		var height: float = [0.68, 0.57, 0.64, 0.61, 0.70, 0.58, 0.66, 0.55, 0.63, 0.69, 0.59, 0.65, 0.56, 0.62][blade]
		var lean := 0.11 + 0.07 * (0.5 + 0.5 * sin(blade * 1.7))
		var root := 0.025 + 0.045 * (0.5 + 0.5 * cos(blade * 2.1))
		for row in rows:
			var t := row / float(rows - 1)
			var width := (0.025 + 0.007 * sin(blade * 1.9)) * pow(1.0 - t, 0.65) * (0.75 + 0.30 * sin(t * PI)) + 0.00025
			var center := Vector3(0.0, height * (t - 0.075 * t * t * t), root + lean * t * t)
			var normal := Vector3(0.0, -2.0 * lean * t, height * (1.0 - 0.225 * t * t)).normalized()
			for side in [-1.0, 1.0]:
				vertices.append(turn * (center + Vector3(side * width, 0.0, 0.0)))
				normals.append(turn * normal)
				var shade := 0.88 + 0.12 * t
				colours.append(Color(shade, shade, shade, 1.0))
				uvs.append(Vector2(blade, t))
		for row in rows - 1:
			var a := base + row * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	# Keep every tuft and leaf. Only merge short segments of the curved
	# blade when the projected mesh detail is small in the current view.
	# Engine mesh LOD also follows zoom, resolution and shadow projections;
	# distance to the ground focus alone kept eight rows at any zoom.
	var lods := {0.035: _blade_indices(count, rows, [0, rows / 2, rows - 1])}
	if detailed:
		lods[0.012] = _blade_indices(count, rows, [0, 2, 4, rows - 1])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return mesh


static func _blade_indices(count: int, rows: int, levels: Array) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for blade in count:
		var base := blade * rows * 2
		for i in levels.size() - 1:
			var a := base + int(levels[i]) * 2
			var b := base + int(levels[i + 1]) * 2
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	return indices
