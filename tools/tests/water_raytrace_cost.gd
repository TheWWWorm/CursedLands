extends "res://tools/tests/water_raytrace_dynamic_performance.gd"
## Same original character/river on either pack, plus bounded CPU-only probes.
func run() -> void:
	var context := await setup()
	var start := Time.get_ticks_usec()
	GameData.options.gfx_water_reflections=3; t.apply_gfx()
	for i in 1200:
		await frames(1)
		if t._reflection._rt_ready and t._reflection.rt_stats.get("active",false): break
		if t._reflection._rt_failed: break
	check(t._reflection._rt_ready,"hardware scene prepares")
	if not t._reflection._rt_ready: get_tree().quit(1); return
	var prepare := (Time.get_ticks_usec()-start)/1000.0
	await frames(15); await shot("water.png")
	t._reflection._rt.output.get_image().save_png(out.path_join("reflection.png"))
	t._reflection.set_process(false); set_process(false); await frames(3)
	var device: Object=t._reflection._rt
	var built := 0
	for blas: RID in device._blases: if blas.is_valid(): built += 1
	t._reflection.rt_stats["built_blas"]=built
	if "_active_instances" in device: t._reflection.rt_stats["active_instances"]=device._active_instances.size()
	var scene: Object=t._reflection._rt_live
	var cpu := {}
	for moving in [false,true]:
		var times := []; var changed := []
		for i in 160:
			if moving:
				hero.pos=start_position+Vector2(sin(i*0.13)*0.5,0); hero.resync_drawn()
				var clip := hero.model.player.get_animation("ei/"+hero.model._current)
				hero.model.player.seek(fmod(i*0.02,clip.length),true); hero.model.flush_pending_pose()
			var begin := Time.get_ticks_usec()
			var updates: Dictionary=scene.updates()
			var elapsed := (Time.get_ticks_usec()-begin)/1000.0
			if i>=10: times.append(elapsed); changed.append(updates.instances.size())
		cpu["moving" if moving else "static"]={"ms":summary(times),"changed_instances":summary(changed)}
	# The probe advances CPU caches without dispatching GPU work; immediately
	# dispose the scene instead of resuming a mismatched cached pose.
	FileAccess.open(out.path_join("cost.json"),FileAccess.WRITE).store_string(JSON.stringify({"prepare_ms":prepare,"updates":cpu,"scene":t._reflection.rt_stats},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown(); get_tree().quit()
