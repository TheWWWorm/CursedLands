extends RefCounted
## Bounded distant grass. No near generator, seed or native API changes.
## TerrainDetails remains the owner of the immutable field and revision barrier.
const Sampler = preload("res://src/game/fx/biome_cover.gd")
const Wind = preload("res://src/game/fx/weather_wind.gd")
const TILE := 24.0
const CELLS := 40
const SPACING := TILE / CELLS
const MAX_TILES := 128
const TRIANGLES := 6
const FOOTPRINT := 0.36
const SHADER := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
#define EI_GRASS_LIGHT
render_mode cull_disabled, ambient_light_disabled;
uniform vec3 view_position;
uniform float breeze = 1.0;
uniform float density_bias = 0.0;
uniform float stream_clock = 0.0;
varying vec3 blade_colour;
varying vec3 blade_normal;
varying vec3 ei_e;
varying float ei_k;
""" + Wind.UNIFORMS + Wind.SWAY + """
float density_at_level(float level, float member, float distant) {
	return member < level ? 0.0 : (member < level+0.5 ? 1.0-distant : 1.0);
}
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(vec3(0.0), 1.0)).xyz;
	// Complement the near field's existing 28..36 m shrink; there are never
	// two full-sized beds or a second set of grass shadow casters here.
	float fade = smoothstep(28.0, 36.0, distance(origin.xz, view_position.xz));
	float depth = -(VIEW_MATRIX * vec4(origin, 1.0)).z;
	// Fine-only roots disappear before a coarse tile can replace them.
	// Parent roots keep the same placement, colour, wind and visibility.
	float lower = floor(density_bias);
	float distant = smoothstep(80.0,96.0,depth);
	fade *= mix(density_at_level(lower,INSTANCE_CUSTOM.z,distant),
		density_at_level(lower+1.0,INSTANCE_CUSTOM.z,distant),fract(density_bias));
	if (INSTANCE_CUSTOM.z < INSTANCE_CUSTOM.y) {
		fade *= smoothstep(INSTANCE_CUSTOM.w,INSTANCE_CUSTOM.w+0.25,stream_clock);
	}
	fade *= 1.0 - smoothstep(max(ei_fog.x, ei_fog.y - 16.0), ei_fog.y, depth);
	float tip = UV.y;
	VERTEX *= fade;
	vec2 sway = wind_state.xy * ei_vegetation_sway(origin.xz, INSTANCE_CUSTOM.x * 4.0, wind_state, wind_phases)
		* tip * tip * 0.035 * wind_state.z * breeze * fade;
	VERTEX += transpose(MODEL_NORMAL_MATRIX) * vec3(sway.x, 0.0, sway.y);
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
	ei_leaf = 0.35;
}
"""

var _field: Field
var _planner := Planner.new()
var _geometry: ArrayMesh
var _material: ShaderMaterial
var _chunks := {}
var _wanted: Array[Vector3i] = []
var _pending := {}
var _work: Job
var _task := -1
var _poll := 0.0
var _clock := 0.0
var _density_bias := 0.0
var _camera_signature := []
var _last_camera: Camera3D
var _owner: TerrainDetails
var _count := 0
var _generation_jobs := 0
var _discarded_jobs := 0
var _max_upload_us := 0
var _max_upload_tiles := 0

## Called by the near owner after updating its camera ground focus. Only
## publication touches the scene; far workers never access this controller.
func tick(details: TerrainDetails, camera: Camera3D, focus: Vector3, delta: float) -> void:
	_owner = details
	_clock += delta
	if not details._grass:
		clear(); return
	if _field == null:
		# Near preparation owns original atlas loading and the native snapshot.
		# Wait for it and for its initial geometry before adding far work.
		if not details._queue.is_empty() or not details._grass_jobs.is_empty(): return
		_field = Field.new(); _field.capture(details)
		_geometry = mesh(); _material = material()
	if _material:
		_material.set_shader_parameter("view_position",focus)
		_material.set_shader_parameter("breeze",float(Gfx.on("gfx_wind")))
		Wind.bind(_material,details.terrain.wind_frame())
		_density_bias=move_toward(_density_bias,float(_planner.diagnostic.get("coarsen_bias",0)),delta/0.3)
		_material.set_shader_parameter("density_bias",_density_bias)
		_material.set_shader_parameter("stream_clock",_clock)
	_poll -= delta
	var signature := [camera.get_camera_transform(),camera.get_camera_projection(),camera.get_viewport().get_visible_rect().size,details.global_transform]
	var turned := not _camera_signature.is_empty() and (signature[0] as Transform3D).basis.z.dot((_camera_signature[0] as Transform3D).basis.z)<cos(deg_to_rad(3.0))
	if _last_camera != camera or (signature != _camera_signature and (_poll<=0.0 or turned)):
		_select(camera)
		_camera_signature = signature; _last_camera = camera; _poll = 0.2
	_finish()
	_commit_ready()
	# At most one lower-priority far task; near streaming owns all four of
	# its existing slots and always dispatches first on a camera move.
	if _work == null and details._queue.is_empty() and details._grass_jobs.is_empty(): _start()
	if _work != null and _task<0:
		var started := Time.get_ticks_usec()
		while not _work.step(4) and Time.get_ticks_usec()-started<500: pass

static func contains_tile(outer: Vector3i, inner: Vector3i) -> bool:
	if outer.z<inner.z: return false
	var shift := outer.z-inner.z
	return (inner.x>>shift)==outer.x and (inner.y>>shift)==outer.y

func _ancestor(key: Vector3i) -> Variant:
	var nearest: Variant = null
	for resident: Vector3i in _chunks:
		if resident!=key and contains_tile(resident,key) and (nearest==null or resident.z<nearest.z): nearest=resident
	return nearest

func _select(camera: Camera3D) -> void:
	var plan := _planner.select(camera,_field,_owner.global_transform)
	_wanted.clear()
	# Refine by one level at a time so a complete replacement group has at
	# most four uploads. Its old parent remains visible until all are ready.
	for key: Vector3i in plan:
		var ancestor: Variant = _ancestor(key)
		if ancestor!=null and ancestor.z>key.z+1:
			var level: int = ancestor.z-1; var shift := level-key.z
			key = Vector3i(key.x>>shift,key.y>>shift,level)
		if not _wanted.has(key): _wanted.append(key)
	for key: Vector3i in _pending.keys():
		if not _wanted.has(key): _pending.erase(key); _discarded_jobs+=1
	for key: Vector3i in _chunks.keys():
		var needed := false
		for wanted: Vector3i in _wanted:
			if contains_tile(key,wanted) or contains_tile(wanted,key): needed=true; break
		if not needed: _retire(key)
	# Coarsening can free the slots needed by a refinement elsewhere.
	_wanted.sort_custom(func(a: Vector3i,b: Vector3i)->bool:
		var ac := _has_descendant(a); var bc := _has_descendant(b)
		return ac if ac!=bc else _planner.box(a).get_center().distance_squared_to(_planner.eye)<_planner.box(b).get_center().distance_squared_to(_planner.eye))

func _has_descendant(key: Vector3i) -> bool:
	for resident: Vector3i in _chunks:
		if resident!=key and contains_tile(key,resident): return true
	return false

func _retire(key: Vector3i) -> void:
	var node: MultiMeshInstance3D = _chunks[key]
	_count -= node.multimesh.instance_count
	_chunks.erase(key)
	node.free()

func _finish() -> void:
	if _work==null: return
	if _task>=0:
		if not WorkerThreadPool.is_task_completed(_task): return
		WorkerThreadPool.wait_for_task_completion(_task)
	elif not _work.done: return
	if _wanted.has(_work.key): _pending[_work.key] = _work
	else: _discarded_jobs+=1
	_work=null; _task=-1

func _commit_ready() -> void:
	for key: Vector3i in _wanted:
		if not _pending.has(key): continue
		var ancestor: Variant = _ancestor(key)
		var group: Array[Vector3i] = [key]
		if ancestor!=null:
			group.clear()
			for wanted: Vector3i in _wanted:
				if contains_tile(ancestor,wanted): group.append(wanted)
		var ready := true
		for member: Vector3i in group:
			if not _pending.has(member) and not _chunks.has(member): ready=false; break
		if not ready: continue
		var removed: Array[Vector3i] = []
		for resident: Vector3i in _chunks:
			if ancestor==resident or (ancestor==null and contains_tile(key,resident)): removed.append(resident)
		var added := 0
		for member: Vector3i in group: added+=int(_pending.has(member))
		if _chunks.size()-removed.size()+added>MAX_TILES: continue
		# A budget-driven coarsening first fades the fine-only roots. Ordinary
		# distance coarsening already has zero fine coverage beyond 96 m.
		if ancestor==null and not removed.is_empty() and _density_bias<float(_planner.diagnostic.get("coarsen_bias",0))-0.001: continue
		var started := Time.get_ticks_usec()
		for resident: Vector3i in removed: _retire(resident)
		for member: Vector3i in group:
			if not _pending.has(member): continue
			var job: Job = _pending[member]
			var node := install(job,_geometry,_material,_clock,int(ancestor.z) if ancestor!=null else (key.z-1 if not removed.is_empty() else 99))
			_owner.add_child(node); _chunks[member]=node; _count+=job.count
			_pending.erase(member)
		_max_upload_us=maxi(_max_upload_us,Time.get_ticks_usec()-started)
		_max_upload_tiles=maxi(_max_upload_tiles,added)
		# One publication group per frame, never a partially visible replacement.
		if ancestor!=null: _camera_signature.clear(); _poll=0.0
		return

func _start() -> void:
	# Finish one refinement group at a time. At most four child buffers plus
	# one coarsening result can wait; the packed staging ceiling is 640 kB.
	var group: Variant = null
	for key: Vector3i in _pending:
		group = _ancestor(key)
		if group!=null: break
	for key: Vector3i in _wanted:
		if _chunks.has(key) or _pending.has(key): continue
		if _pending.size()>=5: return
		if group!=null and not contains_tile(group,key) and not _has_descendant(key): continue
		_work = Job.new(); _work.configure(_field,key); _generation_jobs+=1
		if Portability.threads(): _task=WorkerThreadPool.add_task(_work.run,false,"far grass")
		return

func diagnostic() -> Dictionary:
	var result := _planner.diagnostic.duplicate()
	result.merge({"resident_tiles":_chunks.size(),"instances":_count,"instance_bytes":_count*80,
		"pending_tiles":_pending.size(),"active_jobs":int(_work!=null),"jobs":_generation_jobs,"discarded":_discarded_jobs,
		"snapshot_owned_bytes":_field.owned_bytes if _field else 0,"borrowed_cover":_field.borrowed_cover if _field else false,
		"max_upload_us":_max_upload_us,"max_upload_tiles":_max_upload_tiles})
	return result

func clear() -> void:
	if _task>=0: WorkerThreadPool.wait_for_task_completion(_task)
	_work=null; _task=-1; _pending.clear(); _wanted.clear()
	for key: Vector3i in _chunks.keys(): _retire(key)
	_field=null; _geometry=null; _material=null; _last_camera=null; _camera_signature.clear(); _poll=0.0; _clock=0.0; _density_bias=0.0

class Field extends RefCounted:
	var sampler: RefCounted
	var scenery := {}
	var owned_bytes := 0
	var borrowed_cover := false
	var low := INF
	var high := -INF
	var size := Vector2i.ZERO
	var map_name := ""

	## Called on the main thread, after the near owner's preparation. Workers
	## retain this snapshot, never TerrainDetails, EITerrain, scene nodes or RIDs.
	func capture(details: TerrainDetails) -> void:
		var terrain := details.terrain
		size = Vector2i(terrain.size_ei()); map_name = terrain.map_name
		if details._cover_field:
			sampler = details._cover_field
			borrowed_cover = true
		else:
			# The existing native sample() supplies exact jittered triangle UVs.
			# The lighter fallback sampler needs no shore/biome/mound setup.
			sampler = Sampler.new()
			sampler.native = details._grass_field
			sampler.size = size; sampler.grid_w = terrain.grid_w
			sampler.heights = terrain.heights.duplicate()
			sampler.surface = terrain.surface.duplicate()
			sampler.water = terrain.water.duplicate()
			sampler.ground = terrain.ground.duplicate()
			owned_bytes = sampler.heights.size()*4 + sampler.surface.size()*4 + sampler.water.size()*4 + sampler.ground.size()
			if sampler.native == null:
				sampler.xy = terrain.land_xy.duplicate(); sampler.tiles = terrain.land_tile.duplicate()
				owned_bytes += sampler.xy.size()*8 + sampler.tiles.size()*4
				for code: int in sampler.tiles:
					if sampler.uv_table.has(code): continue
					var uvs := PackedVector2Array()
					for y in 3:
						for x in 3: uvs.append(terrain._tile_uv(code,x,y)[0])
					sampler.uv_table[code] = uvs
			for code: int in terrain.land_tile:
				var atlas := (code>>6)&255
				if sampler.images.has(atlas): continue
				var source: Image = details._images.get(atlas)
				if source == null: source = GameData.load_image("%s%03d" % [terrain.resource_prefix,atlas])
				if source == null: continue
				var copy := source.duplicate() as Image
				if copy.is_compressed(): copy.decompress()
				sampler.images[atlas] = copy
				owned_bytes += copy.get_data().size()
		# The near index already expands every real mesh box by the complete
		# 0.56 m leaf envelope. Every far vertex and its wind fit inside it.
		scenery = details._scenery.duplicate(true)
		for height: float in sampler.heights:
			low = minf(low,height); high = maxf(high,height)

	func allowed(p: Vector2) -> Dictionary:
		if not p.is_finite() or p.x<0 or p.y<0 or p.x>=size.x or p.y>=size.y: return {}
		var at := int(p.y)*size.x+int(p.x)
		if not int(sampler.ground[at]) in TerrainDetails.GRASS_TYPES: return {}
		var hit: Dictionary = sampler.sample(p)
		if hit.is_empty() or absf((hit.normal as Vector3).y)<0.80: return {}
		var height := float(hit.height)
		if EITerrain.ground_in(sampler.heights,sampler.surface,sampler.grid_w,size.x,size.y,p.x,p.y)>height+0.08 \
				or sampler.water[at]>height-0.035: return {}
		var colour: Color = sampler.colour(hit)
		if not TerrainDetails.green_colour(colour): return {}
		hit.colour = colour
		return hit

	func patch(p: Vector2) -> Dictionary:
		var hit := allowed(p)
		if hit.is_empty(): return {}
		# Check the patch's support as well as its root. The conservative ring
		# extends beyond the six leaf tips, including their maximum wind sway.
		for offset: Vector2 in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1),
				Vector2(-0.707107,-0.707107),Vector2(0.707107,-0.707107),Vector2(-0.707107,0.707107),Vector2(0.707107,0.707107)]:
			var edge := allowed(p+offset*FOOTPRINT)
			if edge.is_empty(): return {}
			var normal: Vector3 = hit.normal
			var expected := float(hit.height)-(normal.x*offset.x-normal.z*offset.y)*FOOTPRINT/normal.y
			if absf(float(edge.height)-expected)>0.10: return {}
		var key := Vector2i((p/TerrainDetails.CHUNK).floor())
		for box: Dictionary in scenery.get(key,[]):
			var inverse: Transform3D = box.inverse
			if (box.box as AABB).intersects_segment(inverse*Vector3(p.x,float(hit.height)-0.025,-p.y),
					inverse*Vector3(p.x,float(hit.height)+TerrainDetails.SCENERY_HEIGHT,-p.y)) != null: return {}
		return hit

class Job extends RefCounted:
	var field: Field
	var key := Vector3i.ZERO
	var buffer := PackedFloat32Array()
	var count := 0
	var attempted := 0
	var elapsed_us := 0
	var noise: FastNoiseLite
	var done := false

	func configure(snapshot: Field, tile: Vector3i) -> void:
		field = snapshot; key = tile
		buffer.resize(CELLS*CELLS*20)
		noise = FastNoiseLite.new(); noise.seed = field.map_name.hash()&0x7fffffff
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.frequency = 0.10
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM; noise.fractal_octaves = 2

	## Coarse roots are a deterministic subset of the fine world grid. The
	## map and cell own all random draws; neither job order nor scenery does.
	func root_cell(local: Vector2i) -> Vector2i:
		var cell := Vector2i(key.x,key.y)*CELLS+local
		for level in range(key.z,0,-1):
			var seed := hash("%s:far:%d:%d:%d" % [field.map_name,level,cell.x,cell.y])
			cell = cell*2+Vector2i(seed&1,(seed>>1)&1)
		return cell

	func membership(cell: Vector2i) -> int:
		# Highest nested level that retains this exact fine root.
		for level in range(1,13):
			var parent := Vector2i(cell.x>>1,cell.y>>1)
			var seed := hash("%s:far:%d:%d:%d" % [field.map_name,level,parent.x,parent.y])
			if cell != parent*2+Vector2i(seed&1,(seed>>1)&1): return level-1
			cell=parent
		return 12

	func step(max_cells := 8) -> bool:
		if done: return true
		var start := Time.get_ticks_usec()
		var end := mini(attempted+maxi(1,max_cells),CELLS*CELLS)
		while attempted<end:
			var cell := root_cell(Vector2i(attempted%CELLS,attempted/CELLS))
			attempted += 1
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%s:far:0:%d:%d" % [field.map_name,cell.x,cell.y])
			var p := (Vector2(cell)+Vector2(rng.randf_range(0.08,0.92),rng.randf_range(0.08,0.92)))*SPACING
			var lush := smoothstep(-0.45,0.55,noise.get_noise_2d(p.x,p.y))
			var present := rng.randf()<=lerpf(0.78,1.0,lush)
			var colour_scale := rng.randf_range(0.96,1.14)
			var turn := rng.randf()*TAU
			var tall := rng.randf_range(0.88,1.12)*lerpf(0.80,1.05,lush)
			var seed := rng.randf()
			if not present: continue
			var hit := field.patch(p)
			if hit.is_empty(): continue
			var colour: Color = hit.colour*Color(lerpf(1.20,0.97,lush),lerpf(1.02,1.14,lush),0.94)*colour_scale
			colour = Color(minf(colour.r,0.75),minf(colour.g,0.80),minf(colour.b,0.60),1.0)
			var basis := Basis(Vector3.UP,turn).scaled(Vector3(1.0,tall,1.0))
			var pos := Vector3(p.x,float(hit.height)-0.008,-p.y)
			var offset := count*20
			buffer[offset] = basis.x.x; buffer[offset+1] = basis.y.x; buffer[offset+2] = basis.z.x; buffer[offset+3] = pos.x
			buffer[offset+4] = basis.x.y; buffer[offset+5] = basis.y.y; buffer[offset+6] = basis.z.y; buffer[offset+7] = pos.y
			buffer[offset+8] = basis.x.z; buffer[offset+9] = basis.y.z; buffer[offset+10] = basis.z.z; buffer[offset+11] = pos.z
			buffer[offset+12] = colour.r; buffer[offset+13] = colour.g; buffer[offset+14] = colour.b; buffer[offset+15] = 1.0
			buffer[offset+16] = seed; buffer[offset+17] = key.z; buffer[offset+18] = membership(cell); buffer[offset+19] = 1.0
			count += 1
		elapsed_us += Time.get_ticks_usec()-start
		done = attempted>=CELLS*CELLS
		if done: buffer.resize(count*20)
		return done

	func run() -> void:
		while not step(32): pass

class Planner extends RefCounted:
	var size := Vector2i.ZERO
	var heights := Vector2.ZERO
	var transform := Transform3D.IDENTITY
	var limit := MAX_TILES
	var planes: Array[Plane] = []
	var eye := Vector3.ZERO
	var forward := Vector3.FORWARD
	var root_level := 0
	var diagnostic := {}

	func box(key: Vector3i) -> AABB:
		var side := TILE*float(1<<key.z)
		var origin := Vector2(key.x,key.y)*side
		var span := (Vector2(size)-origin).clamp(Vector2.ZERO,Vector2.ONE*side)
		# A root just outside the frustum may still send a leaf into view.
		# Grow in local XZ before transforming the full swept envelope.
		return transform*AABB(Vector3(origin.x-FOOTPRINT,heights.x-0.03,-origin.y-span.y-FOOTPRINT),
			Vector3(span.x+2.0*FOOTPRINT,heights.y-heights.x+0.95,span.y+2.0*FOOTPRINT))

	func visible(bounds: AABB) -> bool:
		var centre := bounds.get_center(); var half := bounds.size*0.5
		for plane: Plane in planes:
			if plane.distance_to(centre)>plane.normal.abs().dot(half)+12.0: return false
		return true

	func _collect(key: Vector3i, bias: int, result: Array[Vector3i]) -> void:
		var side := TILE*float(1<<key.z)
		if key.x*side>=size.x or key.y*side>=size.y: return
		var bounds := box(key)
		if not visible(bounds): return
		var first_depth := forward.dot(bounds.get_center()-eye)-forward.abs().dot(bounds.size*0.5)
		var target := bias+(1 if first_depth>=96.0 else 0)
		if key.z<=target:
			result.append(key); return
		for y in 2:
			for x in 2: _collect(Vector3i(key.x*2+x,key.y*2+y,key.z-1),bias,result)

	## Every intersecting ground bound has a leaf. If a view needs too many,
	## coarsen the representation; never silently truncate visible corners.
	func select(camera: Camera3D, snapshot: Field, terrain_transform := Transform3D.IDENTITY) -> Array[Vector3i]:
		size = snapshot.size; heights = Vector2(snapshot.low,snapshot.high); transform = terrain_transform
		var camera_transform := camera.get_camera_transform()
		planes = camera.get_frustum(); eye = camera_transform.origin; forward = -camera_transform.basis.z
		root_level = 0
		while TILE*float(1<<root_level)<maxi(size.x,size.y): root_level += 1
		var bias := 0
		var result: Array[Vector3i] = []
		while true:
			result.clear(); _collect(Vector3i(0,0,root_level),bias,result)
			if result.size()<=limit or bias>=root_level: break
			bias += 1
		result.sort_custom(func(a: Vector3i,b: Vector3i)->bool: return box(a).get_center().distance_squared_to(eye)<box(b).get_center().distance_squared_to(eye))
		diagnostic = {"tiles":result.size(),"coarsen_bias":bias,"coarsened":bias>0,"limit":limit,
			"candidate_limit":result.size()*CELLS*CELLS,"packed_byte_limit":result.size()*CELLS*CELLS*80,
			"triangle_limit":result.size()*CELLS*CELLS*TRIANGLES,"far_plane":camera.far}
		return result

static func mesh() -> ArrayMesh:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uvs := PackedVector2Array()
	for i in TRIANGLES:
		var turn := Basis(Vector3.UP,i*2.39996)
		var height: float = [0.66,0.55,0.62,0.69,0.59,0.65][i]
		for vertex: Vector3 in [Vector3(-0.065,0.0,0.045),Vector3(0.065,0.0,0.045),Vector3(0.0,height,0.26)]:
			vertices.append(turn*vertex)
			normals.append(turn*Vector3(0.0,-0.215,height).normalized())
			uvs.append(Vector2(i,1.0 if vertex.y>0 else 0.0))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_TEX_UV] = uvs
	var result := ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func material() -> ShaderMaterial:
	var result := ShaderMaterial.new(); result.shader = Gfx.make_shader(SHADER,true,true)
	return result

static func install(job: Job, geometry: ArrayMesh, shader_material: ShaderMaterial, clock := -1.0, previous_level := -1) -> MultiMeshInstance3D:
	assert(job.done)
	var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D
	var node := MultiMeshInstance3D.new()
	multi.use_colors = true; multi.use_custom_data = true; multi.mesh = geometry
	multi.instance_count = job.count
	var buffer := job.buffer.duplicate()
	for i in job.count:
		buffer[i*20+17]=previous_level
		buffer[i*20+19]=clock
	multi.buffer = buffer
	node.name = "FarGrass_%d_%d_%d" % [job.key.x,job.key.y,job.key.z]
	node.multimesh = multi; node.material_override = shader_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 0.04
	return node
