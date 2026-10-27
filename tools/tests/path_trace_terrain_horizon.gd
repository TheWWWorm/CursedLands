extends "res://tools/tests/path_trace_terrain.gd"
## Upward authored lighting normals may cross a steep face's tangent plane.
## Adjacent facets must not turn a continuous lighting field upside down.
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(), "native path tracing is available")
	if not PathDevice.supported(): finish(); return
	camera = Camera3D.new(); add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4
	camera.position = Vector3(0,0,72); camera.current = true
	size = fixture_size; bounces = 1; sky_energy = 0; sun_energy = 1
	sun_direction = Vector3(0,1,0.1).normalized()
	for style in [0,3]:
		mode = style
		var previous := Vector3.ZERO
		var brightness := []
		for crossing in [0.04,0.01,-0.01,-0.04]:
			authored_normal = Vector3(0,1,crossing).normalized()
			check(await build_land(), "build authored terrain normal " + str(crossing))
			await render_many(8)
			var sample := mean(device.guide)
			var n := Vector3(sample.r,sample.g,sample.b)
			check(n.y > 0.9 and n.z > 0 and n.is_finite(), "steep face retains upward light instead of a dark inverted triangle")
			if previous != Vector3.ZERO: check(n.dot(previous)>0.98, "lighting stays continuous across adjacent facet orientations")
			previous = n
			brightness.append(mean(device.output).r)
			device.output.get_image().save_png(out.path_join("terrain-horizon-%d-%s.png" % [mode,crossing]))
		check(float(brightness.min()) > float(brightness.max()) * 0.9, "sunlit neighbouring terrain does not become a black wedge")
	RenderingServer.call_on_render_thread(device.dispose); await frames(8)
	camera.queue_free(); await frames()
	print("TERRAIN_HORIZON ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
