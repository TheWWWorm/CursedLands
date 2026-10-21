extends RefCounted
## Bounded static-scene snapshot for the opt-in water RT experiment. Extraction
## is spread over frames. No units, particles, foliage animation or soft-ground
## deformation are baked into this static acceleration structure.
const RADIUS := 80.0
const MAX_TRIANGLES := 240000
const MAX_TEXTURES := 192
const TEXTURE_SIZE := 512
var center := Vector3.ZERO
var vertices := PackedFloat32Array()
var images: Array[Image] = []
var triangles := 0
var failed := false
var pending: Array = []
var _textures := {}
var _terrain: EITerrain
var _plane := 0.0
var _cursor := 0

func begin(terrain: EITerrain, position: Vector3, plane: float) -> void:
	_terrain = terrain
	center = position
	_plane = plane
	for child in terrain.get_children():
		if child is EITerrainSector and child.is_visible_in_tree() and _near(child.global_transform*child.get_aabb()):
			pending.append({"node":weakref(child),"land":true})
	var world := terrain.game_world()
	if world == null: return
	for object: Node3D in world.objects.values():
		if not is_instance_valid(object) or not object.is_visible_in_tree(): continue
		for mesh: MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null or mesh.mesh.get_blend_shape_count() > 0: continue
			if mesh is EIObjectWater or not _near(mesh.global_transform*mesh.get_aabb()): continue
			pending.append({"node":weakref(mesh),"land":false})

func _near(bounds: AABB) -> bool:
	var p := center.clamp(bounds.position,bounds.end)
	return p.distance_squared_to(center) <= RADIUS*RADIUS and bounds.end.y >= _plane-0.1

## Returns true when finished (including a budget failure). Fail the whole
## snapshot rather than silently reflecting a randomly truncated scene.
func step() -> bool:
	var deadline := Time.get_ticks_usec()+6000
	while _cursor < pending.size() and not failed:
		var entry: Dictionary = pending[_cursor]
		_cursor += 1
		var node: Node3D = entry.node.get_ref()
		if is_instance_valid(node) and node.is_visible_in_tree():
			if entry.land:
				_append(node.deformation_arrays(),node.global_transform,null,true)
			else:
				var mesh := node as MeshInstance3D
				for surface in mesh.mesh.get_surface_count():
					if mesh.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
					_append(mesh.mesh.surface_get_arrays(surface),mesh.global_transform,mesh.get_active_material(surface),false)
		if Time.get_ticks_usec() >= deadline: break
	return failed or _cursor >= pending.size()

func _layer(texture: Texture2D, atlas := -1) -> int:
	var key := "terrain:%d"%atlas if atlas >= 0 else str(texture.get_instance_id()) if texture else "white"
	if _textures.has(key): return _textures[key]
	if images.size() >= MAX_TEXTURES:
		failed = true
		return -1
	var image: Image
	if atlas >= 0:
		if atlas >= _terrain._atlases.get_layers(): return -1
		image = _terrain._atlases.get_layer_data(atlas)
	elif texture: image = texture.get_image()
	else:
		image = Image.create(1,1,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
	if image == null or image.is_empty(): return -1
	image = image.duplicate()
	if image.is_compressed() and image.decompress() != OK: return -1
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(TEXTURE_SIZE,TEXTURE_SIZE,Image.INTERPOLATE_BILINEAR)
	var layer := images.size()
	images.append(image)
	_textures[key] = layer
	return layer

func _append(arrays: Array, transform: Transform3D, material: Material, land: bool) -> void:
	if arrays.is_empty(): return
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(positions.size())
		for i in indices.size(): indices[i] = i
	if normals.size() != positions.size() or uv.size() != positions.size(): return
	var texture: Texture2D
	var diffuse := Vector4.ONE
	var emission := Vector3.ZERO
	if not land:
		if material is ShaderMaterial:
			texture = material.get_shader_parameter("albedo_tex") as Texture2D
			# Screen effects and procedural surfaces are not opaque scenery.
			if texture == null: return
			var d: Variant = material.get_shader_parameter("ei_material_diffuse")
			if d is Vector4: diffuse = d
			var e: Variant = material.get_shader_parameter("ei_material_emissive")
			if e is Vector3: emission = e
		elif material is BaseMaterial3D:
			texture = material.albedo_texture
			var c: Color = material.albedo_color
			diffuse = Vector4(c.r,c.g,c.b,c.a)
		else: return
	var base_layer := -1 if land else _layer(texture)
	var normal_transform := transform.basis.inverse().transposed()
	for at in range(0,indices.size()-2,3):
		var ia := indices[at]
		var ib := indices[at+1]
		var ic := indices[at+2]
		var a := transform*positions[ia]
		var b := transform*positions[ib]
		var c := transform*positions[ic]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		if not _near(AABB(lo,hi-lo)): continue
		var layer := _layer(null,roundi(uv2[ia].x)) if land and uv2.size() == positions.size() else base_layer
		if layer < 0: continue
		if triangles >= MAX_TRIANGLES:
			failed = true
			return
		for index in [ia,ib,ic]:
			var p := transform*positions[index]
			var n := (normal_transform*normals[index]).normalized()
			vertices.append_array(PackedFloat32Array([p.x,p.y,p.z,uv[index].x,n.x,n.y,n.z,uv[index].y,
				diffuse.x,diffuse.y,diffuse.z,diffuse.w,emission.x,emission.y,emission.z,float(layer)]))
		triangles += 1
