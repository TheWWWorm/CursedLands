extends RefCounted
## Small static ambient contacts complement the sun shadow, whose normal bias
## exceeds the height of some pebbles. One batch per cover chunk, no per-rock
## nodes, textures or frame updates. The existing contact-shadow option owns it.
const FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
const RADIUS := 0.14
const LIFT := 0.002
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 view_position;
varying float contact_fade;
void vertex() {
	vec3 origin = (MODEL_MATRIX*vec4(UV2.x,0.0,UV2.y,1.0)).xyz;
	float distance_to_view = distance(origin.xz,view_position.xz);
	contact_fade = (1.0-smoothstep(28.0,36.0,distance_to_view))
		*mix(1.0,step(COLOR.r,0.35),smoothstep(18.0,28.0,distance_to_view));
	// SURFACE
}
void fragment() {
	float contact = (1.0-smoothstep(0.35,1.0,length(UV)))*0.42*contact_fade;
	contact *= 1.0-ei_fog_of(VERTEX,(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz).a;
	vec3 factor = vec3(1.0-contact);
	ALBEDO = OUTPUT_IS_SRGB ? factor : ei_lin(factor);
	ALPHA = 1.0;
}
"""
const ATTACH := """
	int packed = int(CUSTOM0.x+0.5);
	ivec2 cell = ivec2(packed/2,int(CUSTOM0.y+0.5));
	bool upper = (packed%2) != 0;
	vec3 a = query_vertex(cell+(upper ? ivec2(1,0) : ivec2(0,1)));
	vec3 b = query_vertex(cell+(upper ? ivec2(0,1) : ivec2(1,0)));
	vec3 c = query_vertex(cell+(upper ? ivec2(1) : ivec2(0)));
	vec3 weights = vec3(1.0-CUSTOM0.z-CUSTOM0.w,CUSTOM0.zw);
	VERTEX.y = query_elevation(a,b,c,weights,cell)+0.002;
"""
static var _shaders := {}


static func shader(soft: bool) -> Shader:
	Gfx._set_vol_fog(Gfx.on("gfx_volumetric"))
	if not _shaders.has(soft):
		var code := SHADER
		if soft:
			code = code.replace("void vertex() {","uniform sampler2D terrain_tiles : filter_nearest, repeat_disable;\nuniform sampler2D terrain_cells : filter_nearest, repeat_disable;\n"+GroundSurfaceShader.SOFT_UNIFORMS+GroundSurfaceShader.SOFT_FUNCTIONS+GroundSurfaceShader.TRIANGLE_QUERY+"\nvoid vertex() {")
			code = code.replace("// SURFACE",ATTACH)
		_shaders[soft] = Gfx.make_shader(code,false)
	return _shaders[soft]


static func build(field: RefCounted, records: Array[Dictionary], key: Vector2i) -> Array:
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array()
	var roots := PackedVector2Array(); var colours := PackedColorArray()
	var anchors := PackedFloat32Array(); var indices := PackedInt32Array()
	for record: Dictionary in records:
		if int(record.kind)!=5: continue
		var centre: Vector2 = record.p
		var radius := RADIUS*float(record.scale)
		var disk := PackedVector2Array()
		for i in 16: disk.append(centre+Vector2.from_angle(i*TAU/16.0)*radius)
		# Clip to the authored triangles instead of bridging terrain edges with
		# a flat billboard. Those same barycentric anchors follow soft ground.
		var lo := Vector2i((centre-Vector2.ONE*(radius+1.0)).floor()).max(Vector2i.ZERO)
		var hi := Vector2i((centre+Vector2.ONE*(radius+1.0)).floor()).min(field.size-Vector2i.ONE)
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				var cell := Vector2i(x,y)
				for side in 2:
					var corners := [cell+Vector2i.DOWN,cell+Vector2i.RIGHT,cell] if side==0 else [cell+Vector2i.RIGHT,cell+Vector2i.DOWN,cell+Vector2i.ONE]
					var xy := PackedVector2Array(); var heights := PackedFloat32Array()
					for corner: Vector2i in corners:
						var at: int = corner.y*field.grid_w+corner.x
						xy.append(Vector2(corner)+field.xy[at]); heights.append(field.heights[at])
					var determinant := (xy[1]-xy[0]).cross(xy[2]-xy[0])
					if absf(determinant)<1e-7: continue
					for polygon: PackedVector2Array in Geometry2D.intersect_polygons(disk,xy):
						var pieces: Array[PackedVector2Array] = [polygon]
						if (record.get("anchor",Vector4(-1,0,0,0)) as Vector4).x>=0.0:
							pieces = dense_pieces(polygon,xy,determinant)
						for piece: PackedVector2Array in pieces:
							var triangles := Geometry2D.triangulate_polygon(piece)
							if triangles.is_empty(): continue
							var first := vertices.size()
							for point: Vector2 in piece:
								var u := (point-xy[0]).cross(xy[2]-xy[0])/determinant
								var v := (xy[1]-xy[0]).cross(point-xy[0])/determinant
								var height := heights[0]*(1.0-u-v)+heights[1]*u+heights[2]*v
								var local := point-Vector2(key)*8.0
								vertices.append(Vector3(local.x,height+LIFT,-local.y))
								uvs.append((point-centre)/radius)
								roots.append(Vector2(centre.x-key.x*8.0,-centre.y+key.y*8.0))
								colours.append(Color(record.seed,0,0,1))
								anchors.append_array([x*2+side,y,u,v])
							for index: int in triangles: indices.append(first+index)
	if indices.is_empty(): return []
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = roots; arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_CUSTOM0] = anchors; arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func dense_pieces(polygon: PackedVector2Array, xy: PackedVector2Array, determinant: float) -> Array[PackedVector2Array]:
	# The contact patch must share the dense terrain edges, too. Interpolating
	# just the coarse perimeter would cut through footprints between vertices.
	var bounds := Rect2(Vector2.ONE*INF,Vector2.ZERO)
	for point: Vector2 in polygon:
		var uv := Vector2((point-xy[0]).cross(xy[2]-xy[0]),(xy[1]-xy[0]).cross(point-xy[0]))/determinant
		if not bounds.position.is_finite(): bounds.position=uv
		else: bounds=bounds.expand(uv)
	var lo := Vector2i((bounds.position*16.0).floor()).max(Vector2i.ZERO)
	var hi := Vector2i((bounds.end*16.0).floor()).min(Vector2i(15,15))
	var result: Array[PackedVector2Array] = []
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			if x+y>15: continue
			for side in (1 if x+y==15 else 2):
				var offsets := [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN] if side==0 else [Vector2i.RIGHT,Vector2i.ONE,Vector2i.DOWN]
				var triangle := PackedVector2Array()
				for offset: Vector2i in offsets:
					var uv := Vector2(Vector2i(x,y)+offset)/16.0
					triangle.append(xy[0]*(1.0-uv.x-uv.y)+xy[1]*uv.x+xy[2]*uv.y)
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon,triangle): result.append(clipped)
	return result
