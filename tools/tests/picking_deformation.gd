extends Node
const MeshScreenRect = preload("res://src/ui/mesh_screen_rect.gd")
## Exact differential test for the native morph/skin stage of pointer bounds.
var checks := 0
var failures := 0
var native_us := 0
var script_us := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<12:printerr("FAIL ",label)

func reference(base: PackedVector3Array, shapes: Array, morphs: PackedFloat64Array, normalized: bool, bones: PackedInt32Array, weights: PackedFloat32Array, poses: Array[Transform3D]) -> PackedVector3Array:
	var vertices := base.duplicate()
	for k in shapes.size():
		var weight := morphs[k]
		if is_zero_approx(weight):continue
		var shape:PackedVector3Array=shapes[k]
		if shape.size()!=vertices.size():continue
		for i in vertices.size():vertices[i]+=(shape[i]-base[i] if normalized else shape[i])*weight
	if weights.is_empty():return vertices
	var stride:=int(weights.size()/vertices.size())
	for i in vertices.size():
		var point:=Vector3.ZERO
		for j in stride:
			var at:=i*stride+j;var bone:=int(bones[at])
			if bone>=0 and bone<poses.size():point+=(poses[bone]*vertices[i])*float(weights[at])
		vertices[i]=point
	return vertices

func _ready() -> void:
	var kernel: Object=ClassDB.instantiate("ScreenRectKernel")
	check(kernel!=null and kernel.has_method("deform_vertices") and kernel.has_method("deformation_state"),"native deformation available")
	if failures:get_tree().quit(1);return
	var rng:=RandomNumberGenerator.new();rng.seed=828619
	for trial in 160:
		var base:=PackedVector3Array()
		var bones:=PackedInt32Array();var weights:=PackedFloat32Array()
		var count:=1+trial%79
		var poses:Array[Transform3D]=[]
		for j in 8:
			poses.append(Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(.7,1.4,1.1)),Vector3(rng.randf(),rng.randf(),rng.randf())*20))
		var stride:=0 if trial%4==0 else 4 if trial%2==0 else 8
		for i in count:
			base.append(Vector3(rng.randf_range(-5,5),rng.randf_range(-5,5),rng.randf_range(-5,5)))
			for j in stride:
				bones.append(rng.randi_range(-1,9));weights.append(rng.randf()/maxi(1,stride))
		var shapes:=[];var morphs:=PackedFloat64Array()
		for k in trial%5:
			var shape:=base.duplicate()
			for i in count:shape[i]+=Vector3(rng.randf(),rng.randf(),rng.randf())
			if trial%9==0:shape.resize(count+1)
			shapes.append(shape);morphs.append([0.0,0.000001,0.00002,-.25,.7][(trial+k)%5])
		var originals:=[base.duplicate(),shapes.duplicate(true),bones.duplicate(),weights.duplicate(),poses.duplicate()]
		for normalized in [false,true]:
			var start:=Time.get_ticks_usec()
			var expected:=reference(base,shapes,morphs,normalized,bones,weights,poses)
			script_us+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
			var actual:PackedVector3Array=kernel.deform_vertices(base,shapes,morphs,normalized,bones,weights,poses)
			native_us+=Time.get_ticks_usec()-start
			check(actual==expected,"exact normalized/relative skin result "+str(trial)+"/"+str(normalized))
		check(base==originals[0] and shapes==originals[1] and bones==originals[2] and weights==originals[3] and poses==originals[4],"input snapshots unchanged "+str(trial))
	var smooth:=EIUnitModel.smooth_joints
	for weld in [false,true]:
		EIUnitModel.smooth_joints=weld
		for prototype in ["Human Hero","dragonbrownm16","cyclopsa20"]:
			var model:=EIUnitModel.create({"prototype":prototype});add_child(model)
			for pose in ["idle","walk","attack"]:
				model.act(pose,1,0.0);model.player.advance(.23);model.flush_pending_pose()
				for mi:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
					if mi.mesh==null:continue
					var morphs:=PackedFloat64Array()
					for k in mi.mesh.get_blend_shape_count():morphs.append(mi.get_blend_shape_value(k))
					var state: Array = kernel.deformation_state(mi)
					check(state[0] == morphs,"native reads all current morph weights")
					check(state[1] == MeshScreenRect._skin_poses(mi),"native reads current named/indexed bind poses")
					check(state[2] == (mi.skin != null and mi.get_node_or_null(mi.skeleton) is Skeleton3D),"native identifies valid skin binding")
					for surface:Dictionary in MeshScreenRect._mesh_data(mi.mesh).surfaces:
						var skin:bool=mi.skin!=null and surface.bones!=null and surface.weights!=null and mi.get_node_or_null(mi.skeleton) is Skeleton3D
						var actual:PackedVector3Array=kernel.deform_vertices(surface.vertices,surface.shapes,morphs,mi.mesh is ArrayMesh and mi.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED,surface.bones if skin else PackedInt32Array(),surface.weights if skin else PackedFloat32Array(),MeshScreenRect._skin_poses(mi))
						check(actual==MeshScreenRect._posed(mi,surface),"exact authored pose "+prototype+"/"+pose+"/"+str(weld)+"/"+str(mi.name))
			model.free()
	EIUnitModel.smooth_joints=smooth
	# Explicitly cover named/indexed binds, unresolved names and a pose edit
	# within the same render frame; the native state reader must retain nothing.
	var holder := Node3D.new(); add_child(holder)
	var rig := Skeleton3D.new(); rig.name = "Rig"; holder.add_child(rig)
	rig.add_bone("root"); rig.set_bone_pose_position(0,Vector3(1,2,3))
	rig.force_update_all_bone_transforms()
	var instance := MeshInstance3D.new(); instance.mesh = BoxMesh.new(); holder.add_child(instance)
	var binding := Skin.new(); binding.set_bind_count(3)
	binding.set_bind_bone(0,0); binding.set_bind_name(1,"root"); binding.set_bind_name(2,"missing")
	for i in 3: binding.set_bind_pose(i,Transform3D(Basis.IDENTITY,Vector3(i,0,0)))
	instance.skeleton = NodePath("../Rig"); instance.skin = binding
	check(kernel.deformation_state(instance)[1] == MeshScreenRect._skin_poses(instance),"named, indexed and missing bone bindings match")
	rig.set_bone_pose_position(0,Vector3(4,5,6)); rig.force_update_all_bone_transforms()
	check(kernel.deformation_state(instance)[1] == MeshScreenRect._skin_poses(instance),"same-frame bone edits are sampled immediately")
	instance.skeleton = NodePath("../Absent")
	var missing_state: Array = kernel.deformation_state(instance)
	check(missing_state[1].is_empty() and not missing_state[2],"missing skeleton retains undeformed fallback")
	holder.free()
	var empty_state: Array = kernel.deformation_state(null)
	check(empty_state[0].is_empty() and empty_state[1].is_empty() and not empty_state[2],"null instance state is safe")
	var one:=PackedVector3Array([Vector3.ONE])
	var identity:Array[Transform3D]=[Transform3D.IDENTITY]
	check(kernel.deform_vertices(PackedVector3Array(),[],PackedFloat64Array(),false,PackedInt32Array(),PackedFloat32Array(),identity).is_empty(),"empty source is safe")
	check(kernel.deform_vertices(one,[one],PackedFloat64Array(),false,PackedInt32Array(),PackedFloat32Array(),identity).is_empty(),"missing morph weights rejected")
	check(kernel.deform_vertices(one,[],PackedFloat64Array(),false,PackedInt32Array(),PackedFloat32Array([1.0]),identity).is_empty(),"truncated bone array rejected")
	check(kernel.deform_vertices(PackedVector3Array([Vector3.ONE,Vector3.ZERO]),[],PackedFloat64Array(),false,PackedInt32Array([0]),PackedFloat32Array([1.0]),identity).is_empty(),"partial influence row rejected")
	check(kernel.deform_vertices(one,[],PackedFloat64Array(),false,PackedInt32Array([-1,19]),PackedFloat32Array([.5,.5]),identity)==PackedVector3Array([Vector3.ZERO]),"invalid bone indices retain the script's zero contribution")
	print("PICKING_DEFORMATION checks=",checks," failures=",failures," native_us=",native_us," script_us=",script_us)
	get_tree().quit(1 if failures else 0)
