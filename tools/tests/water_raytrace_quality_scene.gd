extends "res://tools/tests/water_raytrace_artifact.gd"
## Same camera and scene: compare the old half-resolution/single-sample budget
## recreated on DX12 with the new native-resolution/four-sample path and Mirror.
signal dispatched

func set_quality(device: RefCounted, size: Vector2i, grid: int, footprint: float) -> void:
	var frame: PackedByteArray = device._rd.buffer_get_data(device._frame)
	frame.encode_float(35*4,grid)
	frame.encode_float(51*4,footprint/size.y)
	device.render(size,frame)
	dispatched.emit.call_deferred()

func run() -> void:
	var context := await setup()
	await frames(10); await shot("mirror")
	GameData.options.gfx_water_reflections=3; t.apply_gfx()
	for i in 1200:
		await frames(1)
		if t._reflection._rt_ready or t._reflection._rt_failed: break
	check(t._reflection._rt_ready,"RT prepares for the same-camera quality comparison")
	if t._reflection._rt_ready:
		await frames(10)
		t._reflection.set_process(false)
		var footprint := 2.0/absf(t._reflection.camera.get_camera_projection().y.y)
		for grid in [1,2]:
			RenderingServer.call_on_render_thread(set_quality.bind(t._reflection._rt,Vector2i(640,360) if grid == 1 else Vector2i(1280,720),grid,footprint))
			await dispatched; await frames(10)
			var label := "old-budget-half-1spp" if grid == 1 else "new-native-4spp"
			await shot(label)
			t._reflection._rt.output.get_image().save_png(out.path_join(label+"-reflection.png"))
	FileAccess.open(out.path_join("quality-scene.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"note":"Old budget recreated with the shared shader; this is not an old DX12 RT release. Frozen camera, no FG."},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
