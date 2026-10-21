extends "res://tools/tests/water_raytrace_device.gd"
## GPU readbacks for live TLAS instances, posed vertices and alpha-aware shadows.
func pixels(device: Device, frame: PackedFloat32Array, changes := {}) -> Color:
	RenderingServer.call_on_render_thread(device.render.bind(Vector2i(128,128),frame.to_byte_array(),changes))
	await frames(6); await RenderingServer.frame_post_draw
	return device.output.get_image().get_pixel(64,64)

func triangle(points: Array, layer: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for p: Vector3 in points:
		data.append_array(PackedFloat32Array([p.x,p.y,p.z,0.5,0,0,1,0.5,1,1,1,1,0,0,0,float(layer)]))
	return data

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"qualified Vulkan RT runtime is available")
	if not Device.supported(): finish(); return
	var camera := Camera3D.new(); add_child(camera)
	camera.position = Vector3(0,-1,3); camera.look_at(Vector3(0,1.5,0)); camera.current = true
	var frame := PackedFloat32Array()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
		for axis in 4:
			var v: Vector4 = matrix[axis]; frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	frame.resize(88)
	for at in [32,33,34]: frame[at] = 0.12
	for at in [36,37,38,39]: frame[at] = 1.0
	frame[40] = sqrt(0.5); frame[42] = sqrt(0.5)
	frame[44] = 90; frame[45] = 100; frame[46] = 100
	var receiver := triangle([Vector3(-3,0.4,0),Vector3(3,0.4,0),Vector3(0,5,0)],0)
	var blocker := triangle([Vector3(0.6,-1,1),Vector3(2.4,-1,1),Vector3(1.5,7,1)],1)
	var data := receiver.duplicate(); data.append_array(blocker)
	for alpha in [1.0,0.0]:
		var white := Image.create(2,2,false,Image.FORMAT_RGBA8); white.fill(Color.WHITE)
		var green := Image.create(2,2,false,Image.FORMAT_RGBA8); green.fill(Color(0,1,0,alpha))
		var device := Device.new()
		var images: Array[Image] = [white,green]
		RenderingServer.call_on_render_thread(device.build.bind(data.to_byte_array(),images,
			[{"offset":0,"count":3},{"offset":3,"count":3}],
			[{"geometry":0,"transform":Transform3D.IDENTITY},{"geometry":1,"transform":Transform3D.IDENTITY}]))
		var ok: bool = await device.prepared; check(ok,"instanced geometry build, alpha="+str(alpha))
		if ok:
			var shadow := await pixels(device,frame)
			check(shadow.r < 0.04 if alpha > 0 else shadow.r > 0.35,
				"opaque blocker casts a sun shadow" if alpha > 0 else "transparent texels do not cast a solid shadow")
			if alpha > 0:
				var bright := await pixels(device,frame,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]})
				check(bright.r > 0.35,"hiding an instance removes its shadow immediately")
				var moved := Transform3D(Basis.IDENTITY,Vector3(4,0,0))
				bright = await pixels(device,frame,{"instances":[{"index":1,"transform":moved,"mask":255}]})
				check(bright.r > 0.35,"moving an instance updates the shadow without rebuilding mesh data")
				var front := Transform3D(Basis.IDENTITY,Vector3(-1.5,0,0))
				var unlit := frame.duplicate()
				for at in [32,33,34]: unlit[at] = 1
				for at in [36,37,38]: unlit[at] = 0
				var tex := await pixels(device,unlit,{"instances":[{"index":1,"transform":front,"mask":255}]})
				check(tex.g > 0.99 and tex.r < 0.01,"instance custom index addresses its own green texture/vertices")
				shadow = await pixels(device,frame,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":255}]})
				check(shadow.r < 0.04,"restoring a moved instance restores its shadow")
				var pose := blocker.duplicate()
				for vertex in 3: pose[vertex*16] += 4.0
				bright = await pixels(device,frame,{"poses":[{"geometry":1,"data":pose.to_byte_array()}]})
				check(bright.r > 0.35,"changed blend-shape vertices rebuild the relevant BLAS")
				shadow = await pixels(device,frame,{"poses":[{"geometry":1,"data":blocker.to_byte_array()}]})
				check(shadow.r < 0.04,"restoring posed vertices restores their shadow")
				var lamp := frame.duplicate()
				for at in [36,37,38]: lamp[at] = 0
				lamp[56]=2; lamp[57]=1.5; lamp[58]=2; lamp[59]=10; lamp[72]=1
				var red := await pixels(device,lamp,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]})
				check(red.r > 0.3 and red.g < 0.04,"nearby red point light illuminates the reflected surface")
				red = await pixels(device,lamp,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":255}]})
				check(red.r < 0.04,"point-light occlusion is traced")
				lamp[59] = 0
				red = await pixels(device,lamp,{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]})
				check(red.r < 0.04,"turning off a local light updates without a scene rebuild")
			else:
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 6.0
				var ortho := frame.duplicate(); ortho[47] = 1.0
				var inverse := camera.get_camera_projection().inverse()
				for axis in 4:
					for component in 4: ortho[axis*4+component] = inverse[axis][component]
				var pixel := await pixels(device,ortho)
				check(pixel.r > 0.35 and pixel.a > 0.99,"orthographic primary rays reflect the same receiver")
				check(device.output.get_image().get_pixel(0,0).a < 0.01,"orthographic misses preserve the sky")
		RenderingServer.call_on_render_thread(device.dispose); await frames(6)
		check(device._owned.is_empty(),"instanced/shadow resources are released")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	await morphs(camera)
	await deferred_geometry(camera)
	camera.queue_free(); await frames(4); finish()

func morphs(camera: Camera3D) -> void:
	# Exercise the CPU scene extractor and its real MeshInstance blend weights,
	# then read back the GPU result; this catches wrong relative/absolute math.
	var frame := PackedFloat32Array()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
		for axis in 4:
			var v: Vector4 = matrix[axis]; frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	frame.resize(88)
	for at in [32,33,34]: frame[at] = 1.0
	frame[44]=90; frame[45]=100; frame[46]=100
	for mode in [Mesh.BLEND_SHAPE_MODE_NORMALIZED,Mesh.BLEND_SHAPE_MODE_RELATIVE]:
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-3,0.4,0),Vector3(3,0.4,0),Vector3(0,5,0)])
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
		arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
		var shape := []; shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX]=PackedVector3Array(); shape[Mesh.ARRAY_NORMAL]=PackedVector3Array()
		for vertex in 3:
			shape[Mesh.ARRAY_VERTEX].append(Vector3(8,0,0)+(arrays[Mesh.ARRAY_VERTEX][vertex] if mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else Vector3.ZERO))
			shape[Mesh.ARRAY_NORMAL].append(Vector3.BACK if mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else Vector3.ZERO)
		var mesh := ArrayMesh.new(); mesh.blend_shape_mode=mode; mesh.add_blend_shape("move")
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[shape])
		var node := MeshInstance3D.new(); node.mesh=mesh; node.material_override=StandardMaterial3D.new(); add_child(node)
		var scene = preload("res://src/game/fx/water_raytrace_scene.gd").new()
		scene.pending=[{"node":weakref(node),"land":false}]
		while not scene.step(): await frames(1)
		check(scene.geometries.size()==1 and scene._morph_geometries.size()==1,"blend mode %d: scene extracts live morph geometry"%mode)
		var device := Device.new()
		RenderingServer.call_on_render_thread(device.build.bind(scene.vertices.to_byte_array(),scene.images,[{"offset":0,"count":3}],[{"geometry":0,"transform":Transform3D.IDENTITY}]))
		var ok: bool = await device.prepared; check(ok,"blend mode %d: extracted geometry builds"%mode)
		if ok:
			var base := await pixels(device,frame,scene.updates())
			check(base.r>0.99 and base.a>0.99,"blend mode %d: base pose intersects camera ray"%mode)
			node.set_blend_shape_value(0,1.0)
			var posed := await pixels(device,frame,scene.updates())
			check(posed.a<0.01,"blend mode %d: deformed mesh moves out of camera ray"%mode)
			node.set_blend_shape_value(0,0.0)
			base=await pixels(device,frame,scene.updates())
			check(base.r>0.99 and base.a>0.99,"blend mode %d: restoring weight restores geometry"%mode)
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			base=await pixels(device,frame,scene.updates())
			check(base.a<0.01,"shadow-only meshes stay out of primary reflection rays")
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			base=await pixels(device,frame,scene.updates())
			check(base.a>0.99,"non-shadow-casting meshes remain visible in primary rays")
			node.layers=EIUnitModel.CLOSE_VIEW_LAYER
			base=await pixels(device,frame,scene.updates())
			check(base.a<0.01,"camera-adjusted first-person mesh is absent from RT")
			node.layers=EIUnitModel.REFLECTION_LAYER
			base=await pixels(device,frame,scene.updates())
			check(base.a>0.99,"complete first-person reflection copy remains visible")
			check(scene.updates().poses.is_empty(),"unchanged blend weights avoid repeated geometry uploads")
			node.hide(); base=await pixels(device,frame,scene.updates())
			check(base.a<0.01 and device._active_instances.is_empty(),"all-hidden scene builds an empty TLAS and returns sky")
			node.show(); base=await pixels(device,frame,scene.updates())
			check(base.a>0.99 and device._active_instances.size()==1,"empty TLAS accepts a revealed instance without recreating the device")
		RenderingServer.call_on_render_thread(device.dispose); await frames(6)
		node.queue_free(); await frames(2)

func deferred_geometry(camera: Camera3D) -> void:
	var frame := PackedFloat32Array()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
		for axis in 4:
			var v: Vector4=matrix[axis]; frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	frame.resize(88); frame[32]=1; frame[33]=1; frame[34]=1; frame[44]=90; frame[45]=100; frame[46]=100
	var data := triangle([Vector3(-3,0.4,0),Vector3(3,0.4,0),Vector3(0,5,0)],0)
	var white := Image.create(2,2,false,Image.FORMAT_RGBA8); white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	var device := Device.new()
	RenderingServer.call_on_render_thread(device.build.bind(data.to_byte_array(),images,[{"offset":0,"count":3}],
		[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":0}]))
	var ok: bool=await device.prepared; check(ok,"an initially hidden scene prepares without geometry builds")
	if ok:
		var shifted := data.duplicate()
		for i in 3: shifted[i*16] += 8
		var pixel := await pixels(device,frame,{"poses":[{"geometry":0,"data":shifted.to_byte_array()}]})
		check(pixel.a<0.01 and not device._blases[0].is_valid(),"hidden posed geometry stays unbuilt and invisible")
		pixel=await pixels(device,frame,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":255}]})
		check(pixel.a<0.01 and device._blases[0].is_valid(),"first reveal builds the latest posed vertices")
		var retained: RID=device._blases[0]
		pixel=await pixels(device,frame,{"poses":[{"geometry":0,"data":data.to_byte_array()}]})
		check(pixel.r>0.99 and pixel.a>0.99,"revealed geometry receives later pose changes")
		await pixels(device,frame,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":0}]})
		pixel=await pixels(device,frame,{"instances":[{"index":0,"transform":Transform3D.IDENTITY,"mask":255}]})
		check(pixel.a>0.99 and device._blases[0]==retained,"hide and reveal reuse the existing geometry structure")
	RenderingServer.call_on_render_thread(device.dispose); await frames(6)
	check(device._owned.is_empty(),"lazily allocated geometry releases all GPU resources")
