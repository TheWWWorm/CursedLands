extends Node
const Bounds = preload("res://src/ui/mesh_screen_rect.gd")
var checks := 0
var failures := 0
var kernel: RefCounted
var camera: Camera3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL ",label)

func native_rect(part: MeshInstance3D, view: Dictionary):
	return kernel.retained_bounds(part,view.planes,view.projection,view.inverse_basis,view.origin,view.size)

func compare(part: MeshInstance3D, label: String) -> void:
	var view := Bounds.camera_context(camera)
	Bounds._drop_rect(part.get_instance_id())
	var expected := Bounds.of_context(part,camera,view)
	check(Bounds.of_retained_context(part,camera,view)==expected,label)

func _ready() -> void:
	kernel=Bounds._kernel
	check(kernel!=null and kernel.has_method("retained_bounds"),"fused native mechanism bounds available")
	if failures:
		print("PICKING_RETAINED ",checks," checks ",failures," failures")
		get_tree().quit(1);return
	camera=Camera3D.new();add_child(camera);camera.current=true
	var rng:=RandomNumberGenerator.new();rng.seed=829166
	var specimens: Array[MeshInstance3D]=[]
	for trial in 432:
		camera.projection=int(trial/6)%3;camera.near=.1;camera.far=50;camera.size=12;camera.fov=65
		camera.frustum_offset=Vector2(.3,-.2)
		camera.transform=Transform3D(Basis.from_euler(Vector3(.17,-.24,.08)),Vector3(10000,-20000,30000) if trial%7==0 else Vector3(3,2,1))
		var mesh:=ArrayMesh.new();mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED if trial%2==0 else Mesh.BLEND_SHAPE_MODE_RELATIVE
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		var vertices:=PackedVector3Array();var count:=3*(1+trial%41)
		var extent:float=[.02,.3,2.,12.][trial%4]
		for i in count:vertices.append(Vector3(rng.randf_range(-extent,extent),rng.randf_range(-extent,extent),rng.randf_range(-extent,extent)))
		arrays[Mesh.ARRAY_VERTEX]=vertices
		if trial%2==0:
			var indices:=PackedInt32Array()
			for i in count:indices.append(count-i-1)
			arrays[Mesh.ARRAY_INDEX]=indices
		var shape_arrays:=[];var shapes:=[]
		for shape_index in trial%3:
			mesh.add_blend_shape("pose"+str(shape_index))
			var shape:=vertices.duplicate()
			for i in count:shape[i]+=Vector3(rng.randf(),rng.randf(),rng.randf())*3
			var channels:=[];channels.resize(Mesh.ARRAY_MAX);channels[Mesh.ARRAY_VERTEX]=shape
			shape_arrays.append(channels);shapes.append(shape)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP if trial%5==0 else Mesh.PRIMITIVE_TRIANGLES,arrays,shape_arrays)
		mesh.set_meta(EIFigure.GEOMETRY_META,[vertices,arrays[Mesh.ARRAY_INDEX]])
		if not shapes.is_empty():mesh.set_meta(EIFigure.SHAPES_META,shapes)
		var part:=MeshInstance3D.new();part.mesh=mesh;add_child(part)
		for i in shapes.size():part.set_blend_shape_value(i,[0.,.000001,-.25,.7,2.][(trial+i)%5])
		var center:Vector3=[Vector3(0,0,-8),Vector3(30,0,-8),Vector3(0,0,-.1),Vector3(0,0,-50),Vector3(0,30,-8),Vector3(0,0,5)][trial%6]
		part.transform=camera.transform*Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(.7,1.4,1.1)),center)
		var view:=Bounds.camera_context(camera)
		check(native_rect(part,view) is Rect2i,"authored geometry takes native path "+str(trial))
		compare(part,"projection/morph/index/clip boundary "+str(trial))
		if trial%12==0:
			Bounds._kernel=null;Bounds._drop_rect(part.get_instance_id())
			var scalar:=Bounds.of_context(part,camera,view);Bounds._kernel=kernel
			check(native_rect(part,view)==scalar,"unaccelerated scalar oracle "+str(trial))
		part.position+=Vector3(.27,-.41,.16)
		if not shapes.is_empty():part.set_blend_shape_value(0,-.8)
		compare(part,"same-frame live transform and morph "+str(trial))
		check(mesh.get_meta(EIFigure.GEOMETRY_META)[0]==vertices,"source vertices remain immutable "+str(trial))
		part.hide();compare(part,"hidden mechanism "+str(trial));part.show()
		if trial<48:specimens.append(part)
		else:part.free()
	var generic:=MeshInstance3D.new();generic.mesh=ArrayMesh.new()
	generic.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
	generic.position=Vector3(0,0,-5);add_child(generic)
	var view:=Bounds.camera_context(camera)
	check(native_rect(generic,view)==null,"third-party geometry uses existing fallback")
	compare(generic,"generic fallback bounds")
	var part:MeshInstance3D=specimens[0]
	part.skin=Skin.new()
	check(native_rect(part,view)==null,"skin keeps general path")
	compare(part,"skin fallback without a skeleton");part.skin=null
	var multi:=ArrayMesh.new()
	var channels:=BoxMesh.new().get_mesh_arrays()
	for i in 2:multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,channels)
	multi.set_meta(EIFigure.GEOMETRY_META,[channels[Mesh.ARRAY_VERTEX],channels[Mesh.ARRAY_INDEX]])
	part.mesh=multi
	check(native_rect(part,view)==null,"multiple surfaces keep general path")
	compare(part,"multiple surfaces fallback")
	var large:=ArrayMesh.new();var vertices:=PackedVector3Array()
	for i in 2052:vertices.append(Vector3(i%3,i%7,-5))
	channels=[];channels.resize(Mesh.ARRAY_MAX);channels[Mesh.ARRAY_VERTEX]=vertices
	large.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,channels)
	large.set_meta(EIFigure.GEOMETRY_META,[vertices,null]);part.mesh=large
	check(native_rect(part,view)==null,"large geometry keeps exact cache")
	compare(part,"large geometry fallback")
	var morph:MeshInstance3D=specimens[1]
	var saved_shapes=morph.mesh.get_meta(EIFigure.SHAPES_META)
	morph.mesh.remove_meta(EIFigure.SHAPES_META)
	check(native_rect(morph,view)==null,"missing morph metadata keeps general path")
	compare(morph,"missing morph metadata fallback")
	morph.mesh.set_meta(EIFigure.SHAPES_META,saved_shapes)
	# Replace the mesh and retained arrays during the same frame.
	part.mesh=generic.mesh;compare(part,"same-frame mesh replacement")
	generic.mesh=null;compare(generic,"missing mesh")
	generic.free()
	# Moving-camera workload: same live geometry, no renderer or readback timing.
	var elapsed:={}
	for accelerated in [false,true,true,false]:
		var start:=Time.get_ticks_usec()
		for frame in 40:
			camera.position=Vector3(frame*.013,2,1)
			view=Bounds.camera_context(camera)
			for item:MeshInstance3D in specimens:
				if accelerated:Bounds.of_retained_context(item,camera,view)
				else:Bounds.of_context(item,camera,view)
		var key:="native" if accelerated else "script"
		if not elapsed.has(key):elapsed[key]=[]
		elapsed[key].append(Time.get_ticks_usec()-start)
	for item:MeshInstance3D in specimens:item.free()
	camera.free()
	print("PICKING_RETAINED_TIMING ",JSON.stringify(elapsed))
	print("PICKING_RETAINED ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
