class_name GroundMarkProjection
extends RefCounted
## Clip the same mark rectangle to the
## actual terrain triangles and eligible floor meshes, like the original's
## ground-print geometry. The Decal remains the lifetime/visibility owner.
const SOURCE := """shader_type spatial;
render_mode cull_disabled, depth_draw_never, ambient_light_disabled;
uniform sampler2D pigment : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity = 1.0;
uniform float centre_height = 0.0;
uniform sampler2D track_clock : filter_nearest;
uniform bool animated_projection = false;
uniform vec2 projection_center;
uniform vec4 projection_axes;
varying vec3 mark_world;
varying vec3 ei_e;
varying float ei_k;
""" + GroundSurfaceShader.LAND_UNIFORMS + GroundSurfaceShader.SOFT_UNIFORMS + GroundSurfaceShader.SOFT_FUNCTIONS + """
void vertex() {
	mark_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (animated_projection) {
		vec2 delta = vec2(VERTEX.x, -VERTEX.z) - projection_center;
		UV = vec2(dot(delta, projection_axes.xy), dot(delta, projection_axes.zw)) + vec2(0.5);
	}
	if (COLOR.r > 0.5 && soft_ground) {
		vec2 profile = soft_profile_grid(UV2);
		VERTEX.y += profile.x;
		if (soft_tracks) {
			VERTEX.y += soft_height(soft_sample(vec2(mark_world.x, -mark_world.z))) * profile.y * soft_track_mask(UV2);
		}
	}
	VERTEX.y += 0.01;
}
void fragment() {
	if (animated_projection && (any(lessThan(UV, vec2(0.0))) || any(greaterThan(UV, vec2(1.0))))) discard;
	vec4 ink = texture(pigment, UV);
	ALBEDO = ink.rgb;
	float alpha = opacity;
	// GLES blends in display space; undo the linear-decal alpha lift there.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	alpha = 1.0 - pow(max(1.0 - opacity, 0.0), 1.0 / 2.2);
#endif
	float height_alpha = clamp((1.0 - abs(mark_world.y - centre_height)) / 0.25, 0.0, 1.0);
	ALPHA = ink.a * alpha * height_alpha * (1.0 - smoothstep(70.0, 85.0, length(VERTEX)));
	FOG = ei_fog_of(VERTEX, mark_world);
}
"""
var world: GameWorld
var surface: GroundSurfaceData
var shader: Shader
var receivers: Array[WeakRef] = []
var _receiver_meshes := {}
var _floor_revision := -1
var key := []
var _verts := PackedVector3Array()
var _uvs := PackedVector2Array()
var _grids := PackedVector2Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _centre := Vector2.ZERO
var _across := Vector2.ZERO
var _along := Vector2.ZERO
var _half := Vector2.ZERO
var _bounds := Rect2()
var _height := 0.0

func _init(w: GameWorld) -> void:
	world = w
	surface = w.terrain.ground_surface_data(true)
	shader = Gfx.make_shader(SOURCE.replace("soft_track_time -", "texelFetch(track_clock, ivec2(0), 0).r -"))
	refresh_receivers()

func refresh_receivers() -> void:
	receivers.clear()
	_receiver_meshes.clear()
	_floor_revision = world.nav.floor_rev if world.nav else 0
	for mesh: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if mesh.layers & EITerrain.DECAL_LAYER and not world.terrain.is_ancestor_of(mesh):
			receivers.append(weakref(mesh))

func receiver_arrays(mesh: Mesh) -> Array:
	if not _receiver_meshes.has(mesh):
		var arrays := []
		for i in mesh.get_surface_count(): arrays.append(mesh.surface_get_arrays(i))
		_receiver_meshes[mesh] = arrays
	return _receiver_meshes[mesh]

func create(mark: GroundMarks.Mark) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "ProjectedMark"
	mesh.top_level = true
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("pigment", mark.decal.texture_albedo)
	material.set_shader_parameter("opacity", mark.decal.modulate.a)
	mesh.material_override = material
	mark.decal.add_child(mesh)
	mesh.global_transform = world.global_transform
	mark.projection = mesh
	bind(material)
	place(mark)

## Ground marks first appear when a unit walks or bleeds. Warm the same
## colored, two-UV vertex layout while the zone's loading cover is visible.
func warmup_variant() -> Array:
	var material := ShaderMaterial.new()
	material.shader = shader
	bind(material)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
	arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return [material,mesh]

func bind(material: ShaderMaterial) -> void:
	surface.bind(material, true)
	var terrain := world.terrain
	var soft := terrain.details.soft_ground if is_instance_valid(terrain.details) else null
	material.set_shader_parameter("soft_tracks", soft != null)
	if soft:
		var field: SoftGroundField = soft.shared_field()
		material.set_shader_parameter("soft_track_texture", field.texture)
		material.set_shader_parameter("track_clock", field.clock)

func sync(lists: Array) -> void:
	var terrain := world.terrain
	var soft := terrain.details.soft_ground if is_instance_valid(terrain.details) else null
	if _floor_revision != (world.nav.floor_rev if world.nav else 0): refresh_receivers()
	var next := [Gfx.on("gfx_soft_ground"), soft, hash(terrain.water_offsets), _floor_revision]
	for ref in receivers:
		var node := ref.get_ref() as MeshInstance3D
		if node: next.append([node.is_visible_in_tree(),node.global_transform,node.mesh])
	if next == key: return
	key = next
	for list in lists:
		for mark: GroundMarks.Mark in list:
			bind(mark.projection.material_override)
			place(mark, true)

func place(mark: GroundMarks.Mark, rebuild := false) -> void:
	_centre = Vector2(mark.x, mark.y)
	_across = Vector2(mark.decal.basis.x.x, -mark.decal.basis.x.z)
	_along = Vector2(mark.decal.basis.z.x, -mark.decal.basis.z.z)
	_half = Vector2(maxf(mark.a, 0.01), maxf(mark.b, 0.01))
	_height = mark.decal.position.y
	var material: ShaderMaterial = mark.projection.material_override
	material.set_shader_parameter("centre_height",_height + world.global_position.y)
	material.set_shader_parameter("animated_projection",not mark.foot)
	if not mark.foot:
		# Blood keeps turning for its entire lifetime. Re-clipping and
		# tessellating every pool at every tick causes a frame-time feedback
		# loop once several kills leave marks behind. Clip a conservative patch
		# once; the shader projects the exact current rectangle onto that patch.
		material.set_shader_parameter("projection_center",_centre)
		material.set_shader_parameter("projection_axes",Vector4(
			_across.x/(_half.x*2.0),_across.y/(_half.x*2.0),
			_along.x/(_half.y*2.0),_along.y/(_half.y*2.0)))
		var grown := Vector2(mark.a,mark.b) + Vector2.ONE * mark.grow * maxi(mark.grow_left,0)
		var radius := maxf(_half.length(),grown.max(Vector2.ONE*0.01).length())
		var origin := Vector3(mark.x,mark.y,_height)
		if not rebuild and mark.projection.mesh != null and origin.is_equal_approx(mark.projection_origin) \
				and radius <= mark.projection_radius + 0.0001:
			return
		mark.projection_radius = radius
		mark.projection_origin = origin
		_across = Vector2.RIGHT; _along = Vector2.DOWN
		_half = Vector2.ONE * radius
	_verts.clear(); _uvs.clear(); _grids.clear(); _normals.clear(); _colors.clear()
	var radius := _across.abs() * _half.x + _along.abs() * _half.y
	_bounds = Rect2(_centre - radius, radius * 2.0)
	var terrain := world.terrain
	var first := Vector2i((_bounds.position - Vector2.ONE).floor()).max(Vector2i.ZERO)
	var last := Vector2i((_bounds.end + Vector2.ONE).ceil()).min(Vector2i(terrain.size_ei()) - Vector2i.ONE)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var corners: Array[Vector2] = [Vector2(x,y),Vector2(x+1,y),Vector2(x,y+1),Vector2(x+1,y+1)]
			var points: Array[Vector3] = []
			for grid in corners:
				var i := int(grid.y) * terrain.grid_w + int(grid.x)
				var xy := grid + terrain.land_xy[i]
				points.append(Vector3(xy.x,terrain.heights[i],-xy.y))
			for ids: Array in [[2,1,0],[1,2,3]]:
				triangle([points[ids[0]],points[ids[1]],points[ids[2]]],
					[corners[ids[0]],corners[ids[1]],corners[ids[2]]], 4 if Gfx.on("gfx_soft_ground") else 0, true)
	for ref in receivers:
		var receiver := ref.get_ref() as MeshInstance3D
		if receiver == null or receiver.mesh == null or not receiver.is_visible_in_tree(): continue
		var xf := world.global_transform.affine_inverse() * receiver.global_transform
		var box := xf * receiver.get_aabb()
		if not Rect2(Vector2(box.position.x,-box.end.z),Vector2(box.size.x,box.size.z)).intersects(_bounds): continue
		for arrays: Array in receiver_arrays(receiver.mesh):
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for j in range(0,count-2,3):
				var p: Array[Vector3] = []
				for k in 3: p.append(xf * vertices[indices[j+k] if not indices.is_empty() else j+k])
				triangle(p,[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],0,false)
	var mesh := ArrayMesh.new()
	if not _verts.is_empty():
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=_verts; arrays[Mesh.ARRAY_NORMAL]=_normals
		arrays[Mesh.ARRAY_TEX_UV]=_uvs; arrays[Mesh.ARRAY_TEX_UV2]=_grids; arrays[Mesh.ARRAY_COLOR]=_colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mark.projection.mesh = mesh

func triangle(p: Array, grid: Array, depth: int, land: bool) -> void:
	var rect := Rect2(Vector2(p[0].x,-p[0].z),Vector2.ZERO)
	for v: Vector3 in p: rect=rect.expand(Vector2(v.x,-v.z))
	if not rect.intersects(_bounds): return
	if minf(p[0].y,minf(p[1].y,p[2].y)) > _height+GroundMarks.DEPTH*.5 or maxf(p[0].y,maxf(p[1].y,p[2].y)) < _height-GroundMarks.DEPTH*.5: return
	var normal: Vector3 = (p[2]-p[0]).cross(p[1]-p[0]).normalized()
	if absf(normal.y)<0.01: return
	if normal.y<0.0: normal=-normal
	if depth>0:
		var ab: Vector3=(p[0]+p[1])*.5; var bc: Vector3=(p[1]+p[2])*.5; var ca: Vector3=(p[2]+p[0])*.5
		var ga: Vector2=(grid[0]+grid[1])*.5; var gb: Vector2=(grid[1]+grid[2])*.5; var gc: Vector2=(grid[2]+grid[0])*.5
		triangle([p[0],ab,ca],[grid[0],ga,gc],depth-1,land)
		triangle([ab,p[1],bc],[ga,grid[1],gb],depth-1,land)
		triangle([ca,bc,p[2]],[gc,gb,grid[2]],depth-1,land)
		triangle([ab,bc,ca],[ga,gb,gc],depth-1,land)
		return
	var poly := []
	for i in 3:
		var delta := Vector2(p[i].x,-p[i].z)-_centre
		var uv := Vector2(delta.dot(_across),delta.dot(_along))/_half*.5+Vector2(.5,.5)
		poly.append([p[i],grid[i],Vector3(uv.x,uv.y,(p[i].y-_height)/GroundMarks.DEPTH+.5)])
	for axis in 3:
		for edge in [0.0,1.0]:
			var clipped := []
			if poly.is_empty(): return
			var previous: Array=poly[-1]
			for current: Array in poly:
				var a: float=previous[2][axis]; var b: float=current[2][axis]
				var inside_a: bool=a>=edge if edge==0.0 else a<=edge
				var inside_b: bool=b>=edge if edge==0.0 else b<=edge
				if inside_a!=inside_b:
					var t: float=(edge-a)/(b-a)
					clipped.append([previous[0].lerp(current[0],t),previous[1].lerp(current[1],t),previous[2].lerp(current[2],t)])
				if inside_b: clipped.append(current)
				previous=current
			poly=clipped
	for i in range(1,poly.size()-1):
		for vertex: Array in [poly[0],poly[i],poly[i+1]]:
			_verts.append(vertex[0]);_grids.append(vertex[1]);_uvs.append(Vector2(vertex[2].x,vertex[2].y));_normals.append(normal)
			_colors.append(Color(1 if land else 0,0,0,1))
