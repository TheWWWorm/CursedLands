extends "res://tools/tests/water_raytrace_artifact.gd"
## A real campaign character moves, animates and disappears in the hardware
## reflection without reconstructing its geometry or leaking hidden units.
func difference(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			var u := a.get_pixel(x,y); var v := b.get_pixel(x,y)
			if absf(u.r-v.r)+absf(u.g-v.g)+absf(u.b-v.b)+absf(u.a-v.a) > 0.08: count += 1
	return count

func reflected(name: String) -> Image:
	await frames(6); await RenderingServer.frame_post_draw
	var im: Image = t._reflection._rt.output.get_image()
	# The PNG exporter may convert its input to 8-bit RGB; preserve HDR/alpha
	# readback for the assertions and export a separate image.
	im.duplicate().save_png(out.path_join(name+".png")); return im

func ready_rt() -> bool:
	for i in 1200:
		if (t._reflection._rt_ready and t._reflection.rt_stats.get("active",false)) or t._reflection._rt_failed: break
		await frames(1)
	return t._reflection._rt_ready and t._reflection.rt_stats.get("active",false)

func run() -> void:
	var context := await setup()
	var hero: GameUnit
	for unit: GameUnit in context[0].world.units.values():
		if unit.has_meta("hero") and unit.model != null: hero = unit; break
	check(hero != null,"campaign supplies a real articulated character")
	if hero == null: get_tree().quit(1); return
	var reflected_camera: Camera3D = t._reflection.camera
	var pixel := reflected_camera.get_viewport().get_visible_rect().size*0.5
	var location := reflected_camera.project_ray_origin(pixel)+reflected_camera.project_ray_normal(pixel)*13.0
	hero.pos = Vector2(location.x,-location.z)
	hero.placement_z = maxf(0.05,t._reflection.plane+1.0-context[0].world.ground_at(hero.pos.x,hero.pos.y))
	hero.show(); hero.resync_drawn(); hero.set_process(false); hero.set_physics_process(false)
	hero.model.act("walk",1,0.0); hero.model.player.pause()
	hero.model.player.seek(0.1,true); hero.model.flush_pending_pose()
	GameData.options.gfx_water_reflections = 3; t.apply_gfx(); await frames(4)
	check(await ready_rt(),"live scene prepares hardware RT")
	if not t._reflection._rt_ready: get_tree().quit(1); return
	var owner: Object = t._reflection._rt_live
	var group: Dictionary = owner._groups.get(hero.get_instance_id(),{})
	print("LIVE_CHARACTER ",hero.global_position," plane ",t._reflection.plane," camera ",t._reflection.camera.global_transform," group ",group.get("indices",[]).size()," hidden ",hero.is_invisible())
	var active := await reflected("character-visible")
	await shot("water-character-visible")
	hero.hide(); var hidden := await reflected("character-hidden")
	check(difference(active,hidden)>50,"hiding the real character removes reflected geometry and its shadows")
	hero.show(); var restored := await reflected("character-restored")
	check(difference(hidden,restored)>50,"revealing the character restores its reflection")
	check(difference(active,restored)<20,"visibility changes preserve the rest of the reflection")
	hero.buffs["water_rt_audit"]={"detect":[0,-1000.0]}
	var invisible := await reflected("character-invisible")
	check(hero.visible and hero.is_invisible() and difference(invisible,hidden)<20,"invisible creatures cannot leak geometry through water reflections")
	hero.buffs.erase("water_rt_audit"); await frames(6)
	var start_position := hero.pos
	hero.pos += Vector2(reflected_camera.global_basis.x.x,-reflected_camera.global_basis.x.z)*1.5
	hero.resync_drawn()
	var moved := await reflected("character-moved")
	check(difference(restored,moved)>50,"root movement changes the reflected character")
	hero.pos = start_position; hero.resync_drawn()
	var pose_before := await reflected("character-before-pose")
	var before_transforms := []
	for index: int in group.indices: before_transforms.append(owner.instances[index].node.get_ref().global_transform)
	hero.model.player.seek(0.45,true); hero.model.flush_pending_pose()
	var animated := await reflected("character-animated")
	var changed_parts := 0
	for i in group.indices.size():
		if before_transforms[i] != owner.instances[group.indices[i]].node.get_ref().global_transform: changed_parts += 1
	print("LIVE_DIFFERENCES visibility ",difference(active,hidden)," move ",difference(restored,moved)," animation ",difference(pose_before,animated)," changed parts ",changed_parts)
	check(changed_parts>0,"the original animation clip changes articulated mesh transforms")
	check(difference(pose_before,animated)>10,"articulated pose changes reach the hardware reflection")
	check(t._reflection._rt_live == owner,"movement, animation and visibility reuse the same geometry snapshot")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 28.0
	camera.global_position = hero.global_position+Vector3(8,18,16); camera.look_at(hero.global_position)
	t.set_process(true); await frames(8); t.set_process(false)
	var ortho_ready := await ready_rt()
	if not ortho_ready:
		push_error("Orthographic RT failed to prepare"); get_tree().quit(1); return
	check(t._reflection._rt_ready and t._reflection.rt_stats.get("active",false),"orthographic game camera keeps hardware RT active")
	var orthographic := await reflected("orthographic-reflection"); await shot("orthographic-water")
	var hits := 0
	for y in range(0,orthographic.get_height(),4):
		for x in range(0,orthographic.get_width(),4):
			if orthographic.get_pixel(x,y).a > 0.1: hits += 1
	check(hits>100,"orthographic rays return real scenery")
	# New or replaced meshes require a new snapshot; removal is masked at
	# once and does not leave a stale character in the old acceleration data.
	var mesh: MeshInstance3D = hero.model.find_children("*","MeshInstance3D",true,false)[0]
	var saved := mesh.mesh; mesh.mesh = saved.duplicate()
	check(t._reflection._rt_live.topology_changed(),"replacing equipment geometry is detected")
	var previous: Object = t._reflection._rt_live
	var previous_output: Texture2D = t._reflection._rt.output
	t._reflection._rt_topology_poll = 0.0; await frames(2)
	check(t._water_mat.get_shader_parameter("planar_texture") == previous_output,"changed equipment keeps the complete reflection while rebuilding")
	for i in 1200:
		if t._reflection._rt_live != previous or t._reflection._rt_failed:break
		await frames(1)
	check(await ready_rt() and t._reflection._rt_live != previous,"changed equipment automatically rebuilds the hardware scene")
	mesh.mesh = saved
	FileAccess.open(out.path_join("live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":t._reflection.rt_stats,"visibility_pixels":difference(active,hidden),"movement_pixels":difference(restored,moved),"animation_pixels":difference(pose_before,animated),"animated_parts":changed_parts},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	print("WATER_RT_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
