extends "res://tools/tests/path_trace_sharc_live.gd"
## Real campaign geometry/materials, the saved setting's controller path,
## mode transitions, and a streamed replacement with directional history.
func select_denoiser(rt: Node,directional: bool) -> bool:
	GameData.options.pt_denoiser=int(directional)
	for i in 900:
		await frames(1)
		if rt._failed:return false
		if rt.device!=null and rt.device.output_ready() and rt.device.nrd_active \
			and rt.device.nrd.directional==directional and rt.stats.get("nrd_directional",false)==directional \
			and not rt.stats.get("rebuilding",false) and not ShaderCompilationScreen.active():return true
	return false

func run() -> void:
	var context:=await setup_sharc()
	if context.is_empty():get_tree().quit(1);return
	GameData.options.pt_denoiser=0
	var rt: Node=context[1].get_node("SceneRaytrace")
	check(await ready_scene(rt),"real campaign prepares radiance PT")
	if rt.device==null:await finish_directional(context,rt);return
	check(await select_denoiser(rt,false),"production controller selects radiance NRD")
	await frames(24)
	await capture("nrd-radiance-world")
	var previous: Object=rt.device
	check(await select_denoiser(rt,true),"production option activates actual SH denoising")
	check(rt.device==previous,"changing denoising keeps scene acceleration structures")
	await frames(24)
	await capture("nrd-directional-world")
	# Read the lighting buffer itself: snowfall, HUD counters and different
	# animation times must not make a broken lighting comparison pass.
	var lighting: Image=rt.device.output.get_image()
	var finite:=true;var lit:=0
	for y in lighting.get_height():
		for x in lighting.get_width():
			var c:=lighting.get_pixel(x,y)
			finite=finite and is_finite(c.r) and is_finite(c.g) and is_finite(c.b) \
				and minf(c.r,minf(c.g,c.b))>=0 and maxf(c.r,maxf(c.g,c.b))<=60000
			if c.r+c.g+c.b>0.001:lit+=1
	check(finite and lit>lighting.get_width()*lighting.get_height()/20,"actual campaign SG lighting is finite, nonnegative and nonblank")
	check(not rt.device._nrd_failed and rt.device.nrd._description.directional,"campaign runs the SH planner without fallback")
	var generation: int=rt.stats.get("snapshot_generation",0)
	camera.global_position+=Vector3(20,0,0)
	check(await ready_scene(rt),"directional PT completes a streamed scene replacement")
	await frames(24)
	check(rt.stats.get("snapshot_generation",0)>generation and rt.device.nrd_active and rt.device.nrd.directional,"replacement retains the requested SH mode")
	await capture("nrd-directional-recenter")
	GameData.options.pt_accumulation=1;await frames(24)
	check(not rt.device.nrd_active and rt.device.output_ready(),"Still scene bypasses directional filtering")
	GameData.options.pt_accumulation=0
	check(await select_denoiser(rt,true),"returning to Responsive restores directional NRD")
	check(await select_denoiser(rt,false),"live radiance selection restores the existing denoiser")
	await finish_directional(context,rt)

func finish_directional(context: Array,rt: Node) -> void:
	FileAccess.open(out.path_join("nrd-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("NRD_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
