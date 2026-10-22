extends "res://tools/tests/scene_raytrace_live.gd"
## Real cave, live lamp and articulated actor; no outdoor ambient substitute.
func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	session._enter_zone("gz5g",1,false);t=session.world.terrain
	session.set_physics_process(false);session.world.set_process(false);session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	game.set_process(false);game._update_daylight(false);game.rig.set_process(false);game.direct.set_process(false)
	var hero: GameUnit=session.party_units(0)[0]
	for unit: GameUnit in session.world.units.values():
		unit.set_process(false);unit.set_physics_process(false)
		if unit!=hero:unit.hide()
	hero.show();hero.resync_drawn();hero.model.player.pause()
	var focus:=hero.global_position+Vector3.UP
	camera.global_position=focus+Vector3(6,6,7);camera.look_at(focus);camera.current=true
	var lamp:=OmniLight3D.new();lamp.light_color=Color(1,0.05,0.02);lamp.light_energy=3.0;lamp.omni_range=12
	lamp.add_to_group(Gfx.POINT_LIGHT_GROUP);game.add_child(lamp);lamp.global_position=focus+Vector3(-1,1,1)
	GameData.options.gfx_water_reflections=0;t.apply_gfx()
	await get_tree().create_timer(0.3,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720);await frames(20)
	var rt: Node=game.get_node("SceneRaytrace")
	check(game._sky_cave,"fixture uses the actual cave lighting configuration")
	var original:=await capture("cave-conventional")
	GameData.options.pt_mode=1;GameData.options.pt_accumulation=1;GameData.options.q_rt_lighting=1
	Gfx.apply_env(game._env)
	check(await ready_scene(rt),"cave prepares multi-bounce path tracing")
	if rt.stats.get("active",false):
		var data: PackedByteArray=rt._frame(camera,Vector2i(960,540),1)
		check(data.decode_float(72*4)==0.0 and data.decode_float(73*4)==0.0 and data.decode_float(74*4)==0.0,"cave paths do not import outdoor sky radiance")
		await frames(100)
		var two:=await capture("cave-path-2-still")
		check(mean_difference(original,two)>0.002,"path lighting reaches the actual cave materials")
		GameData.options.pt_mode=2;await frames(100)
		var four:=await capture("cave-path-4-still")
		check(mean_difference(two,four)>0.0001,"additional bounces affect the cave image")
		check(rt.stats.accumulation_frames>=90,"stationary cave accumulates across frames")
		var red: Image=rt.device.output.get_image()
		lamp.light_color=Color(0.02,0.05,1);await frames(2)
		check(rt.stats.accumulation_frames<=3,"light colour change invalidates progressive history")
		await frames(100)
		var blue: Image=rt.device.output.get_image();await shot("cave-path-blue")
		var difference:=0.0
		for y in range(0,red.get_height(),4):
			for x in range(0,red.get_width(),4):
				var a:=red.get_pixel(x,y);var b:=blue.get_pixel(x,y)
				difference+=absf(a.r-b.r)+absf(a.b-b.b)
		check(difference>1.0,"local-light colour propagates through path illumination: "+str(difference))
		var scene: Object=rt._scene;var before:=[]
		for index: int in scene._groups[hero.get_instance_id()].indices:before.append(scene.instances[index].transform)
		hero.model.act("walk",1,0);hero.model.player.pause();hero.model.player.seek(0.3,true);hero.model.flush_pending_pose()
		hero.pos+=Vector2(0.5,0.2);hero.resync_drawn();await frames(3)
		var after:=[]
		for index: int in scene._groups[hero.get_instance_id()].indices:after.append(scene.instances[index].transform)
		check(before!=after and rt._scene==scene,"moving creature updates without rebuilding cave geometry")
		check(rt.stats.accumulation_frames<=4,"moving creature invalidates progressive history")
		GameData.options.gfx_ssao=1;GameData.options.gfx_contact_shadows=1;Gfx.apply_env(game._env)
		check(not game._env.ssao_enabled and Gfx.scene_rt_gi_active,"path lighting avoids double ambient occlusion")
		GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(8)
		check(game._env.ssao_enabled and not Gfx.scene_rt_gi_active and GameData.option("gfx_ssao")==1 \
			and GameData.option("gfx_contact_shadows")==1,"disabling path lighting restores saved ambient effects")
	FileAccess.open(out.path_join("path-cave.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_TRACE_CAVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
