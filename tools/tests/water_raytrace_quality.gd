extends "res://tools/tests/water_raytrace_device.gd"
## Compare actual single/four-sample GPU pixels with a 64-sample reference.
## Cover geometry and alpha-tested edges, colour coverage, and camera changes.
const Reflection = preload("res://src/game/fx/water_reflection.gd")
var measurements := []

func capture(device: Device, frame: PackedFloat32Array, grid: int) -> Image:
	var sample := frame.duplicate(); sample[35] = grid
	RenderingServer.call_on_render_thread(device.render.bind(Vector2i(128,128),sample.to_byte_array()))
	await frames(6); await RenderingServer.frame_post_draw
	return device.output.get_image()

func error(image: Image, reference: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width(): total += absf(image.get_pixel(x,y).a-reference.get_pixel(x,y).a)
	return total / (image.get_width()*image.get_height())

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"hardware RT is available for quality readbacks")
	if not Device.supported(): finish(); return
	check(Reflection.raytrace_target_size(Vector2(1280,720)) == Vector2i(1280,720),"720p reflections retain native pixels")
	check(Reflection.raytrace_target_size(Vector2(1920,1080)) == Vector2i(1920,1080),"1080p reflections retain native pixels")
	check(Reflection.raytrace_target_size(Vector2(3840,2160)) == Vector2i(1920,1080),"4K reflection cost is bounded with aspect preserved")
	check(Reflection.raytrace_target_size(Vector2(1080,1920)) == Vector2i(1080,1920),"portrait reflection aspect is preserved")
	var camera := Camera3D.new(); add_child(camera)
	camera.position = Vector3(0,-1,3); camera.look_at(Vector3(0,1.5,0)); camera.current = true
	var data := PackedFloat32Array()
	var points := [Vector3(-3,0.4,0),Vector3(3,0.4,0),Vector3(-0.6,5,0)]
	var uvs := [Vector2(0,0),Vector2(1,0),Vector2(0.35,1)]
	for i in 3:
		var p: Vector3 = points[i]; var uv: Vector2 = uvs[i]
		data.append_array(PackedFloat32Array([p.x,p.y,p.z,uv.x,0,0,1,uv.y,1,1,1,1,0,0,0,0]))
	for cutout in [false,true]:
		var texture := Image.create(64,64,false,Image.FORMAT_RGBA8); texture.fill(Color.RED)
		if cutout:
			for y in 64:
				for x in 64:
					if x < y*0.65+8 or (x+y*3)%19 < 3: texture.set_pixel(x,y,Color(1,0,0,0))
		var device := Device.new(); var images: Array[Image] = [texture]
		RenderingServer.call_on_render_thread(device.build.bind(data.to_byte_array(),images))
		var ok: bool = await device.prepared; check(ok,"quality scene builds, cutout="+str(cutout))
		if ok:
			for offset in [0.0,0.027]:
				camera.position.x = offset
				var frame := PackedFloat32Array()
				for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
					for axis in 4:
						var v: Vector4 = matrix[axis]; frame.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
				frame.resize(88)
				for i in [32,33,34]: frame[i] = 1.0
				frame[44]=90; frame[45]=100; frame[46]=100
				var single := await capture(device,frame,1)
				var aa := await capture(device,frame,Reflection.RT_SAMPLE_GRID)
				var reference := await capture(device,frame,8)
				var e1 := error(single,reference); var e4 := error(aa,reference)
				check(e1 > 0.0001 and e4 < e1*0.6,"four samples reduce edge coverage error by at least 40%")
				var fractional := 0; var opaque := 0; var premult_error := 0.0
				for y in 128:
					for x in 128:
						var p := aa.get_pixel(x,y)
						if p.a > 0.01 and p.a < 0.99: fractional += 1
						if p.r > 0.99 and p.a > 0.99: opaque += 1
						premult_error = maxf(premult_error,absf(p.r-p.a))
				check(fractional > 20,"diagonal silhouettes have fractional pixel coverage")
				check(opaque > 100,"opaque reflected details remain sharp and fully coloured")
				check(premult_error < 0.002,"edge RGB is premultiplied by coverage for halo-free water filtering")
				var repeat := await capture(device,frame,Reflection.RT_SAMPLE_GRID)
				check(repeat.get_data() == aa.get_data(),"stable samples have no temporal noise or stale camera history")
				var name := "cutout-%s-offset-%s"%[cutout,offset]
				single.save_png(out.path_join(name+"-1spp.png")); aa.save_png(out.path_join(name+"-4spp.png"))
				reference.save_png(out.path_join(name+"-64spp.png"))
				measurements.append({"case":name,"single_error":e1,"four_sample_error":e4,"fractional_pixels":fractional})
		RenderingServer.call_on_render_thread(device.dispose); await frames(6)
		check(device._owned.is_empty(),"quality scene releases GPU resources")
	camera.queue_free(); await frames(4)
	FileAccess.open(out.path_join("quality-results.json"),FileAccess.WRITE).store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"measurements":measurements},"\t"))
	finish()
