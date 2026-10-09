extends RefCounted
## Diagnostic only. Preserve the authored pose nodes; give each source vertex
## exactly one bone. No smooth weights, production switch or gameplay hook.
var skeleton: Skeleton3D
var body: MeshInstance3D
var bodies: Array[MeshInstance3D] = []
var parts: Array[Dictionary] = []
var before_meshes := 0
var merged_meshes := 0
var surfaces := 0
var last_sync_usec := 0
var last_updates := 0

func build(model: EIUnitModel) -> void:
	var figure := EIFigure.get_model(model.template)
	var groups := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		before_meshes += 1
		if model.template == "unmowi": continue # translucent surfaces need individual sorting
		var part := mi.get_parent() as EIAnimPart
		if OS.get_cmdline_user_args().has("--rigid-inspect"):
			var sizes := []
			for value in mi.mesh.surface_get_arrays(0): sizes.append(-1 if value == null else value.size())
			print("RIGID_INPUT ",JSON.stringify({"parent":str(mi.get_parent().name),"animated_part":part != null,
				"visible":mi.visible,"skin":mi.skin != null,"array_mesh":mi.mesh is ArrayMesh,
				"shapes":mi.mesh.get_blend_shape_count(),"surfaces":mi.mesh.get_surface_count(),"arrays":sizes,
				"body":EIUnitModel._is_body_part(str(mi.get_parent().name),figure),"material":mi.get_active_material(0).get_instance_id()}))
		if part == null or not mi.visible or mi.skin != null or not mi.mesh is ArrayMesh: continue
		var name := String(part.name)
		# Heads keep the detailed-head option; weapons/morphs retain their own
		# visibility and deformation. Their original part nodes remain too.
		if name == "hd" or not EIUnitModel._is_body_part(name,figure): continue
		if mi.mesh.get_surface_count() != 1 or mi.mesh.get_blend_shape_count() != 0: continue
		if mi.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: continue
		var material := mi.get_active_material(0)
		if material == null: continue
		var arrays := mi.mesh.surface_get_arrays(0)
		var supported := true
		for slot in Mesh.ARRAY_MAX:
			if slot not in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX] and arrays[slot] != null and arrays[slot].size() > 0:
				supported = false
		if not supported: continue
		var key := "%d:%d:%d" % [material.get_instance_id(),mi.layers,mi.cast_shadow]
		if not groups.has(key): groups[key] = []
		groups[key].append({"node":part,"mesh_node":mi,"mesh":mi.mesh,"local":mi.transform,
			"part_path":model.get_path_to(part),"material":material,"arrays":arrays})
	var usable := []
	for group: Array in groups.values():
		if group.size() > 1: usable.append(group)
	if usable.is_empty(): return
	skeleton = Skeleton3D.new(); skeleton.name = "RigidSkeleton"; model.add_child(skeleton)
	var skin := Skin.new()
	for group: Array in usable:
		var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array()
		var tangents := PackedFloat32Array()
		var bones := PackedInt32Array(); var weights := PackedFloat32Array(); var indices := PackedInt32Array()
		for item: Dictionary in group:
			var bone := skeleton.add_bone("part_"+str(parts.size()))
			skeleton.set_bone_rest(bone,Transform3D.IDENTITY)
			skin.add_bind(bone,Transform3D.IDENTITY)
			item.bone = bone; item.last_pose = Transform3D(Basis(),Vector3.INF)
			parts.append(item)
			var arrays: Array = item.arrays
			var start := vertices.size()
			vertices.append_array(arrays[Mesh.ARRAY_VERTEX]); normals.append_array(arrays[Mesh.ARRAY_NORMAL])
			tangents.append_array(arrays[Mesh.ARRAY_TANGENT])
			uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
			for v in arrays[Mesh.ARRAY_VERTEX].size():
				bones.append_array([bone,0,0,0]); weights.append_array([1.0,0.0,0.0,0.0])
			for index: int in arrays[Mesh.ARRAY_INDEX]: indices.append(start+index)
		var output := []; output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = vertices; output[Mesh.ARRAY_NORMAL] = normals
		output[Mesh.ARRAY_TANGENT] = tangents
		output[Mesh.ARRAY_TEX_UV] = uv; output[Mesh.ARRAY_INDEX] = indices
		output[Mesh.ARRAY_BONES] = bones; output[Mesh.ARRAY_WEIGHTS] = weights
		var merged := ArrayMesh.new(); merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,output)
		var mi := MeshInstance3D.new(); mi.name = "Body" if bodies.is_empty() else "Body"+str(bodies.size())
		mi.mesh = merged; mi.set_surface_override_material(0,group[0].material)
		mi.layers = group[0].mesh_node.layers; mi.cast_shadow = group[0].mesh_node.cast_shadow
		skeleton.add_child(mi); bodies.append(mi)
	for mi: MeshInstance3D in bodies:
		mi.skin = skin; mi.skeleton = NodePath("..")
	body = bodies[0]
	# Only the draw children are replaced. Logical part names/geometry/poses
	# stay intact. Metadata keeps a source mesh for the existing limb copier.
	for item: Dictionary in parts:
		item.node.set_meta("weld_mesh",[item.mesh,item.material])
		item.mesh_node.free(); item.erase("mesh_node")
	merged_meshes = parts.size(); surfaces = bodies.size()
	sync()

func sync() -> void:
	last_updates = 0
	if not is_instance_valid(skeleton): return
	var start := Time.get_ticks_usec()
	var inverse := skeleton.global_transform.affine_inverse()
	for item: Dictionary in parts:
		var pose: Transform3D = inverse * item.node.global_transform * item.local
		if pose != item.last_pose:
			skeleton.set_bone_pose(item.bone,pose)
			item.last_pose = pose; last_updates += 1
	last_sync_usec = Time.get_ticks_usec()-start

func geometry_error(reference: EIUnitModel) -> Dictionary:
	var peak := 0.0; var normal_peak := 0.0; var vertices := 0
	if not is_instance_valid(skeleton): return {"vertices":0,"position_error":0.0,"normal_error":0.0}
	for item: Dictionary in parts:
		var original := reference.get_node(item.part_path) as Node3D
		var expected: Transform3D = original.global_transform * item.local
		var actual := body.global_transform * skeleton.get_bone_global_pose(item.bone)
		var points: PackedVector3Array = item.arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = item.arrays[Mesh.ARRAY_NORMAL]
		for i in points.size():
			peak = maxf(peak,(expected*points[i]).distance_to(actual*points[i]))
			var a := (expected.basis.inverse().transposed()*normals[i]).normalized()
			var b := (actual.basis.inverse().transposed()*normals[i]).normalized()
			normal_peak = maxf(normal_peak,a.distance_to(b)); vertices += 1
	return {"vertices":vertices,"position_error":peak,"normal_error":normal_peak}
