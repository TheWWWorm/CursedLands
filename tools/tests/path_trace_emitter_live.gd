extends "res://tools/tests/scene_raytrace_live.gd"
## Exercise the production gatherer, controller and world receivers with a
## temporary glowing mesh attached to a real campaign object.
func red_mean(image: Image) -> float:
	var total:=0.0;var count:=0
	for y in range(0,image.get_height(),3):
		for x in range(0,image.get_width(),3):
			total+=image.get_pixel(x,y).r;count+=1
	return total/count

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.gfx_water_reflections=0;t.apply_gfx()
	var host: Node3D=session.world.objects[4442]
	var glow:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.3,0.3,0.3);glow.mesh=box
	var material:=StandardMaterial3D.new();material.emission_enabled=true;material.emission=Color(1,0.03,0.01);material.emission_energy_multiplier=20
	glow.material_override=material;host.add_child(glow)
	var focus:=host.global_position+Vector3(2,0,1);focus.y=t.height_at(focus.x,-focus.z)
	glow.global_position=focus+Vector3.UP*1.3;glow.hide()
	camera.global_position=focus+Vector3(4,3,6);camera.look_at(focus+Vector3.UP*0.5)
	GameData.options.pt_mode=2 if OS.get_cmdline_user_args().has("--pt-deep") else 1;GameData.options.pt_accumulation=0;GameData.options.q_rt_lighting=0;Gfx.apply_env(game._env)
	GameData.options.pt_sharc=int(OS.get_cmdline_user_args().has("--pt-sharc"))
	GameData.options.pt_restir=int(OS.get_cmdline_user_args().has("--pt-rtxdi"))
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"campaign snapshot includes the hidden emissive mesh")
	if rt.stats.get("active",false):
		var scene: RefCounted=rt._scene;var device: RefCounted=rt.device
		await frames(45)
		check(rt.stats.get("emissive_triangles",-1)==0 and not device.get("_uses_emitters"),"hidden campaign emitter uses the lean pipeline")
		check(device.sharc.active==bool(GameData.options.pt_sharc),"emitter fixture uses the requested cache mode")
		if GameData.options.pt_restir:
			check(device._rtxdi_mode and device.rtxdi.frames>0 and not device.rtxdi_failed,"emitter fixture executes actual RTXDI reservoirs")
		var prepared_programs: int=rt._programs.compilations
		await capture("campaign-emitter-hidden")
		var original:=red_mean(device.output.get_image())
		glow.show();await frames(45)
		check(rt._scene==scene and rt.device==device,"revealing emission retains the campaign snapshot and device")
		check(rt.stats.get("emissive_triangles",0)==12 and device.get("_uses_emitters"),"the collector passes all twelve emissive box triangles to the sampler")
		check(rt._programs.compilations==prepared_programs,"first visible emitter compiles no PT or SHaRC programs during play")
		var lit:=red_mean(device.output.get_image());await capture("campaign-emitter-lit")
		check(lit>original+0.005,"emissive light reaches real terrain receivers: %s -> %s"%[original,lit])
		glow.position.x+=0.8;await frames(30)
		check(rt._scene==scene and rt.stats.get("emissive_triangles",0)==12,"moving the campaign emitter updates placement without a scene rebuild")
		check(rt._programs.compilations==prepared_programs,"moving emission reuses prepared programs")
		await capture("campaign-emitter-moved")
		glow.hide();await frames(15)
		var restored:=red_mean(device.output.get_image());await capture("campaign-emitter-restored")
		check(rt.stats.get("emissive_triangles",-1)==0 and not device.get("_uses_emitters"),"hiding the final campaign emitter restores the lean pipeline")
		check(rt._programs.compilations==prepared_programs,"last emitter expiry reuses the prepared lean programs")
		check(absf(restored-original)<(lit-original)*0.2,"old emissive illumination disappears from the actual receivers")
		glow.show();await frames(15)
		material.emission_enabled=false;rt._poll=0.0
		# The bounded topology scan can take more than two frames to reach
		# this object's material. An active old scene is not a replacement.
		var replacement_deadline:=Time.get_ticks_msec()+90000
		while rt._scene==scene and not rt._failed and Time.get_ticks_msec()<replacement_deadline:
			await frames(1)
		check(await ready_scene(rt) and rt._scene!=scene,"material emission changes rebuild the supported snapshot")
		check(rt._scene!=scene and rt.stats.get("emissive_triangles",-1)==0,"extinguished material is excluded by the gatherer's emission metadata")
		rows.append({"original_red":original,"lit_red":lit,"restored_red":restored,
			"prepared_programs":prepared_programs,"final_programs":rt._programs.compilations,"stats":rt.stats.duplicate()})
	FileAccess.open(out.path_join("path-emitter-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":rows},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_EMITTER_LIVE ",checks," checks ",failures.size()," failures");get_tree().quit(1 if not failures.is_empty() else 0)
