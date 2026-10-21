extends "res://tools/tests/water_raytrace_live.gd"
## Preserve main's full first-person figure in the hardware reflection.
func refresh() -> bool:
	t._reflection._rt_topology_poll=0.0; await frames(2)
	return await ready_rt()

func run() -> void:
	var context := await setup()
	var hero: GameUnit
	for unit: GameUnit in context[0].world.units.values():
		if unit.has_meta("hero") and unit.model != null: hero=unit; break
	check(hero!=null,"real campaign character is available")
	if hero==null: get_tree().quit(1); return
	var view: Camera3D=t._reflection.camera
	var pixel := view.get_viewport().get_visible_rect().size*0.5
	var location := view.project_ray_origin(pixel)+view.project_ray_normal(pixel)*13.0
	hero.pos=Vector2(location.x,-location.z)
	hero.placement_z=maxf(0.05,t._reflection.plane+1.0-context[0].world.ground_at(hero.pos.x,hero.pos.y))
	hero.show(); hero.resync_drawn(); hero.set_process(false); hero.set_physics_process(false)
	hero.model.act("walk",1,0.0); hero.model.player.pause()
	hero.model.player.seek(0.25,true); hero.model.flush_pending_pose()
	GameData.options.gfx_water_reflections=3; t.apply_gfx()
	check(await ready_rt(),"hardware reflection prepares the complete character")
	if not t._reflection._rt_ready: get_tree().quit(1); return
	var before := await reflected("normal-figure")
	hero.model.set_first_person_view(true)
	hero.model.align_first_person_body(hero.global_position+Vector3(0.2,1.7,0.1),Vector3.RIGHT)
	hero.model._update_first_person_shadows()
	check(await refresh(),"first-person copies enter the hardware snapshot")
	var first := await reflected("first-person-figure")
	check(difference(before,first)<20,"RT first-person figure matches the complete authored figure")
	var owner: Object=t._reflection._rt_live
	var close_count := 0; var complete_count := 0; var wrong := 0
	for index: int in owner._groups[hero.get_instance_id()].indices:
		var entry: Dictionary=owner.instances[index]; var node: MeshInstance3D=entry.node.get_ref()
		if node.layers==EIUnitModel.CLOSE_VIEW_LAYER:
			close_count+=1
			if entry.mask!=0: wrong+=1
		elif node.layers==EIUnitModel.REFLECTION_LAYER and node.is_visible_in_tree():
			complete_count+=1
			if entry.mask!=1: wrong+=1
	check(close_count>0 and complete_count>0 and wrong==0,"close-view torso is masked and complete reflection copies remain visible")
	check(not hero.model._head.is_visible_in_tree(),"main first-person camera still hides the original head")
	hero.hide(); var hidden := await reflected("first-person-hidden")
	check(difference(first,hidden)>50,"hidden first-person character leaves no reflected copies")
	hero.show(); hero.model.set_first_person_view(false)
	check(await refresh(),"leaving first person refreshes the changed torso")
	check(difference(before,await reflected("normal-restored"))<20,"leaving first person restores the same reflection")
	FileAccess.open(out.path_join("first-person.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"close_parts":close_count,"reflection_parts":complete_count,"changed_pixels":difference(before,first)},"\t"))
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
