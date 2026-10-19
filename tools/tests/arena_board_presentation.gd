extends "arena_expansion_ui.gd"
## Exercise the real online replica, including rapid overview/scout changes.
func check_render_positions(battle: ArenaPveMatch, label: String) -> void:
	var sampled := 0
	var worst := 0.0
	for unit: GameUnit in battle.world.unit_rows():
		for mesh: GeometryInstance3D in unit._geoms:
			if not is_instance_valid(mesh) or not mesh.is_visible_in_tree(): continue
			sampled += 1
			worst = maxf(worst, mesh.global_position.distance_to(mesh.get_global_transform_interpolated().origin))
	# A moving limb can span part of a stride between the CPU and render
	# samples; a stale overview cell displaces the entire mesh by 64m or more.
	check(sampled > 0 and worst < 2.0, "%s: rendered meshes match the current board (%d meshes, %.3fm error)" % [label, sampled, worst])


func red_pixels() -> int:
	var image := screen.field.view.get_texture().get_image()
	var colored := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.r>.55 and color.g<.2 and color.b<.2: colored+=1
	return colored

func _ready() -> void:
	OS.add_logger(errors); await frames(12)
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"gfx_hd_textures":0},true)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,720)
	var connection := ArenaOnlineSession.new(); add_child(connection)
	check(connection.host(29849)==OK,"local authority starts")
	check(connection.start_game(7319).is_empty(),"online game starts")
	connection.game.set_process(false)
	await frames(12)
	var online := ArenaOnlineScreen.new(); online.connection=connection; add_child(online); screen=online
	var run := connection.game.run
	run.training=126
	for family in [0,1,2,3,4,5,6]: run._recruit(family,0,1)
	for family in [15,4]: run._recruit(family,2,9)
	run.arrange(); connection.game._prepare()
	await frames(45)
	screen.battle.formation_motion.settle(screen.battle.world)
	await frames(8)
	await shot("board-presentation-before")
	var actor: GameUnit=screen.battle.world.unit_rows()[0]
	var snap := actor.snapshot()
	# First prime the steady-action cache with a running network pose.
	snap[4]="run"; snap[13]=4.0
	actor._set_action("run")
	actor.apply_snapshot(snap,false,ArenaOnlineGame.exact_body(actor))
	actor.model.player.advance(.2)
	var moving_clip := actor.model.player.current_animation
	check(actor.model._cycle==actor.model.code_for("run"),"fixture plays native run animation")
	snap[4]="idle"; snap[13]=0.0
	actor.apply_snapshot(snap,false,ArenaOnlineGame.exact_body(actor))
	screen.battle._stop_locomotion()
	check(actor.action=="idle" and actor.model._cycle==actor.model.code_for("idle"),"finished replica replaces running clip with native idle")
	# A stopped model cannot hide transform propagation bugs by moving again.
	connection.set_process(false)
	screen.battle.world.process_mode=Node.PROCESS_MODE_DISABLED
	var ink := StandardMaterial3D.new(); ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; ink.albedo_color=Color.RED
	for unit: GameUnit in screen.battle.world.unit_rows():
		for mesh: GeometryInstance3D in unit._geoms: mesh.material_override=ink
	for index in 20:
		screen._show_boards(); await frames(1+index%3)
		screen._show_player(1+index%8); await frames(1+index%2)
		screen._show_boards(); await frames(1)
		screen._show_player(0); await frames(4)
		check_render_positions(screen.battle, "stopped return %d" % index)
		for unit: GameUnit in screen.battle.world.unit_rows():
			check(unit.is_visible_in_tree() and unit.model.is_visible_in_tree(),"returned actor remains visible %d"%index)
			check(unit._geoms.any(func(g):return is_instance_valid(g) and g.is_visible_in_tree()),"returned actor has drawable geometry %d"%index)
		if index in [0,9,19]:
			await RenderingServer.frame_post_draw
			var colored := red_pixels()
			check(colored>200,"paused models still render after board switches: %d pixels"%colored)
			await shot("board-presentation-return-"+str(index))
	# A tall window and steep orbit must restore the fitted far plane after
	# scouting. Deliberately clip the models, then compare real GPU output.
	get_window().size=Vector2i(1280,1100); await frames(12)
	screen.field.pitch_offset=deg_to_rad(35); screen.field.zoom=23; screen.field._update_camera()
	var fitted_far := screen.field.camera.far
	screen.field.camera.far=30; await frames(6); await RenderingServer.frame_post_draw
	var clipped := red_pixels(); await shot("board-presentation-old-clip")
	screen._show_boards(); await frames(3); screen._show_player(0); await frames(6); await RenderingServer.frame_post_draw
	var fitted := red_pixels()
	print("CAMERA_CLIP old_pixels=",clipped," fitted_pixels=",fitted," far=",fitted_far)
	check(is_equal_approx(screen.field.camera.far,fitted_far) and fitted>clipped+100,"orbit return restores the fitted plane and visible models")
	await shot("board-presentation-orbit")
	get_window().size=Vector2i(1280,720); screen.field.reset_camera(); await frames(12)
	# A full next-round generation can arrive while the home board is hidden.
	connection.set_process(true)
	for index in 5:
		screen._show_boards(); await frames(3); screen._show_player(index+1); await frames(3)
		run.stage="fight"; run.resolve(0,12,[100,0],[9,0])
		for seat in range(1,9): run.record_board(seat,0,[3,0])
		run.advance(); connection.game._prepare()
		await frames(16); screen._show_player(0); await frames(24)
		screen.battle.formation_motion.settle(screen.battle.world)
		check_render_positions(screen.battle, "hidden round %d" % index)
		check(screen.battle.world.unit_rows().size()==run.deployed_count(),"new generation retains every home creature")
		for unit: GameUnit in screen.battle.world.unit_rows():
			check(unit.model.is_visible_in_tree() and unit._geoms.any(func(g):return g.is_visible_in_tree()),"hidden round replacement restores drawable figure")
	await shot("board-presentation-next-round")
	# Keep receiving native movement while the board's presentation parent
	# moves between overview cells. Visible flags alone miss stale FTI poses.
	connection.game.set_process(true)
	connection.request("ready")
	for index in 16:
		screen._show_boards(); await get_tree().create_timer(.15).timeout
		screen._show_player(1 + index % 8); await get_tree().create_timer(.15).timeout
		check_render_positions(screen.field.match_state, "live scout %d" % index)
		screen._show_player(0); await get_tree().create_timer(.15).timeout
		check_render_positions(screen.battle, "live return %d" % index)
	connection.game.set_process(false)
	await shot("board-presentation-live-return")
	# Eliminated spectators keep read-only hover access.
	screen.run.lives=0
	connection.set_process(true)
	screen._show_player(1); await frames(24)
	var watched := screen.field.match_state
	if watched.world.unit_rows().is_empty():
		connection.game.run.company(1)._recruit(0,0,1); connection.game.run.company(1).arrange(); connection.game.boards._sync_board(1)
		await frames(30)
	connection.set_process(false); screen.run.lives=0
	var target: GameUnit=watched.world.unit_rows()[0]
	watched.formation_motion.settle(watched.world); await frames(4)
	var rects := target.screen_rects(screen.field.camera)
	await move(Rect2(rects[0]).get_center()); await get_tree().create_timer(.5).timeout
	check(not screen.run.can_shop() and screen._inspected_unit==target and screen._inspector.visible,"eliminated spectator can hover a watched creature")
	await shot("board-presentation-spectator")
	check(errors.messages.filter(func(message):return not message.begins_with("NO GRAB")).is_empty(),"no runtime/render errors: "+str(errors.messages))
	connection.close(); screen.queue_free(); connection.queue_free(); screen=null; await frames(6)
	print("ARENA_BOARD_PRESENTATION ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
