extends "res://tools/tests/water_raytrace_device.gd"
## GPU texture filtering: retain resolvable stripes along the short footprint
## axis while minifying single-texel stripes along its long axis. Compare two
## triangulations of the same affine UV field, including nonuniform instances.
var rows := []
var baseline := false
const SIZE := Vector2i(128,128)

func pattern() -> Image:
	var im := Image.create(512,512,false,Image.FORMAT_RGBA8)
	for y in 512:
		for x in 512: im.set_pixel(x,y,Color(0.95 if (x/32)%2 == 0 else 0.15,float(y%2),0,1))
	im.generate_mipmaps()
	return im

func quad(flip: bool) -> PackedFloat32Array:
	var corners := [Vector3(-4,0.1,0),Vector3(4,0.1,0),Vector3(4,8,0),Vector3(-4,8,0)]
	var data := PackedFloat32Array()
	for index in ([0,1,3,1,2,3] if flip else [0,1,2,0,2,3]):
		var p: Vector3 = corners[index]
		data.append_array(PackedFloat32Array([p.x,p.y,p.z,p.x*0.18,0,0,1,p.y*4.0,1,1,1,1,0,0,0,0]))
	return data

func capture(device: Device, frame: PackedFloat32Array, filtering := 4) -> Image:
	if baseline: RenderingServer.call_on_render_thread(device.render.bind(SIZE,frame.to_byte_array()))
	else: RenderingServer.call_on_render_thread(device.render.bind(SIZE,frame.to_byte_array(),{},filtering))
	await frames(5); await RenderingServer.frame_post_draw
	return device.output.get_image()

func stats(im: Image) -> Dictionary:
	var lo := 1.0; var hi := 0.0; var error := 0.0; var count := 0
	var green := Color(0,128.0/255.0,0).srgb_to_linear().g
	for y in range(40,88):
		for x in range(40,88):
			var p := im.get_pixel(x,y)
			if p.a < 0.99: continue
			lo = minf(lo,p.r); hi = maxf(hi,p.r)
			error += absf(p.g-green); count += 1
	return {"contrast":hi-lo,"green_error":error/maxi(count,1),"pixels":count}

func difference(a: Image, b: Image) -> float:
	var total := 0.0
	for y in range(40,88):
		for x in range(40,88):
			var p := a.get_pixel(x,y); var q := b.get_pixel(x,y)
			total += absf(p.r-q.r)+absf(p.g-q.g)+absf(p.a-q.a)
	return total/(48.0*48.0*3.0)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	baseline = OS.get_cmdline_user_args().has("--baseline-filtering")
	DirAccess.make_dir_recursive_absolute(out)
	check(Device.supported(),"hardware RT is available for filtering readbacks")
	if not Device.supported(): finish(); return
	var camera := Camera3D.new(); add_child(camera); camera.current = true
	camera.position = Vector3(0,-1,3); camera.look_at(Vector3(0,2.5,0)); camera.size = 6.0
	var images: Array[Image] = [pattern()]
	for projection in [Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_ORTHOGONAL]:
		camera.projection = projection
		for scale in [Vector3.ONE,Vector3(1.3,0.7,1.0)]:
			var pair: Array[Image] = []
			var label := "%s-%s"%[projection,scale]
			for flip in [false,true]:
				var frame := PackedFloat32Array()
				for matrix: Projection in [camera.get_camera_projection().inverse(),Projection(camera.global_transform)]:
					for axis in 4:
						for component in 4: frame.append(matrix[axis][component])
				frame.resize(88); frame[32]=1; frame[33]=1; frame[34]=1; frame[35]=2
				frame[44]=90; frame[45]=100; frame[46]=100; frame[47]=float(projection == Camera3D.PROJECTION_ORTHOGONAL)
				frame[51]=2.0/absf(camera.get_camera_projection().y.y)/SIZE.y
				var device := Device.new()
				RenderingServer.call_on_render_thread(device.build.bind(quad(flip).to_byte_array(),images,
					[{"offset":0,"count":6,"opaque":true}],
					[{"geometry":0,"transform":Transform3D(Basis.from_scale(scale),Vector3.ZERO)}]))
				var ok: bool = await device.prepared; check(ok,label+": textured quad prepares")
				if ok:
					var anisotropic := await capture(device,frame)
					pair.append(anisotropic)
					var a := stats(anisotropic)
					check(a.pixels > 1800,label+": comparison region contains the textured surface")
					check(a.contrast > 0.5,label+": resolvable texture stripes retain contrast")
					check(a.green_error < 0.02,label+": subpixel stripes are filtered instead of shimmering")
					anisotropic.save_png(out.path_join("filter-%s-%s.png"%[label,flip]))
					if not baseline:
						var texture := device.output.texture_rd_rid; var bound := device.output.get_rid(); var allocations := device._owned.size()
						var off := stats(await capture(device,frame,0))
						check(a.contrast > off.contrast+0.2,label+": Texture filtering Off and 16x produce distinct expected detail")
						for quality in [1,2,3,4]: await capture(device,frame,quality)
						var restored := await capture(device,frame,4)
						check(restored.get_data() == anisotropic.get_data(),label+": changing filtering back restores deterministic pixels")
						check(device.output.texture_rd_rid == texture and device.output.get_rid() == bound and device._owned.size() == allocations,label+": filtering changes reuse the target and scene resources")
					rows.append({"case":label,"flipped_diagonal":flip,"stats":a})
				RenderingServer.call_on_render_thread(device.dispose); await frames(4)
				check(device._owned.is_empty(),label+": all filtering and scene resources released")
			if pair.size() == 2:
				var error := difference(pair[0],pair[1])
				check(error < 0.004,label+": equivalent triangle diagonals do not create texture seams")
				rows.append({"case":label,"triangulation_error":error})
	camera.queue_free(); await frames(3)
	FileAccess.open(out.path_join("filtering.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"baseline":baseline,"rows":rows},"\t"))
	finish()
