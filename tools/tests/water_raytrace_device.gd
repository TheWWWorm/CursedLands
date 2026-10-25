extends Node
## Actual GPU readbacks: closest hit, texture/UBO/vertex access, alpha rejection,
## misses, water-plane clipping, target resize and queued teardown.
const Device = preload("res://src/game/fx/water_raytrace_device.gd")
var out := "user://water-rt-device"
var checks := 0
var failures := []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void: run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"qualified hardware RT runtime is available")
	if not Device.supported(): finish(); return
	var camera := Camera3D.new(); add_child(camera)
	camera.position = Vector3(0,-1,3)
	camera.look_at(Vector3(0,1.5,0)); camera.current = true
	var frame := PackedFloat32Array()
	for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
		for axis in 4:
			var v: Vector4 = matrix[axis]
			frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	frame.append_array(PackedFloat32Array([1,1,1,0,0,0,0,0,0,1,0,0,90,100,100,0,0.2,0.3,0.5,0]))
	for transparent in [false,true]:
		var data := PackedFloat32Array()
		for layer in 2:
			for p: Vector3 in [Vector3(-3,0.4,-layer),Vector3(3,0.4,-layer),Vector3(0,5,-layer)]:
				data.append_array(PackedFloat32Array([p.x,p.y,p.z,0.5,0,0,1,0.5,1,1,1,1,0,0,0,float(layer)]))
		var red := Image.create(2,2,false,Image.FORMAT_RGBA8)
		red.fill(Color(1,0,0,0 if transparent else 1))
		var green := Image.create(2,2,false,Image.FORMAT_RGBA8); green.fill(Color.GREEN)
		var images: Array[Image] = [red,green]
		var device := Device.new()
		# Save loading starts with hidden placements. Reveal the geometry on the
		# first trace, then rebuild the TLAS after tracing when resizing below.
		# The second build must not add AS-build sync to the frame UBO barrier.
		var placements := [{"geometry":0,"transform":Transform3D.IDENTITY,"mask":0}]
		RenderingServer.call_on_render_thread(device.build.bind(data.to_byte_array(),images,[],placements))
		var ok: bool = await device.prepared
		check(ok,"build hardware acceleration structure, alpha="+str(transparent))
		if ok:
			var material_texture := RID()
			for size: Vector2i in [Vector2i(128,128),Vector2i(96,64)]:
				var pose := Transform3D(Basis.IDENTITY,Vector3(0.05,0,0)) if material_texture.is_valid() else Transform3D.IDENTITY
				var changes := {"instances":[{"index":0,"transform":pose,"mask":255}]}
				RenderingServer.call_on_render_thread(device.render.bind(size,frame.to_byte_array(),changes))
				await frames(8); await RenderingServer.frame_post_draw
				var image := device.output.get_image()
				if material_texture.is_valid():
					check(device.output.get_rid() == material_texture,"resize preserves the texture RID bound by water materials")
				material_texture = device.output.get_rid()
				check(image != null and image.get_size() == size,"RT target dimensions "+str(size))
				var pixel := image.get_pixel(size.x/2,size.y/2)
				check(image.get_format() == Image.FORMAT_RGBAH,"HDR colour and alpha survive GPU readback")
				check(pixel.g > 0.99 and pixel.r < 0.01 if transparent else pixel.r > 0.99 and pixel.g < 0.01,
					"alpha-tested front triangle reveals green rear hit" if transparent else "closest textured triangle reads red")
				check(image.get_pixel(0,0).a < 0.01,"miss leaves reflected sky visible")
				image.save_png(out.path_join("device-%s-%dx%d.png"%[transparent,size.x,size.y]))
			# Raising the clipping plane beyond all geometry removes the hits.
			var clipped := frame.duplicate(); clipped[43] = 10.0
			RenderingServer.call_on_render_thread(device.render.bind(Vector2i(128,128),clipped.to_byte_array()))
			await frames(8); await RenderingServer.frame_post_draw
			check(device.output.get_image().get_pixel(64,64).a < 0.01,"underwater geometry is excluded by the reflection plane")
		RenderingServer.call_on_render_thread(device.dispose)
		await frames(8)
		# Godot 4.7 retains the last RD RID in the property's getter even after
		# detaching the RS texture. Its dimensions and our ownership are live.
		check(device.output.get_width() == 0 and device._owned.is_empty() and not device._target.is_valid(),"GPU output is detached after teardown")
	camera.queue_free(); await frames(4)
	finish()

func finish() -> void:
	FileAccess.open(out.path_join("device-results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown()
	print("WATER_RT_DEVICE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
