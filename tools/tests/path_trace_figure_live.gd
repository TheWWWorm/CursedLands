extends "path_trace_performance.gd"
func average(image: Image) -> float:
	var total:=0.0;var count:=0
	for y in range(170,600,2):
		for x in range(530,750,2):
			var c:=image.get_pixel(x,y);total+=(c.r+c.g+c.b)/3;count+=1
	return total/count
func run() -> void:
	var context:=await setup();var s: Session=context[0];var g: Game=context[1]
	Engine.max_fps=30
	var at:=Vector3(241,0,-197)
	# Keep the hero on authored terrain beside the river fixture.
	at=camera.global_position;at.y=t.height_at(at.x,-at.z)
	var u:=s.world.spawn_unit({"prototype":"Human Hero","position":Vector3(at.x,-at.z,0),"weapons":PackedStringArray()})
	u.set_meta("hero",{});u.refresh_figure(true);u.show();u.set_process(false);u.set_physics_process(false)
	u.model.act("idle",1,0);u.model.player.seek(.2,true)
	camera.global_position=u.global_position+Vector3(0,1.5,3.7);camera.look_at(u.global_position+Vector3.UP*.9);camera.fov=42
	GameData.options.merge({"gfx_water_reflections":0,"gfx_materials":1,"gfx_terrain":1,"character_light":0,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0},true)
	t.apply_gfx();Gfx.apply_env(g._env)
	var rt: Node=g.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"real scene prepares native PT")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	rt.set_process(false)
	for i in 20:rt._poll=99;rt._process(1.0/30);await frames(1)
	var before:=await capture("body-before-highlight")
	var marks:=OrderMarks.new();marks._lighten(u.model,true)
	for i in 20:rt._poll=99;rt._process(1.0/30);await frames(1)
	var lit:=await capture("body-highlighted")
	check(average(lit)<average(before)*1.5+.015,"highlight preserves traced shading without full albedo emission")
	marks._lighten(u.model,false)
	for effect in ["strength","weak",""]:
		u.buffs.erase("strength");u.buffs.erase("weak")
		if effect!="":u.buffs[effect]={"p":1.0,"left":60.0}
		u.refresh_figure()
		var rendered: int=rt.device.completed_renders
		rt._poll=99;rt._process(1.0/30);await frames(3)
		var found:=0;var missing:=0
		for entry: Dictionary in rt._scene.instances:
			var node: Node=entry.node.get_ref()
			if is_instance_valid(node) and u.model.is_ancestor_of(node):
				found+=1
				if node.is_visible_in_tree() and entry.mask==0:missing+=1
		check(found>12 and missing==0,"first spell frame retains all current actor parts: "+effect)
		check(rt.device.completed_renders>rendered and not rt._failed,"native pose upload renders successfully: "+effect)
		await shot("body-effect-"+(effect if effect!="" else "expired"))
	marks.free();g.queue_free();s.queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_FIGURE_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
