extends "arena_species_ui.gd"
## Exercise rendered planning fire, terrain receivers and scouting cleanup.
func guide_value(ground: ArenaWinterTerrain, expected: float, label: String) -> void:
	check(is_equal_approx(ground.deployment_guide,expected),label+" terrain state")
	check(is_equal_approx(float(ground._land_mat.get_shader_parameter("arena_deploy_weight")),expected),label+" land material")
	check(ground._land_mat.get_shader_parameter("arena_deploy_edge")==Vector3(ArenaRun.DEPLOY.end.x,ArenaRun.DEPLOY.position.y,ArenaRun.DEPLOY.end.y),label+" actual placement boundary")
	if expected <= 0.0:
		check(not is_instance_valid(ground._guide_fire),label+" has no fire emitter")
	else:
		var fire:=ground._guide_fire
		check(is_instance_valid(fire) and fire.effects.size()==1,label+" has one fire emitter")
		if is_instance_valid(fire):
			check(fire.world==null and fire.lights.is_empty() and fire.missiles.is_empty(),label+" fire cannot change combat or add lights")
			var emitter: FxEmitter=fire.effects[0].e
			check(emitter.parts.size()<=256,label+" particle count remains bounded")
	if is_instance_valid(ground.details) and is_instance_valid(ground.details.soft_ground):
		for sector: Dictionary in ground.details.soft_ground.sectors.values():
			check(is_equal_approx(float(sector.material.get_shader_parameter("arena_deploy_weight")),expected),label+" deformed snow material")

func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen+=1; GameData.arena_mode=1
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"autosave":0,"net_directory":0,"net_upnp":0},true)
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,800); get_window().position=Vector2i.ZERO
	get_window().grab_focus(); await frames(8)
	screen=ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text="7191"; screen._begin(); screen.run.auto_save=false
	screen.run.army.clear(); screen.run.training=36
	for pair in [[0,1],[11,1],[16,1],[23,0],[6,1]]: screen.run._recruit(pair[0],pair[1],9)
	screen.run.arrange(); screen.run._touch(); await wait_models()
	await frames(90)
	screen._round_banner._age=10
	var terrain: ArenaWinterTerrain=screen.battle.world.terrain
	check(GameData.option("gfx_biome_cover")==1,"Ultra cover preference stays enabled for campaign maps")
	check(not terrain.details._cover and terrain.details._cover_field==null,"arena has no procedural pebbles or snow mounds")
	var campaign_details := TerrainDetails.new()
	check(campaign_details._wants_biome_cover(),"campaign keeps its cover setting")
	campaign_details.free()
	guide_value(terrain,0.8,"preparation")
	var fire := terrain._guide_fire
	check(is_instance_valid(fire) and fire.effects.size()==1,"one visual boundary emitter")
	if is_instance_valid(fire):
		var emitter: FxEmitter=fire.effects[0].e
		var height:=0.0
		for part: Array in emitter.parts: height=maxf(height,float(part[2]))
		print("GUIDE_FIRE ",JSON.stringify({"particles":emitter.parts.size(),"height":height,"size":emitter.s,"rise":emitter.a110,"frame_ticks":emitter.e4}))
		check(is_zero_approx(height),"fire bases stay on the snow throughout the animation")
		check(emitter.s*2.2>0.7 and emitter.s*2.2<1.0,"upright flame geometry stays below one metre")
		for material: ShaderMaterial in fire._mats.values():
			check(float(material.get_shader_parameter("boost"))<1.0,"planning fire avoids combat HDR boost")
	var method:=RenderingServer.get_current_rendering_method()
	await shot("guide-"+method+"-default")
	fire.hide();fire.sync_visibility();await shot("guide-"+method+"-ground")
	print("GUIDE_ORIGIN ",terrain.global_position)
	fire.show();fire.sync_visibility()
	if "--guide-animation" in OS.get_cmdline_user_args():
		var samples := []
		for frame in 32:
			await get_tree().create_timer(0.125).timeout
			await RenderingServer.frame_post_draw
			var name := "guide-motion-%02d.png" % frame
			get_viewport().get_texture().get_image().save_png("user://"+name)
			samples.append({"file":name,"milliseconds":Time.get_ticks_msec()})
		FileAccess.open("user://guide-motion.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
	screen._select(int(screen.run.army[0].uid)); await frames(8)
	guide_value(terrain,1.0,"selected placement")
	check(terrain._guide_fire==fire,"selection reuses the existing emitter")
	screen.field.zoom*=0.72
	for frame in 60:
		screen.field.advance_camera(1.0/60.0,0.35,Vector2(0.2,0.0)); await frames(1)
	await shot("guide-"+method+"-orbit")
	screen._clear_selection(); screen._show_boards(); await frames(12)
	guide_value(terrain,0.0,"overview")
	check(not is_instance_valid(fire),"overview frees the old emitter and its draw batches")
	screen._show_player(1); await frames(20)
	guide_value(terrain,0.0,"previously watched ground")
	guide_value(screen.field.match_state.world.terrain,0.8,"scouted preparation")
	screen._show_player(0); await frames(12); screen.field.reset_camera()
	guide_value(terrain,0.8,"return home")
	for iteration in 4:
		var previous: ArenaWinterTerrain=screen.field.match_state.world.terrain
		var previous_fire:=previous._guide_fire
		screen._show_player(1 if iteration%2==0 else 0); await frames(12)
		check(not is_instance_valid(previous_fire),"scouting frees old fire %d" % iteration)
		guide_value(previous,0.0,"scouting previous %d" % iteration)
		guide_value(screen.field.match_state.world.terrain,0.8,"scouting current %d" % iteration)
	# Exercise the material refresh path used when graphics settings change.
	terrain.apply_gfx(); terrain.details.apply_options(); guide_value(terrain,0.8,"graphics refresh")
	check(not terrain.details._cover,"graphics refresh keeps arena clearing free of scatter")
	var soft:=GameData.option("gfx_soft_particles")
	for value in [0,1]:
		GameData.options.gfx_soft_particles=value
		GameData.options_changed.emit();await frames(8)
		check(terrain._guide_fire.effects.size()==1,"particle quality change keeps one boundary emitter")
		for material: ShaderMaterial in terrain._guide_fire._mats.values():
			check(material.shader.code.contains("#define EI_PARTICLE_NO_DEPTH")==(value==0),"rooted flames honor soft particle setting")
	GameData.options.gfx_soft_particles=soft;GameData.options_changed.emit()
	screen.battle.phase=ArenaMatch.Phase.FIGHT; await frames(8)
	guide_value(terrain,0.0,"combat")
	await shot("guide-"+method+"-hidden")
	check(errors.messages.is_empty(),"no shader or engine errors: "+str(errors.messages))
	print("DEPLOYMENT_GUIDE ",method," checks=",checks," failures=",JSON.stringify(failures))
	screen.queue_free(); screen=null; await frames(8)
	get_tree().quit(0 if failures.is_empty() else 1)
