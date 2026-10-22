extends RefCounted
## CPU-owned scene description. Geometry is shared by rigid instances; only
## transforms, visibility and changed blend-shape vertices cross each frame.
const RADIUS := 96.0
const MAX_TRIANGLES := 320000
const MAX_TEXTURES := 192
const MAX_INSTANCES := 4096
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
var _groups := {}
var _morph_geometries: Array[int] = []
var _terrain: EITerrain
var _plane := 0.0
var _cursor := 0
var _kernel: Object
var _watching := false
# Negative keeps the original water masks. Scene lighting distinguishes
# camera-visible receivers (1), shadow casters (2), and GI surfaces (4).
var lighting_camera_mask := -1

func _init() -> void:
	if ClassDB.class_exists("WaterRaytraceKernel") and not OS.get_cmdline_user_args().has("--ei-script-water-rt"):
		_kernel = ClassDB.instantiate("WaterRaytraceKernel")

func begin(terrain: EITerrain, position: Vector3, plane: float) -> void:
	_terrain = terrain; center = position; _plane = plane
	for child in terrain.get_children():
		if child is EITerrainSector and _near(child.global_transform*child.get_aabb()):
			pending.append({"node":weakref(child),"land":true})
	var materials := {}
	for mesh: MeshInstance3D in _scene_meshes():
		pending.append({"node":weakref(mesh),"land":false})
		_nodes[mesh.get_instance_id()] = _mesh_version(mesh,materials)

func _scene_meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var world := _terrain.game_world()
	if world == null: return found
	for root: Node3D in world.objects.values()+world.units.values():
		if not is_instance_valid(root): continue
		# Include hidden parts, too: visibility is a live instance mask, and a
		# fogged creature must not require a fresh mesh build when revealed.
		if root.global_position.distance_squared_to(center) > pow(RADIUS+24.0,2): continue
		for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null or mesh is EIObjectWater: continue
			if not _near(mesh.global_transform*mesh.get_aabb(),false): continue
			var supported := false
			for surface in mesh.mesh.get_surface_count():
				var mat := mesh.get_active_material(surface)
				if mat is BaseMaterial3D or (mat is ShaderMaterial and mat.get_shader_parameter("albedo_tex") is Texture2D):
					supported = true; break
			if supported:
				found.append(mesh)
				_mesh_roots[mesh.get_instance_id()] = weakref(root)
	return found

func _material_version(material: Material) -> Array:
	if material is ShaderMaterial:
		var texture: Texture2D = material.get_shader_parameter("albedo_tex") as Texture2D
		return [material.shader.get_instance_id() if material.shader else 0,texture.get_instance_id() if texture else 0,
			material.get_shader_parameter("ei_material_diffuse"),material.get_shader_parameter("ei_material_emissive")]
	if material is BaseMaterial3D:
		return [material.albedo_texture.get_instance_id() if material.albedo_texture else 0,material.albedo_color,
			material.transparency,material.alpha_scissor_threshold,material.emission_enabled,material.emission,
			material.emission_energy_multiplier]
	return []

func _mesh_version(mesh: MeshInstance3D, materials: Dictionary) -> Array:
	var version := [mesh.mesh.get_instance_id()]
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		var key := material.get_instance_id() if material else 0
		if not materials.has(key): materials[key] = _material_version(material)
		version.append([key,materials[key]])
	return version

func topology_changed() -> bool:
	var current := {}
	var materials := {}
	for mesh: MeshInstance3D in _scene_meshes(): current[mesh.get_instance_id()] = _mesh_version(mesh,materials)
	return current != _nodes

func _near(bounds: AABB, clip_plane := true) -> bool:
	var p := center.clamp(bounds.position,bounds.end)
	return p.distance_squared_to(center) <= RADIUS*RADIUS and (not clip_plane or bounds.end.y >= _plane-0.1)

func step() -> bool:
	var deadline := Time.get_ticks_usec()+6000
	while _cursor < pending.size() and not failed:
		var entry: Dictionary = pending[_cursor]; _cursor += 1
		var node: Node3D = entry.node.get_ref()
		if is_instance_valid(node):
			if entry.land:
				var geometry := _append(node.deformation_arrays(),node.global_transform,null,true)
				_add_instance(node,geometry,Transform3D.IDENTITY)
			else:
				var mesh := node as MeshInstance3D
				for surface in mesh.mesh.get_surface_count():
					# Only ArrayMesh exposes this query to scripts. PrimitiveMesh
					# uses triangles except PointMesh, which has no ray surface.
					if mesh.mesh is ArrayMesh:
						if mesh.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
					elif not mesh.mesh is PrimitiveMesh or mesh.mesh is PointMesh: continue
					var material := mesh.get_active_material(surface)
					var key := "%s:%s:%s"%[mesh.mesh.get_instance_id(),surface,material.get_instance_id() if material else 0]
					var morph: bool = mesh.get_blend_shape_count() > 0
					if morph: key += ":"+str(node.get_instance_id())
					var geometry: int = _mesh_cache.get(key,-1)
					if geometry < 0:
						geometry = _append(mesh.mesh.surface_get_arrays(surface),Transform3D.IDENTITY,material,false)
						if geometry >= 0:
							_mesh_cache[key] = geometry
							if morph:
								_morph_geometries.append(geometry)
								geometries[geometry].morph = {"node":weakref(node),"mesh":mesh.mesh,"surface":surface,
									"arrays":mesh.mesh.surface_get_arrays(surface),"shapes":mesh.mesh.surface_get_blend_shape_arrays(surface),"weights":[]}
					_add_instance(node,geometry,node.global_transform)
		if Time.get_ticks_usec() >= deadline: break
	return failed or _cursor >= pending.size()

func _add_instance(node: Node3D, geometry: int, transform: Transform3D) -> void:
	if geometry < 0: return
	_watching = false
	if instances.size() >= MAX_INSTANCES: failed = true; return
	var root: Node3D = _mesh_roots[node.get_instance_id()].get_ref() if _mesh_roots.has(node.get_instance_id()) else node
	var key := root.get_instance_id()
	if not _groups.has(key): _groups[key] = {"node":weakref(root),"indices":[],"visible":-1}
	_groups[key].indices.append(instances.size())
	instances.append({"geometry":geometry,"node":weakref(node),"mesh":node.mesh if node is MeshInstance3D else null,
		"terrain":node is EITerrainSector,"transform":transform,"mask":-1})

func _layer(texture: Texture2D, atlas := -1) -> int:
	var key := "terrain:%d"%atlas if atlas >= 0 else str(texture.get_instance_id()) if texture else "white"
	if _textures.has(key): return _textures[key]
	if images.size() >= MAX_TEXTURES: failed = true; return -1
	var image: Image
	if atlas >= 0:
		if atlas >= _terrain._atlases.get_layers(): return -1
		image = _terrain._atlases.get_layer_data(atlas)
	elif texture: image = texture.get_image()
	else:
		image = Image.create(1,1,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	if image == null or image.is_empty(): return -1
	image = image.duplicate()
	if image.is_compressed() and image.decompress() != OK: return -1
	image.clear_mipmaps(); image.convert(Image.FORMAT_RGBA8)
	image.resize(TEXTURE_SIZE,TEXTURE_SIZE,Image.INTERPOLATE_BILINEAR); image.generate_mipmaps()
	_opaque_textures.append(image.detect_alpha() == Image.ALPHA_NONE)
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
	var base_layer := -1 if land else _layer(texture)
	var opaque := cutoff <= 0.0 or (base_layer >= 0 and _opaque_textures[base_layer] and diffuse.w >= cutoff)
	if _kernel != null:
		var atlas := {}
		if land and uv2.size() == positions.size():
			for layer: int in _kernel.atlas_layers(arrays,transform,center,RADIUS,_plane): atlas[layer] = _layer(null,layer)
		var packed: Dictionary = _kernel.pack(arrays,transform,{"land":land,"center":center,"radius":RADIUS,
			"plane":_plane,"limit":MAX_TRIANGLES-triangles,"layer":base_layer,"atlas":atlas,"diffuse":diffuse,"emission":emission})
		if packed.failed: failed = true; return -1
		var count: int = packed.vertices.size()/16
		if count == 0: return -1
		geometries.append({"offset":vertices.size()/16,"count":count,"indices":packed.indices,"opaque":opaque,"cutoff":cutoff,"standard":standard})
		vertices.append_array(packed.vertices); triangles += count/3
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
	geometries.append({"offset":start,"count":count,"indices":used,"opaque":opaque,"cutoff":cutoff,"standard":standard})
	return geometries.size()-1

## Plain values only: the render thread never dereferences a scene node.
func _instance_updates(force: bool) -> Array:
	if _kernel != null and lighting_camera_mask < 0:
		if not _watching:
			_kernel.clear_instances()
			for group: Dictionary in _groups.values():
				var root: Node3D = group.node.get_ref()
				var at: int = _kernel.add_group(root,root is GameUnit)
				for i: int in group.indices:
					var entry: Dictionary = instances[i]
					_kernel.add_instance(at,entry.node.get_ref(),entry.mesh,entry.terrain,i,entry.transform,entry.mask)
			_watching = true
		var changes: Array = _kernel.updates(force)
		for change: Dictionary in changes:
			instances[change.index].mask = change.mask
			instances[change.index].transform = change.transform
		return changes
	var transforms := []
	for group: Dictionary in _groups.values():
		var root: Node3D = group.node.get_ref()
		var visible := is_instance_valid(root) and root.is_visible_in_tree()
		if root is GameUnit and root.is_invisible(): visible = false
		if not force and not visible and group.visible == 0: continue
		group.visible = 1 if visible else 0
		for i: int in group.indices:
			var entry: Dictionary = instances[i]; var node: Node3D = entry.node.get_ref()
			var mask := 0; var transform: Transform3D = entry.transform
			if visible and is_instance_valid(node) and (entry.terrain or node.mesh == entry.mesh) and node.is_visible_in_tree():
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
