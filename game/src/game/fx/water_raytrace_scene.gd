extends RefCounted
## CPU-owned scene description. Geometry is shared by rigid instances; only
## transforms, visibility and changed blend-shape vertices cross each frame.
const RADIUS := 96.0
const UNIT_HYSTERESIS := 8.0
const MAX_TRIANGLES := 320000
const MAX_TEXTURES := 192
# Dense LiA cities exceed 4096 articulated parts within the unchanged radius.
# The FP16 identity encoding remains exact across this bounded range.
const MAX_INSTANCES := 8192
const TEXTURE_SIZE := 512
var center := Vector3.ZERO
var vertices := PackedFloat32Array()
var images: Array[Image] = []
var geometries: Array[Dictionary] = []
var instances: Array[Dictionary] = []
var triangles := 0
var failed := false
var pending: Array = []
var _textures := {}
var _opaque_textures: Array[bool] = []
var _mesh_cache := {}
var _nodes := {}
var _mesh_roots := {}
var _unit_roots := {}
var _groups := {}
var _view_models := {}
var _view_offsets := {}
var _morph_geometries: Array[int] = []
var _terrain: EITerrain
var _plane := 0.0
var _cursor := 0
var _gather_roots: Array[WeakRef] = []
var _gather_root_cursor := 0
var _gather_materials := {}
var _kernel: Object
var _watching := false
var _detail_options := Vector4i.ZERO
var path_materials := false
var path_transmission := false
var _water_version := PackedFloat32Array()
var _water_enabled := false
var _terrain_version := []
# Live polling shares a small frame budget between roots. Atomic candidate
# validation still uses a fresh synchronous check before publishing output.
var topology_pending := false
var _topology_roots: Array[WeakRef] = []
var _topology_cursor := 0
var _topology_seen := {}
var _topology_materials := {}
const PathTerrain = preload("res://src/game/fx/path_trace_terrain.gd")
const Ground = preload("res://src/game/fx/raytrace_ground.gd")
var _ground := Ground.new()
const SourceCache = preload("res://src/game/fx/raytrace_source_cache.gd")
const Retirement = preload("res://src/game/fx/raytrace_retirement.gd")
var _sources := SourceCache.new()
var _retirement: Retirement
var _soft_ground := false
var _cliffs: TerrainCliff
# Negative keeps the original water masks. Scene lighting distinguishes
# camera-visible receivers (1), shadow casters (2), and GI surfaces (4).
var lighting_camera_mask := -1
# Observation-only live diagnostics. The controller enables these solely for
# --ei-profile-rt; plain values can be retained after a candidate is promoted.
var profile_cpu := false
var profile_gather := {}
var profile_topology := {}
var _profile_gather_active := false

func _init() -> void:
	if ClassDB.class_exists("WaterRaytraceKernel") and not OS.get_cmdline_user_args().has("--ei-script-water-rt"):
		_kernel = ClassDB.instantiate("WaterRaytraceKernel")

func begin(terrain: EITerrain, position: Vector3, plane: float, incremental := false) -> void:
	_terrain = terrain; center = position; _plane = plane
	_soft_ground=Gfx.on("gfx_soft_ground");_ground.configure(terrain)
	_cliffs=terrain._cliffs
	_detail_options = Vector4i(GameData.option("gfx_terrain"),GameData.option("gfx_materials"),GameData.option("gfx_foliage_light"),GameData.option("gfx_terrain_cliffs"))
	if path_materials: _terrain_version=PathTerrain.version(terrain)
	if path_transmission: _water_version=terrain._level.duplicate();_water_enabled=Gfx.on("gfx_water")
	for child in terrain.get_children():
		if child is EITerrainSector and _near(child.global_transform*child.get_aabb()):
			pending.append({"node":weakref(child),"land":true})
		elif path_transmission and Gfx.on("gfx_water") and child is MeshInstance3D and child.mesh!=null and child.get_active_material(0)==terrain._water_mat and _near(child.global_transform*child.get_aabb(),false):
			pending.append({"node":weakref(child),"land":false,"water":true})
	if incremental:
		# Discovering every articulated mesh and its material versions can itself
		# take several milliseconds. Include that work in the live gather budget;
		# capturing weak roots here does not retain objects that leave the world.
		for root: Node3D in _scene_roots():
			if is_instance_valid(root): _gather_roots.append(weakref(root))
	else:
		var materials := {}
		for mesh: MeshInstance3D in _scene_meshes(true):
			pending.append({"node":weakref(mesh),"land":false})
			_nodes[mesh.get_instance_id()] = _mesh_version(mesh,materials)

func _scene_roots() -> Array:
	var world := _terrain.game_world()
	if world == null: return []
	var roots: Array = world.objects.values()+world.units.values()
	# Detached limbs opt in without retaining another world's geometry.
	if world.is_inside_tree():
		for root: Node in world.get_tree().get_nodes_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP):
			if root is Node3D and world.is_ancestor_of(root) and root.get_world_3d()==world.get_world_3d() and not roots.has(root):
				roots.append(root)
	return roots

func _root_meshes(root: Node3D,remember_units := false) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if not is_instance_valid(root) or not root.is_inside_tree(): return found
	var dynamic := root is GameUnit or root.is_in_group(GameWorld.RAYTRACE_GEOMETRY_GROUP)
	var radius := RADIUS+24.0
	if dynamic and _unit_roots.has(root.get_instance_id()): radius+=UNIT_HYSTERESIS
	# Hidden parts remain members; their visibility is a live instance mask.
	if root.global_position.distance_squared_to(center) > radius*radius: return found
	if dynamic and remember_units: _unit_roots[root.get_instance_id()]=true
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null or mesh is EIObjectWater: continue
		# Admit an animated figure as a whole, with root hysteresis.
		if not dynamic and not _near(mesh.global_transform*mesh.get_aabb(),false): continue
		var supported := false
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface)
			if mat is BaseMaterial3D or (mat is ShaderMaterial and mat.get_shader_parameter("albedo_tex") is Texture2D):
				supported = true; break
		if supported:
			found.append(mesh)
			if remember_units: _mesh_roots[mesh.get_instance_id()] = weakref(root)
	return found

func _scene_meshes(remember_units := false) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for root: Node3D in _scene_roots():found.append_array(_root_meshes(root,remember_units))
	return found

func _material_version(material: Material) -> Array:
	if material is ShaderMaterial:
		var texture: Texture2D = material.get_shader_parameter("albedo_tex") as Texture2D
		return [material.shader.get_instance_id() if material.shader else 0,texture.get_instance_id() if texture else 0,
			material.get_shader_parameter("ei_material_diffuse"),material.get_shader_parameter("ei_material_emissive"),
			material.get_shader_parameter("surface_profile"),material.get_shader_parameter("foliage_mask"),
			material.get_shader_parameter("surface_tex") if path_materials else null,
			material.get_shader_parameter("surface_detail_tex") if path_materials else null,
			material.get_shader_parameter("surface_detail_enabled") if path_materials else null,material.get_meta("pt_dielectric",PackedFloat32Array())]
	if material is BaseMaterial3D:
		return [material.albedo_texture.get_instance_id() if material.albedo_texture else 0,material.albedo_color,
			material.transparency,material.alpha_scissor_threshold,material.emission_enabled,material.emission,
			material.emission_energy_multiplier,material.roughness,material.metallic,material.metallic_specular]
	return []

static func surface_profile(material: Material) -> Vector3:
	if material is BaseMaterial3D:
		return Vector3(material.roughness,material.metallic,material.metallic_specular)
	if material is ShaderMaterial:
		var profile: Variant = material.get_shader_parameter("surface_profile")
		if profile is Vector4 and profile.x>0.0:
			return Vector3(clampf(profile.y,0.08,1.0),clampf(profile.z,0.0,1.0),0.5)
	# Original assets without a remake profile are rough dielectrics.
	return Vector3(1.0,0.0,0.5)

static func surface_relief(material: Material, land: bool) -> float:
	# Terrain is packed from sector arrays without an object material.
	if land: return 0.85 if GameData.option("gfx_terrain")>0 else 0.0
	if not material is ShaderMaterial: return 0.0
	# Only explicitly identified stone/wood profiles have relief. In
	# particular, leaf cutout alpha and painted shadows are not height maps.
	var profile: Variant = material.get_shader_parameter("surface_profile")
	return clampf(profile.w,0.0,1.0) if profile is Vector4 and GameData.option("gfx_materials")>0 else 0.0

func _mesh_variants(mesh: MeshInstance3D) -> Array:
	var variants: Array=mesh.get_meta(EIUnitModel.VIEW_MESH_VARIANTS_META,[])
	# An equipment replacement is still a real topology change. Only the two
	# registered, immutable camera meshes can share this retained membership.
	return variants if variants.has(mesh.mesh) else [mesh.mesh]

func _mesh_version(mesh: MeshInstance3D, materials: Dictionary) -> Array:
	var version := [_mesh_variants(mesh).map(func(source: Mesh):return source.get_instance_id())]
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		var dielectric: PackedFloat32Array=material.get_meta("pt_dielectric",PackedFloat32Array()) if material else PackedFloat32Array()
		if not dielectric.is_empty() and not path_transmission:continue
		var key := material.get_instance_id() if material else 0
		if not materials.has(key): materials[key] = _material_version(material)
		version.append([key,materials[key]])
	return version

func _reset_topology_poll() -> void:
	topology_pending=false;_topology_roots.clear();_topology_cursor=0
	_topology_seen.clear();_topology_materials.clear()

func topology_changed(budget_us := 0) -> bool:
	var profile_start:=Time.get_ticks_usec() if profile_cpu else 0
	if profile_cpu:
		profile_topology={"budget_us":budget_us,"fresh":budget_us<=0,"cursor_before":_topology_cursor,
			"roots_before":_topology_roots.size(),"root_count":0,"mesh_count":0,"collect_us":0,"versions_us":0,"roots_us":0,"max_root":{}}
	if (path_transmission and (_water_version!=_terrain._level or _water_enabled!=Gfx.on("gfx_water"))) or _soft_ground!=Gfx.on("gfx_soft_ground") or _cliffs!=_terrain._cliffs \
		or (lighting_camera_mask>=0 and _detail_options!=Vector4i(GameData.option("gfx_terrain"),GameData.option("gfx_materials"),GameData.option("gfx_foliage_light"),GameData.option("gfx_terrain_cliffs"))) \
		or (path_materials and _terrain_version!=PathTerrain.version(_terrain)):
		_reset_topology_poll()
		if profile_cpu:_profile_topology_end(profile_start,"settings",true)
		return true
	if budget_us<=0:_reset_topology_poll()
	var profile_roots:=Time.get_ticks_usec() if profile_cpu else 0
	if not topology_pending:
		for root: Node3D in _scene_roots():
			if is_instance_valid(root):_topology_roots.append(weakref(root))
		topology_pending=true
	if profile_cpu:profile_topology.roots_us=Time.get_ticks_usec()-profile_roots
	var deadline := Time.get_ticks_usec()+budget_us
	while _topology_cursor<_topology_roots.size():
		var root: Node3D=_topology_roots[_topology_cursor].get_ref();_topology_cursor+=1
		var profile_root:=Time.get_ticks_usec() if profile_cpu else 0
		var meshes:=_root_meshes(root)
		var profile_versions:=Time.get_ticks_usec() if profile_cpu else 0
		if profile_cpu:
			profile_topology.collect_us+=profile_versions-profile_root
			profile_topology.root_count+=1
		for mesh: MeshInstance3D in meshes:
			if profile_cpu:profile_topology.mesh_count+=1
			var id := mesh.get_instance_id()
			if _nodes.get(id)!=_mesh_version(mesh,_topology_materials):
				if profile_cpu:_profile_topology_root(root,profile_root,profile_versions)
				_reset_topology_poll()
				if profile_cpu:_profile_topology_end(profile_start,"mesh",true)
				return true
			_topology_seen[id]=true
		if profile_cpu:_profile_topology_root(root,profile_root,profile_versions)
		if budget_us>0 and Time.get_ticks_usec()>=deadline:
			if profile_cpu:_profile_topology_end(profile_start,"budget",false)
			return false
	var changed := _topology_seen.size()!=_nodes.size()
	if profile_cpu:
		profile_topology.seen_meshes=_topology_seen.size();profile_topology.expected_meshes=_nodes.size()
		profile_topology.materials=_topology_materials.size()
	_reset_topology_poll()
	if profile_cpu:_profile_topology_end(profile_start,"complete",changed)
	return changed

func _profile_topology_root(root: Node3D,started: int,versions_started: int) -> void:
	var now:=Time.get_ticks_usec()
	profile_topology.versions_us+=now-versions_started
	var elapsed:=now-started
	if elapsed>int(profile_topology.max_root.get("us",-1)):
		profile_topology.max_root={"us":elapsed,"owner":_profile_owner(root)}

func _profile_topology_end(started: int,reason: String,changed: bool) -> void:
	profile_topology.total_us=Time.get_ticks_usec()-started
	profile_topology.reason=reason;profile_topology.changed=changed
	profile_topology.cursor_after=_topology_cursor

static func _profile_owner(node: Node) -> Dictionary:
	if not is_instance_valid(node):return {"valid":false}
	var script:=node.get_script() as Script
	var result:={"id":node.get_instance_id(),"name":str(node.name),"class":node.get_class(),
		"script":script.resource_path if script else ""}
	if node is MeshInstance3D and node.mesh:
		result.mesh_id=node.mesh.get_instance_id();result.mesh_path=node.mesh.resource_path
	return result

## Retain only inexpensive source watches after a failed/empty gather. The
## controller can retry when real inputs change without keeping copied images
## or repeatedly repacking an unchanged over-budget scene.
func discard_geometry() -> void:
	_reset_topology_poll()
	vertices=PackedFloat32Array();images.clear();geometries.clear();instances.clear()
	pending.clear();_textures.clear();_opaque_textures.clear();_mesh_cache.clear()
	_gather_roots.clear();_gather_root_cursor=0;_gather_materials.clear()
	_mesh_roots.clear();_groups.clear();_view_models.clear();_view_offsets.clear();_morph_geometries.clear()
	_kernel=null;_watching=false;_cursor=0
	_ground=Ground.new()

func retire_step(budget_us := 1000) -> bool:
	if _retirement==null:
		_retirement=Retirement.new()
		_retirement.parts=[vertices,_kernel,images,geometries,instances,pending,_textures,_opaque_textures,
			_mesh_cache,_nodes,_mesh_roots,_unit_roots,_groups,_view_models,_view_offsets,_morph_geometries,
			_gather_roots,_gather_materials,_topology_roots,_topology_seen,_topology_materials]
		vertices=PackedFloat32Array();_kernel=null
		# Ground/source caches are shared with the current generation.
	return _retirement.step(budget_us)

func _near(bounds: AABB, clip_plane := true) -> bool:
	var p := center.clamp(bounds.position,bounds.end)
	return p.distance_squared_to(center) <= RADIUS*RADIUS and (not clip_plane or bounds.end.y >= _plane-0.1)

func step(budget_us := 6000) -> bool:
	var profile_start:=Time.get_ticks_usec() if profile_cpu else 0
	if profile_cpu:
		_profile_gather_active=true
		profile_gather={"budget_us":budget_us,"root_cursor_before":_gather_root_cursor,"roots":_gather_roots.size(),
			"entry_cursor_before":_cursor,"entries_before":pending.size(),"triangles_before":triangles,
			"cache_hits_before":_sources.hits,"cache_misses_before":_sources.misses,
			"readbacks_before":_sources.surface_readbacks,"retained_before":_sources.retained_surfaces,
			"image_readbacks_before":_sources.image_readbacks,"retained_images_before":_sources.retained_images,
			"counts":{},"us":{},"parts_us":{},"slowest":{}}
	var deadline := Time.get_ticks_usec()+budget_us
	while _gather_root_cursor < _gather_roots.size():
		var root: Node3D = _gather_roots[_gather_root_cursor].get_ref()
		_gather_root_cursor += 1
		var profile_root:=Time.get_ticks_usec() if profile_cpu else 0
		for mesh: MeshInstance3D in _root_meshes(root,true):
			pending.append({"node":weakref(mesh),"land":false})
			_nodes[mesh.get_instance_id()] = _mesh_version(mesh,_gather_materials)
		if profile_cpu:_profile_gather_entry("root",root,_gather_root_cursor-1,profile_root)
		if Time.get_ticks_usec() >= deadline:
			if profile_cpu:_profile_gather_end(profile_start,false)
			return false
	_gather_roots.clear();_gather_root_cursor=0;_gather_materials.clear()
	while _cursor < pending.size() and not failed:
		var entry: Dictionary = pending[_cursor]; _cursor += 1
		var node: Node3D = entry.node.get_ref()
		var profile_entry:=Time.get_ticks_usec() if profile_cpu else 0
		# Gathering spans frames. Equipment/body parts can leave the tree or
		# lose their mesh before this queued entry reaches the packing budget.
		if is_instance_valid(node) and node.is_inside_tree() and (entry.land or (node as MeshInstance3D).mesh != null):
			if entry.get("water",false):
				_pack_water(node)
			elif entry.land:
				var profile_part:=Time.get_ticks_usec() if profile_cpu else 0
				var arrays: Array = _ground.arrays(node.visual_arrays(),node.get_instance_id())
				if profile_cpu:_profile_gather_part("ground_arrays",profile_part)
				profile_part=Time.get_ticks_usec() if profile_cpu else 0
				var geometry := _append(arrays,node.global_transform,null,true)
				if profile_cpu:_profile_gather_part("ground_append",profile_part)
				profile_part=Time.get_ticks_usec() if profile_cpu else 0
				if path_materials and geometry>=0:
					# Follow the actual retained triangles, including shifted MPR
					# vertices. World XZ cannot identify their authored tile.
					var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
					var used: PackedInt32Array = geometries[geometry].indices
					var ids := PackedInt32Array(); ids.resize(used.size()/3)
					for i in ids.size(): ids[i]=roundi(uv2[used[i*3]].y)+1
					geometries[geometry]["land_tiles"]=ids
				_add_instance(node,geometry,Transform3D.IDENTITY)
				if profile_cpu:_profile_gather_part("ground_tiles",profile_part)
			else:
				var mesh := node as MeshInstance3D
				for source_mesh: Mesh in _mesh_variants(mesh):
					_pack_mesh(mesh,source_mesh)
		if profile_cpu:_profile_gather_entry("water" if entry.get("water",false) else "terrain" if entry.land else "mesh",node,_cursor-1,profile_entry)
		if Time.get_ticks_usec() >= deadline: break
	var complete:=failed or _cursor>=pending.size()
	if profile_cpu:_profile_gather_end(profile_start,complete)
	return complete

func _profile_gather_part(label: String,started: int) -> void:
	profile_gather.parts_us[label]=int(profile_gather.parts_us.get(label,0))+Time.get_ticks_usec()-started

func _profile_gather_entry(kind: String,node: Node,index: int,started: int) -> void:
	var elapsed:=Time.get_ticks_usec()-started
	profile_gather.counts[kind]=int(profile_gather.counts.get(kind,0))+1
	profile_gather.us[kind]=int(profile_gather.us.get(kind,0))+elapsed
	var before: Dictionary=profile_gather.slowest.get(kind,{})
	if elapsed>int(before.get("us",-1)):
		profile_gather.slowest[kind]={"us":elapsed,"index":index,"owner":_profile_owner(node)}

func _profile_gather_end(started: int,complete: bool) -> void:
	_profile_gather_active=false
	profile_gather.total_us=Time.get_ticks_usec()-started
	profile_gather.complete=complete;profile_gather.root_cursor_after=_gather_root_cursor
	profile_gather.entry_cursor_after=_cursor;profile_gather.entries_after=pending.size()
	profile_gather.triangles_added=triangles-int(profile_gather.triangles_before)
	profile_gather.cache_hits=_sources.hits-int(profile_gather.cache_hits_before)
	profile_gather.cache_misses=_sources.misses-int(profile_gather.cache_misses_before)
	profile_gather.surface_readbacks=_sources.surface_readbacks-int(profile_gather.readbacks_before)
	profile_gather.retained_surfaces=_sources.retained_surfaces-int(profile_gather.retained_before)
	profile_gather.image_readbacks=_sources.image_readbacks-int(profile_gather.image_readbacks_before)
	profile_gather.retained_images=_sources.retained_images-int(profile_gather.retained_images_before)

func _pack_water(mesh: MeshInstance3D) -> void:
	# Surface waves remain a raster detail. Geometry follows authored tiles and
	# SetWaterLevel; finite shore boundaries and stepped pools stay distinct.
	for surface in mesh.mesh.get_surface_count():
		var profile_part:=Time.get_ticks_usec() if _profile_gather_active else 0
		var arrays := mesh.mesh.surface_get_arrays(surface)
		if _profile_gather_active:_profile_gather_part("water_source",profile_part)
		profile_part=Time.get_ticks_usec() if _profile_gather_active else 0
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var uv2: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(positions.size())
			for i in indices.size():indices[i]=i
		var groups: Dictionary={}
		for at in range(0,indices.size()-2,3):
			var id:=int(uv2[indices[at]].y)&63
			if id>=_terrain.materials.size() or _terrain._lava[id]>.5:continue
			var point: Vector3=mesh.global_transform*((positions[indices[at]]+positions[indices[at+1]]+positions[indices[at+2]])/3.0)
			var width:=_terrain.sectors_x*EITerrain.SECTOR
			var cell:=int(-point.z)*width+int(point.x)
			if cell>=0 and cell<_terrain.liquid_ground.size() and _terrain.liquid_ground[cell]==14:id+=64
			if not groups.has(id):groups[id]=PackedInt32Array()
			for j in 3:groups[id].append(indices[at+j])
		for i in positions.size():positions[i].y+=_terrain._level[int(uv2[i].y)&63]
		arrays[Mesh.ARRAY_VERTEX]=positions
		if _profile_gather_active:_profile_gather_part("water_groups",profile_part)
		profile_part=Time.get_ticks_usec() if _profile_gather_active else 0
		for id: int in groups:
			arrays[Mesh.ARRAY_INDEX]=groups[id]
			var mat:=StandardMaterial3D.new()
			var geometry:=_append(arrays,Transform3D.IDENTITY,mat,false)
			if geometry<0:continue
			# Clear water absorbs red first. Swamp liquid extinguishes the bed
			# quickly; existing sediment surface colour still overlays it.
			var swamp: bool=id>=64
			geometries[geometry]["dielectric"]=PackedFloat32Array([.48 if swamp else .12,.22 if swamp else .035,.6 if swamp else .018,1.333,1,0,0,0])
			_add_instance(mesh,geometry,mesh.global_transform,surface,mesh.mesh)
		if _profile_gather_active:_profile_gather_part("water_append",profile_part)

func _pack_mesh(mesh: MeshInstance3D, source_mesh: Mesh) -> void:
	for surface in source_mesh.get_surface_count():
		# Only ArrayMesh exposes this query to scripts. PrimitiveMesh
		# uses triangles except PointMesh, which has no ray surface.
		if source_mesh is ArrayMesh:
			if source_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		elif not source_mesh is PrimitiveMesh or source_mesh is PointMesh: continue
		var material := mesh.get_active_material(surface)
		var dielectric: PackedFloat32Array=material.get_meta("pt_dielectric",PackedFloat32Array()) if material else PackedFloat32Array()
		if not dielectric.is_empty() and not path_transmission:continue
		var key := "%s:%s:%s"%[source_mesh.get_instance_id(),surface,material.get_instance_id() if material else 0]
		var morph: bool = source_mesh is ArrayMesh and source_mesh.get_blend_shape_count() > 0
		if morph: key += ":"+str(mesh.get_instance_id())
		var geometry: int = _mesh_cache.get(key,-1)
		if geometry < 0:
			var profile_part:=Time.get_ticks_usec() if _profile_gather_active else 0
			var source: Dictionary=_sources.surface(source_mesh,surface)
			if _profile_gather_active:_profile_gather_part("mesh_source",profile_part)
			profile_part=Time.get_ticks_usec() if _profile_gather_active else 0
			geometry = _append(source.arrays,Transform3D.IDENTITY,material,false)
			if _profile_gather_active:_profile_gather_part("mesh_append",profile_part)
			if geometry >= 0:
				_mesh_cache[key] = geometry
				if dielectric.size()==8:geometries[geometry]["dielectric"]=dielectric.duplicate()
				if morph:
					_morph_geometries.append(geometry)
					geometries[geometry].morph = {"node":weakref(mesh),"mesh":source_mesh,"surface":surface,
						"arrays":source.arrays,"shapes":source.shapes,"weights":[]}
		_add_instance(mesh,geometry,mesh.global_transform,surface,source_mesh)

func _add_instance(node: Node3D, geometry: int, transform: Transform3D, surface := -1, source_mesh: Mesh = null) -> void:
	if geometry < 0: return
	_watching = false
	if instances.size() >= MAX_INSTANCES: failed = true; return
	var root: Node3D = _mesh_roots[node.get_instance_id()].get_ref() if _mesh_roots.has(node.get_instance_id()) else node
	var key := root.get_instance_id()
	if not _groups.has(key): _groups[key] = {"node":weakref(root),"indices":[],"visible":-1}
	_groups[key].indices.append(instances.size())
	if root is GameUnit and is_instance_valid(root.model) and root.model.is_ancestor_of(node):
		var model_key: int = root.model.get_instance_id()
		if not _view_models.has(model_key): _view_models[model_key] = {"model":weakref(root.model),"indices":[]}
		_view_models[model_key].indices.append(instances.size())
	instances.append({"geometry":geometry,"node":weakref(node),"mesh":source_mesh if source_mesh else node.mesh if node is MeshInstance3D else null,
		"surface":surface,"terrain":node is EITerrainSector,"transform":transform,"mask":-1})

func history_matches(previous: RefCounted) -> PackedInt32Array:
	var matches := PackedInt32Array();matches.resize(instances.size());matches.fill(-1)
	if previous==null or _detail_options!=previous._detail_options or _soft_ground!=previous._soft_ground or _terrain_version!=previous._terrain_version:return matches
	var old := {}
	for i in previous.instances.size():
		var entry: Dictionary=previous.instances[i];var node: Node3D=entry.node.get_ref()
		if is_instance_valid(node):old[_history_key(entry,node)]=i
	for i in instances.size():
		var entry: Dictionary=instances[i];var node: Node3D=entry.node.get_ref()
		if not is_instance_valid(node) or geometries[entry.geometry].has("morph"):continue
		var key := _history_key(entry,node)
		if not old.has(key):continue
		var before: Dictionary=previous.instances[old[key]]
		if entry.mesh!=before.mesh:continue
		if _nodes.get(node.get_instance_id())!=previous._nodes.get(node.get_instance_id()):continue
		matches[i]=old[key]
	return matches

func _history_key(entry: Dictionary,node: Node3D) -> String:
	return "%d:%d:%d"%[node.get_instance_id(),entry.surface,entry.mesh.get_instance_id() if entry.mesh else 0]

func _layer(texture: Texture2D, atlas := -1) -> int:
	var key := "terrain:%d"%atlas if atlas >= 0 else str(texture.get_instance_id()) if texture else "white"
	if _textures.has(key): return _textures[key]
	if images.size() >= MAX_TEXTURES: failed = true; return -1
	var image: Image
	var profile_part:=Time.get_ticks_usec() if _profile_gather_active else 0
	if atlas >= 0:
		if atlas >= _terrain._atlases.get_layers(): return -1
		image = _sources.image(_terrain._atlases,atlas,TEXTURE_SIZE)
	elif texture: image = _sources.image(texture,-1,TEXTURE_SIZE)
	else:
		image = Image.create(TEXTURE_SIZE,TEXTURE_SIZE,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE);image.generate_mipmaps()
	if _profile_gather_active:_profile_gather_part("layer_source",profile_part)
	if image == null or image.is_empty(): return -1
	profile_part=Time.get_ticks_usec() if _profile_gather_active else 0
	_opaque_textures.append(image.detect_alpha() == Image.ALPHA_NONE)
	if _profile_gather_active:_profile_gather_part("layer_alpha",profile_part)
	var layer := images.size(); images.append(image); _textures[key] = layer
	return layer

func _append(arrays: Array, transform: Transform3D, material: Material, land: bool) -> int:
	if arrays.is_empty(): return -1
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(positions.size())
		for i in indices.size(): indices[i] = i
	if normals.size() != positions.size() or uv.size() != positions.size(): return -1
	var texture: Texture2D
	var diffuse := Vector4.ONE
	var emission := Vector3.ZERO
	var cutoff := 0.0 if land else 0.5
	var standard := material is BaseMaterial3D
	if not land:
		if material is ShaderMaterial:
			texture = material.get_shader_parameter("albedo_tex") as Texture2D
			if texture == null: return -1
			var d: Variant = material.get_shader_parameter("ei_material_diffuse")
			if d is Vector4: diffuse = d
			var e: Variant = material.get_shader_parameter("ei_material_emissive")
			if e is Vector3: emission = e
		elif material is BaseMaterial3D:
			# Blended and hashed transparency need an ordered transmission path.
			# They must not become solid cutout surfaces in this single-hit view.
			if material.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED,BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]: return -1
			texture = material.albedo_texture
			var c: Color = material.albedo_color; diffuse = Vector4(c.r,c.g,c.b,c.a)
			cutoff = 0.0 if material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED else material.alpha_scissor_threshold
			if material.emission_enabled:
				var e: Color = material.emission.srgb_to_linear()*material.emission_energy_multiplier
				emission = Vector3(e.r,e.g,e.b)
		else: return -1
	var foliage_layer := -1
	if lighting_camera_mask>=0 and material is ShaderMaterial and (Gfx.on("gfx_foliage_light") or Gfx.on("gfx_materials")):
		var mask: Texture2D = material.get_shader_parameter("foliage_mask") as Texture2D
		if mask != null: foliage_layer = _layer(mask)
	var base_layer := -1 if land else _layer(texture)
	# Unit redress already composes a linear highlight/roughness/metalness map.
	# Keep the authored regions and mip footprint at every path hit. Reuse the
	# raw array only for materials with a map; ordinary surfaces add no fetch.
	var surface_layer := -1
	var detail_layer := -1
	if path_materials and Gfx.on("gfx_materials") and material is ShaderMaterial:
		var mask: Texture2D = material.get_shader_parameter("surface_tex") as Texture2D
		if mask != null: surface_layer = _layer(mask)
		var detail: Texture2D = material.get_shader_parameter("surface_detail_tex") as Texture2D
		if detail!=null and material.get_shader_parameter("surface_detail_enabled")==true:detail_layer=_layer(detail)
	var opaque := cutoff <= 0.0 or (base_layer >= 0 and _opaque_textures[base_layer] and diffuse.w >= cutoff)
	if _kernel != null:
		var atlas := {}
		var profile_part:=Time.get_ticks_usec() if _profile_gather_active else 0
		if land and uv2.size() == positions.size():
			for layer: int in _kernel.atlas_layers(arrays,transform,center,RADIUS,_plane): atlas[layer] = _layer(null,layer)
		if _profile_gather_active:_profile_gather_part("atlas_layers",profile_part)
		profile_part=Time.get_ticks_usec() if _profile_gather_active else 0
		var packed: Dictionary = _kernel.pack(arrays,transform,{"land":land,"center":center,"radius":RADIUS,
			"plane":_plane,"limit":MAX_TRIANGLES-triangles,"layer":base_layer,"atlas":atlas,"diffuse":diffuse,"emission":emission})
		if _profile_gather_active:_profile_gather_part("kernel_pack",profile_part)
		if packed.failed: failed = true; return -1
		var count: int = packed.vertices.size()/16
		if count == 0: return -1
		geometries.append({"offset":vertices.size()/16,"count":count,"indices":packed.indices,"opaque":opaque,"cutoff":cutoff,"standard":standard,"surface":surface_profile(material),"relief":surface_relief(material,land),"terrain":land,"foliage_layer":foliage_layer,
			"leaf_light":Gfx.on("gfx_foliage_light"),"bark_relief":Gfx.on("gfx_materials"),"emissive":emission!=Vector3.ZERO,"surface_layer":surface_layer,"detail_layer":detail_layer})
		profile_part=Time.get_ticks_usec() if _profile_gather_active else 0
		vertices.append_array(packed.vertices); triangles += count/3
		if _profile_gather_active:_profile_gather_part("vertices_copy",profile_part)
		return geometries.size()-1
	var start := vertices.size()/16
	var used := PackedInt32Array()
	var normal_transform := transform.basis.inverse().transposed()
	for at in range(0,indices.size()-2,3):
		var ia := indices[at]; var ib := indices[at+1]; var ic := indices[at+2]
		if land:
			var a := transform*positions[ia]; var b := transform*positions[ib]; var c := transform*positions[ic]
			var lo := a.min(b).min(c); var hi := a.max(b).max(c)
			if not _near(AABB(lo,hi-lo)): continue
		var layer := _layer(null,roundi(uv2[ia].x)) if land and uv2.size() == positions.size() else base_layer
		if layer < 0: continue
		if triangles >= MAX_TRIANGLES: failed = true; return -1
		for index in [ia,ib,ic]:
			var p := transform*positions[index]; var n := (normal_transform*normals[index]).normalized()
			vertices.append_array(PackedFloat32Array([p.x,p.y,p.z,uv[index].x,n.x,n.y,n.z,uv[index].y,
				diffuse.x,diffuse.y,diffuse.z,diffuse.w,emission.x,emission.y,emission.z,float(layer)]))
			used.append(index)
		triangles += 1
	var count := vertices.size()/16-start
	if count == 0: return -1
	geometries.append({"offset":start,"count":count,"indices":used,"opaque":opaque,"cutoff":cutoff,"standard":standard,"surface":surface_profile(material),"relief":surface_relief(material,land),"terrain":land,"foliage_layer":foliage_layer,
		"leaf_light":Gfx.on("gfx_foliage_light"),"bark_relief":Gfx.on("gfx_materials"),"emissive":emission!=Vector3.ZERO,"surface_layer":surface_layer,"detail_layer":detail_layer})
	return geometries.size()-1

## Plain values only: the render thread never dereferences a scene node.
func _instance_updates(force: bool) -> Array:
	# First-person clearance is a renderer-only shift, absent from Node3D's
	# transform and the native tracker. Finish the pose after DirectPose, then
	# apply that presentation only to the local camera's visible body. Water
	# reflections and full-body shadow/GI copies retain their authored pose.
	var presented := {}
	if lighting_camera_mask >= 0:
		for group: Dictionary in _view_models.values():
			var model: EIUnitModel = group.model.get_ref()
			if not is_instance_valid(model) or not model.is_inside_tree() or not model._view_active: continue
			model._align_first_person_body()
			for i: int in group.indices:
				var entry: Dictionary = instances[i]
				var mesh: MeshInstance3D = entry.node.get_ref()
				if not is_instance_valid(mesh) or not mesh.is_inside_tree() or not model._view_meshes.has(mesh): continue
				var transform := model.presented_mesh_transform(mesh)
				presented[i] = {"before":entry.transform,"mask":entry.mask,
					"transform":transform,"lighting_offset":mesh.global_transform.origin-transform.origin}
	var changes := _tracked_instance_updates(force)
	if presented.is_empty() and _view_offsets.is_empty(): return changes
	var changed := {}
	for change: Dictionary in changes: changed[change.index] = change
	for i: int in _view_offsets:
		if presented.has(i): continue
		var entry: Dictionary = instances[i]
		var mesh: MeshInstance3D = entry.node.get_ref()
		# The native tracker caches the authored transform, so an idle body
		# need not emit a transform change when its renderer-only shift ends.
		if is_instance_valid(mesh) and mesh.is_inside_tree():entry.transform=mesh.global_transform
		entry.lighting_offset = Vector3.ZERO
		changed[i] = {"index":i,"transform":entry.transform,"mask":entry.mask,"lighting_offset":Vector3.ZERO}
	_view_offsets.clear()
	for i: int in presented:
		var view: Dictionary = presented[i]
		var entry: Dictionary = instances[i]
		var previous_offset: Vector3 = entry.get("lighting_offset",Vector3.ZERO)
		entry.transform = view.transform
		entry.lighting_offset = view.lighting_offset
		_view_offsets[i] = true
		if force or entry.transform != view.before or entry.mask != view.mask or previous_offset != view.lighting_offset:
			changed[i] = {"index":i,"transform":entry.transform,"mask":entry.mask,"lighting_offset":view.lighting_offset}
		else: changed.erase(i)
	return changed.values()

func _tracked_instance_updates(force: bool) -> Array:
	if _kernel != null and (lighting_camera_mask < 0 or _kernel.has_method("lighting_updates")):
		if not _watching:
			_kernel.clear_instances()
			for group: Dictionary in _groups.values():
				var root: Node3D = group.node.get_ref()
				var at: int = _kernel.add_group(root,root is GameUnit)
				for i: int in group.indices:
					var entry: Dictionary = instances[i]
					_kernel.add_instance(at,entry.node.get_ref(),entry.mesh,entry.terrain,i,entry.transform,entry.mask)
			_watching = true
		var changes: Array = _kernel.lighting_updates(force,lighting_camera_mask) if lighting_camera_mask >= 0 else _kernel.updates(force)
		for change: Dictionary in changes:
			instances[change.index].mask = change.mask
			instances[change.index].transform = change.transform
		return changes
	var transforms := []
	for group: Dictionary in _groups.values():
		var root: Node3D = group.node.get_ref()
		var visible := is_instance_valid(root) and root.is_inside_tree() and root.is_visible_in_tree()
		if root is GameUnit and root.is_invisible(): visible = false
		if not force and not visible and group.visible == 0: continue
		group.visible = 1 if visible else 0
		for i: int in group.indices:
			var entry: Dictionary = instances[i]; var node: Node3D = entry.node.get_ref()
			var mask := 0; var transform: Transform3D = entry.transform
			if visible and is_instance_valid(node) and node.is_inside_tree() and (entry.terrain or node.mesh == entry.mesh) and node.is_visible_in_tree():
				mask = 255
				if not entry.terrain: transform = node.global_transform
				if node is MeshInstance3D:
					if lighting_camera_mask >= 0:
						mask = 1 if (node.layers & lighting_camera_mask) != 0 else 0
						if (node.layers & ~EIUnitModel.CLOSE_VIEW_LAYER) != 0: mask |= 4
						if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: mask |= 2
						if node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: mask &= ~1
					else:
						if node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: mask = 2
						elif node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: mask = 1
						# First-person reflections use the complete authored copies,
						# not the sealed torso reserved for the close-view camera.
						if (node.layers & ~EIUnitModel.CLOSE_VIEW_LAYER) == 0: mask = 0
			if force or mask != entry.mask or transform != entry.transform:
				transforms.append({"index":i,"transform":transform,"mask":mask})
				entry.mask = mask; entry.transform = transform
	return transforms

func updates(force := false) -> Dictionary:
	var transforms := _instance_updates(force); var poses := []
	for i in _morph_geometries:
		var geo: Dictionary = geometries[i]
		var morph: Dictionary = geo.morph; var node: MeshInstance3D = morph.node.get_ref()
		if not is_instance_valid(node) or node.mesh != morph.mesh or not node.is_visible_in_tree(): continue
		var weights := []
		for shape in node.get_blend_shape_count(): weights.append(node.get_blend_shape_value(shape))
		if weights == morph.weights and not force: continue
		morph.weights = weights
		var base: PackedVector3Array = morph.arrays[Mesh.ARRAY_VERTEX]
		var normal: PackedVector3Array = morph.arrays[Mesh.ARRAY_NORMAL]
		var p := base.duplicate(); var n := normal.duplicate()
		for k in weights.size():
			if absf(weights[k]) < 0.00001: continue
			var sp: PackedVector3Array = morph.shapes[k][Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = morph.shapes[k][Mesh.ARRAY_NORMAL]
			for v in p.size():
				if node.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED:
					p[v] += (sp[v]-base[v])*weights[k]; n[v] += (sn[v]-normal[v])*weights[k]
				else:
					p[v] += sp[v]*weights[k]; n[v] += sn[v]*weights[k]
		var data := vertices.slice(geo.offset*16,(geo.offset+geo.count)*16)
		for v in geo.indices.size():
			var at: int = geo.indices[v]; var nn := n[at].normalized()
			data[v*16]=p[at].x; data[v*16+1]=p[at].y; data[v*16+2]=p[at].z
			data[v*16+4]=nn.x; data[v*16+5]=nn.y; data[v*16+6]=nn.z
		poses.append({"geometry":i,"data":data.to_byte_array()})
	return {"instances":transforms,"poses":poses}
