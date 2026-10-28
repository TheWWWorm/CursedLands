extends "path_trace_performance.gd"
## Per-frame PT scene updates reuse their figure and first-person scans until a
## figure is replaced or changes view mode. Replacement still rebinds every
## part at once. A preparation cover lets snapshot gathering use more of the frame.
func actor_parts(rt: Node,u: GameUnit) -> Array[int]:
	var found:=0;var missing:=0
	for entry: Dictionary in rt._scene.instances:
		var node: Node=entry.node.get_ref()
		if is_instance_valid(node) and u.model.is_ancestor_of(node):
			found+=1
			if node.is_visible_in_tree() and entry.mask==0:missing+=1
	return [found,missing]

func step(rt: Node,count: int) -> void:
	for i in count:rt._poll=99;rt._process(1.0/30);await frames(1)

func run() -> void:
	var context:=await setup();var s: Session=context[0];var g: Game=context[1]
	Engine.max_fps=30
	var at:=camera.global_position;at.y=t.height_at(at.x,-at.z)
	var u:=s.world.spawn_unit({"prototype":"Human Hero","position":Vector3(at.x,-at.z,0),"weapons":PackedStringArray()})
	u.set_meta("hero",{});u.refresh_figure(true);u.show();u.set_process(false);u.set_physics_process(false)
	camera.global_position=u.global_position+Vector3(0,1.5,3.7);camera.look_at(u.global_position+Vector3.UP*.9);camera.fov=42
	GameData.options.merge({"gfx_water_reflections":0,"gfx_materials":1,"gfx_terrain":1,"character_light":0,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0},true)
	t.apply_gfx();Gfx.apply_env(g._env)
	var rt: Node=g.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"real scene prepares native PT")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	rt.set_process(false)
	await step(rt,4)
	var scene: RefCounted=rt._scene
	var scans: int=scene.model_scans
	await step(rt,60)
	check(rt._scene==scene and scene.model_scans==scans,"60 unchanged frames perform no figure replacement scan")
	var before:=actor_parts(rt,u)
	check(before[0]>12 and before[1]==0,"traced actor parts are bound before replacement")
	var old_model:=u.model
	u.buffs["strength"]={"p":1.0,"left":60.0};u.refresh_figure()
	check(u.model!=old_model,"body spell replaces the figure")
	var rendered: int=rt.device.completed_renders
	await step(rt,1)
	var after:=actor_parts(rt,u)
	check(rt._scene==scene and scene.model_scans==scans+1,"one figure replacement causes exactly one scan")
	check(after[0]==before[0] and after[1]==0,"replacement rebinds every traced part on its first frame")
	await step(rt,2)
	check(rt.device.completed_renders>rendered and not rt._failed,"native pose upload renders after replacement")
	await step(rt,30)
	check(scene.model_scans==scans+1,"no further scans while figures stay unchanged")
	# First-person presentation follows the cached view list.
	u.model.set_first_person_view(true)
	await step(rt,1)
	var presented: Array=scene._presented_views.filter(func(group: Dictionary):return group.model.get_ref()==u.model)
	check(presented.size()==1,"first-person figure enters the presented list")
	u.model.set_first_person_view(false)
	await step(rt,1)
	check(scene._presented_views.is_empty(),"leaving first-person view clears the presented list")
	# Snapshot gathering budgets.
	check(rt.gather_budget_us()==rt.GATHER_LIVE_US,"live replacement gathers within the shared-frame budget")
	rt._travel_gather_budget=6000
	check(rt.gather_budget_us()==6000,"live travel retains its larger bounded gathering budget")
	rt._travel_gather_budget=rt.GATHER_LIVE_US
	rt._release()
	check(rt.device==null and rt.gather_budget_us()==rt.GATHER_LOADING_US,"uncovered loading keeps the responsive budget")
	rt._preparation_owner=&"test-cover"
	check(rt.gather_budget_us()==rt.GATHER_COVERED_US and rt.GATHER_COVERED_US>rt.GATHER_LOADING_US,"a preparation cover enables the larger gathering budget")
	rt._preparation_owner=&""
	rt.set_process(true)
	check(await ready_snapshot(rt),"PT is prepared again after release")
	FileAccess.open(out.path_join("path-cpu-caches.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"model_scans":scene.model_scans,"parts":after,"stats":rt.stats.duplicate(true)},"\t"))
	g.queue_free();s.queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_CPU_CACHES ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
