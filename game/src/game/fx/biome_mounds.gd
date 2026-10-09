extends RefCounted
## Sparse receive-only piles. Their topology is a subset of the original
## terrain's 16-way footprint triangles, so compaction cannot seal a trench.
const Sand = preload("res://src/game/fx/biome_sand_tiles.gd")
const SUBDIV := SoftGroundDeform.SUBDIV
const MAX_MOUNDS := 2
const MAX_VERTICES := 4096 # Per chunk, including separate triangle-edge UVs.
const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
const VERTEX := """
uniform vec3 view_position;
varying float mound_rise;
void vertex() {
	vec3 point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	int packed = int(CUSTOM0.x+0.5);
	ivec2 cell = ivec2(packed/2,int(CUSTOM0.y+0.5));
	bool upper = (packed%2) != 0;
	vec3 a = query_vertex(cell+(upper ? ivec2(1,0) : ivec2(0,1)));
	vec3 b = query_vertex(cell+(upper ? ivec2(0,1) : ivec2(1,0)));
	vec3 c = query_vertex(cell+(upper ? ivec2(1) : ivec2(0)));
	vec3 weights = vec3(1.0-CUSTOM0.z-CUSTOM0.w,CUSTOM0.zw);
	float height = query_elevation(a,b,c,weights,cell);
	float cut = 0.0;
	vec2 state = texelFetch(query_tiles,cell/2,0).rg;
	if (soft_ground && state.y > 0.5 && state.x > 0.0) {
		vec2 p = vec2(point.x,-point.z);
		vec2 origin = vec2(cell/32)*32.0;
		vec2 uv = ((p-origin)*(511.0/32.0)+0.5)/512.0;
		vec4 track = textureLod(query_tracks,vec3(uv,state.x-1.0),0.0);
		float age = max(textureLod(query_clock,vec2(0.5),0.0).r-track.b/max(track.a,1e-5),0.0);
		// Shared normalized compaction, gated on the installed dense mesh.
		cut = clamp(track.r*clamp((240.0-age)/60.0,0.0,1.0)/0.15,0.0,1.0);
	}
	float fade = 1.0-smoothstep(24.0,32.0,distance(CUSTOM1.xy,view_position.xz));
	mound_rise = CUSTOM1.z*fade*(1.0-cut)-0.005;
	VERTEX.y += height-point.y+mound_rise;
	wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	soft_profile = vec2(0.0); ei_e = vec3(0.0); ei_k = 0.0;
}
"""
const FRAGMENT := """
	// Buried rim/trough fragments leave the original terrain visible.
	vec3 shaped = normalize(cross(dFdx(VERTEX),dFdy(VERTEX)));
	if (dot(shaped,NORMAL)<0.0) { shaped = -shaped; }
	if (mound_rise <= 0.0005) { discard; }
	NORMAL = normalize(mix(NORMAL,shaped,smoothstep(0.0,0.035,mound_rise)));
"""
static var _shaders := {}
var enabled := false
var materials := PackedByteArray() # 0 excluded, 1 snow, 2 verified soft sand.
var normals := PackedVector3Array()


static func shader(soft := true) -> Shader:
	# A cached variant still needs the normal Gfx option specialization.
	# Otherwise creating the soft-off variant recompiles land globally, but
	# returning to the cached soft-on variant can leave it specialized off.
	Gfx._set_vol_fog(Gfx.on("gfx_volumetric"))
	if not _shaders.has(soft):
		# Keep the land's original/HD atlas, detail, wetness and lighting path.
		# Only the vertex displacement changes; no per-fragment terrain search.
		var code := EITerrain.TERRAIN_SHADER
		var start := code.find("void vertex() {")
		var end := code.find(GroundSurfaceShader.TILE_FUNCTIONS,start)
		assert(start>0 and end>start)
		var vertex := VERTEX
		if not soft:
			var a := vertex.find("\tint packed")
			var b := vertex.find("\tfloat fade")
			vertex = vertex.substr(0,a)+"\tfloat height = point.y; float cut = 0.0;\n"+vertex.substr(b)
		code = code.substr(0,start)+(GroundSurfaceShader.TRIANGLE_QUERY if soft else "")+vertex+code.substr(end)
		code = code.replace("void fragment() {","void fragment() {"+FRAGMENT)
		_shaders[soft] = Gfx.make_shader(code,true,true)
	return _shaders[soft]


func configure(terrain: EITerrain, field: RefCounted) -> void:
	materials.resize(field.tiles.size())
	if field.biome in ["cave","unknown"]: return
	var sand := {}
	if terrain.texture_size==512 and terrain.tile_size==64:
		for atlas: int in field.images: sand[atlas] = Sand.slots(field.images[atlas])
	for i in materials.size():
		var code: int = field.tiles[i]&0x3fff
		var type := terrain.tile_types[code] if code<terrain.tile_types.size() else -1
		if field.biome=="ingos" and type in [9,12]: materials[i] = 1
		elif type==3 and (code&63) in sand.get(code>>6,[]): materials[i] = 2
	enabled = materials.has(1) or materials.has(2)
	if enabled: normals = terrain.land_n.duplicate()


func kind(field: RefCounted, cell: Vector2i) -> int:
	if cell.x<0 or cell.y<0 or cell.x>=field.size.x or cell.y>=field.size.y: return 0
	return materials[(cell.y/2)*(field.size.x/2)+cell.x/2]


func point(field: RefCounted, p: Vector2i) -> Vector3:
	var at: int = p.y*field.grid_w+p.x
	var xy: Vector2 = Vector2(p)+field.xy[at]
	return Vector3(xy.x,field.heights[at],-xy.y)


static func touches(p: Vector2, radius: float, a: Vector2, b: Vector2, c: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(p,PackedVector2Array([a,b,c])): return true
	for edge in [[a,b],[b,c],[c,a]]:
		if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,edge[0],edge[1]))<=radius*radius: return true
	return false


func footprint(field: RefCounted, p: Vector2, radius: float, type: int, boxes: Array) -> Array:
	# Full circular envelope, including the authored cell jitter and hidden rim.
	var lo := Vector2i((p-Vector2.ONE*(radius+1.0)).floor())
	var hi := Vector2i((p+Vector2.ONE*(radius+1.0)).ceil())
	if lo.x<0 or lo.y<0 or hi.x>=field.size.x or hi.y>=field.size.y: return []
	var triangles := []; var low := INF; var high := -INF
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var cell := Vector2i(x,y)
			for side in 2:
				var grid: Array[Vector2i] = [cell+Vector2i.DOWN,cell+Vector2i.RIGHT,cell]
				if side: grid.assign([cell+Vector2i.RIGHT,cell+Vector2i.DOWN,cell+Vector2i.ONE])
				var vertices: Array[Vector3] = [point(field,grid[0]),point(field,grid[1]),point(field,grid[2])]
				var a := vertices[0]; var b := vertices[1]; var c := vertices[2]
				if not touches(p,radius,Vector2(a.x,-a.z),Vector2(b.x,-b.z),Vector2(c.x,-c.z)): continue
				var normal := (c-a).cross(b-a).normalized()
				# Reject folded/near-vertical source triangles instead of picking
				# the wrong layer. A regular, shallow patch remains watertight.
				if normal.y<0.90 or kind(field,cell)!=type: return []
				for v: Vector3 in vertices: low = minf(low,v.y); high = maxf(high,v.y)
				triangles.append({"cell":cell,"side":side,"grid":grid,"vertices":vertices})
	if triangles.is_empty() or high-low>0.65: return []
	var first := Vector2i((p-Vector2.ONE*radius).floor()); var last := Vector2i((p+Vector2.ONE*radius).floor())
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var at: int = y*field.size.x+x
			if field.water[at]>low-0.06 or field.surface[at]>low+0.08: return []
	var box := AABB(Vector3(p.x-radius,low-0.04,-p.y-radius),Vector3(radius*2,high-low+0.65,radius*2))
	for obstacle: Dictionary in boxes:
		if (obstacle.box as AABB).intersects((obstacle.inverse as Transform3D)*box): return []
	return triangles


static func rise(delta: Vector2, radius: float, height: float, phase: float) -> float:
	var a := delta.angle()
	var wobble := 1.0+0.11*sin(2*a+phase)+0.06*sin(3*a-phase)
	var r := delta.length()/(radius*wobble)
	var fall := maxf(0,1-r*r)
	return height*fall*fall*(1+0.22*r*cos(a)+0.10*r*r*sin(2*a-phase))


func records(field: RefCounted, key: Vector2i, boxes: Array) -> Array:
	var out := []
	if not enabled: return out
	var rng := RandomNumberGenerator.new(); rng.seed = hash("%s:mounds:%d:%d" % [field.map_name,key.x,key.y])
	for i in 4:
		var rx := rng.randf_range(-0.45,0.45); var ry := rng.randf_range(-0.45,0.45)
		var p := Vector2(key)*8+Vector2(2+(i%2)*4,2+(i/2)*4)+Vector2(rx,ry)
		var size_roll := rng.randf(); var height_roll := rng.randf(); var phase := rng.randf()*TAU; var chance := rng.randf()
		var type := kind(field,Vector2i(p.floor()))
		if not type or chance>0.60: continue
		var radius := lerpf(0.55,0.9,size_roll) if type==1 else lerpf(0.4,0.75,size_roll)
		var height := lerpf(0.14,0.23,height_roll) if type==1 else lerpf(0.06,0.10,height_roll)
		var triangles := footprint(field,p,radius*1.17+0.10,type,boxes)
		if triangles.is_empty(): continue
		out.append({"p":p,"kind":type,"radius":radius,"height":height,"phase":phase,"triangles":triangles})
		if out.size()==MAX_MOUNDS: break
	return out


func build(field: RefCounted, key: Vector2i, boxes: Array) -> Dictionary:
	var placed := records(field,key,boxes)
	var vertices := PackedVector3Array(); var directions := PackedVector3Array()
	var uvs := PackedVector2Array(); var layers := PackedVector2Array()
	var anchors := PackedFloat32Array(); var shapes := PackedFloat32Array(); var indices := PackedInt32Array()
	var accepted := []
	for mound: Dictionary in placed:
		var first := vertices.size(); var first_index := indices.size()
		for tri: Dictionary in mound.triangles:
			var ids := {}; var grid: Array[Vector2i] = tri.grid; var points: Array[Vector3] = tri.vertices
			var tile := Vector2i(tri.cell.x/2,tri.cell.y/2)
			var code: int = field.tiles[tile.y*(field.size.x/2)+tile.x]
			var atlas_uv: PackedVector2Array = field.uv_table[code]
			# Adjacent dense triangles share grid vertices. Evaluate the shape
			# once per point rather than repeating its trigonometry per corner.
			var samples := {}; var rises := {}
			for y in range(SUBDIV+1):
				for x in range(SUBDIV+1-y):
					var q := Vector2i(x,y)
					var w := Vector3(1-float(x+y)/SUBDIV,float(x)/SUBDIV,float(y)/SUBDIV)
					var p := points[0]*w.x+points[1]*w.y+points[2]*w.z
					samples[q] = p; rises[q] = rise(Vector2(p.x,-p.z)-mound.p,mound.radius,mound.height,mound.phase)
			for y in SUBDIV:
				for x in range(SUBDIV-y):
					var cells := [[Vector2i(x,y),Vector2i(x+1,y),Vector2i(x,y+1)]]
					if x+y<SUBDIV-1: cells.append([Vector2i(x+1,y),Vector2i(x+1,y+1),Vector2i(x,y+1)])
					for cell: Array in cells:
						if maxf(rises[cell[0]],maxf(rises[cell[1]],rises[cell[2]]))<=0.0001: continue
						for j in 3:
							var q: Vector2i = cell[j]
							if not ids.has(q):
								ids[q] = vertices.size()
								var w := Vector3(1-float(q.x+q.y)/SUBDIV,float(q.x)/SUBDIV,float(q.y)/SUBDIV)
								var normal := Vector3.ZERO; var uv := Vector2.ZERO
								for k in 3:
									var at := grid[k]-tile*2
									uv += atlas_uv[at.y*3+at.x]*w[k]
									if not normals.is_empty(): normal += normals[grid[k].y*field.grid_w+grid[k].x]*w[k]
								vertices.append(samples[q]-Vector3(key.x*8,0,-key.y*8)); directions.append(normal.normalized() if normal.length_squared()>0.01 else Vector3.UP)
								uvs.append(uv); layers.append(Vector2((code>>6)&255,tile.y*(field.size.x/2)+tile.x))
								anchors.append_array([tri.cell.x*2+tri.side,tri.cell.y,w.y,w.z])
								shapes.append_array([mound.p.x,-mound.p.y,rises[q],mound.height])
							indices.append(ids[q])
		if vertices.size()>MAX_VERTICES:
			vertices.resize(first); directions.resize(first); uvs.resize(first); layers.resize(first)
			anchors.resize(first*4); shapes.resize(first*4); indices.resize(first_index)
			break
		var record := mound.duplicate(); record.erase("triangles"); accepted.append(record)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = directions
	arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_TEX_UV2] = layers
	arrays[Mesh.ARRAY_CUSTOM0] = anchors; arrays[Mesh.ARRAY_CUSTOM1] = shapes; arrays[Mesh.ARRAY_INDEX] = indices
	return {"records":accepted,"arrays":arrays}
