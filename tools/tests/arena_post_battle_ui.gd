extends "arena_expansion_ui.gd"
## Real HUD transforms, particle projection, re-sorted standings and retained rows.
func _ready() -> void:
	OS.add_logger(errors); await frames(12)
	GameData._window_gen += 1; GameData.arena_mode = 1
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): lang = arg.trim_prefix("--lang=")
	RemakeText.lang = lang
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1280,800)
	await frames(6)
	screen = ArenaPveScreen.new(); add_child(screen); await frames(12)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	Fixture.buy_company(screen.run, 1)
	for plan: Dictionary in screen.run.bot_plans: plan.done = true
	screen._refresh(); await frames(24); screen.set_process(false)
	var battle := screen.battle
	var uid := int(battle.round_army[0].uid)
	var prototype: String = battle.round_army[0].prototype
	battle.friendly_damage[uid] = 125.0
	battle.phase = ArenaMatch.Phase.FINISHED
	battle._remember_damage()
	screen.run.wave = 2; screen.run.army[0].deployed = false
	screen.run._recruit(6,0,1)
	screen._refresh(); await frames(12)
	screen._damage_panel.update_damage(battle,screen._field_army(),260)
	check(screen._damage_panel.rows.has(uid), "withdrawn fighter remains in the previous battle report")
	check(screen._damage_panel.rows[uid].value.text == "125", "finished damage total survives preparation")
	check(screen._damage_panel.rows[uid].title.text == ArenaRules.title(prototype), "report retains the localized name from the battle roster")
	await shot("post-battle-"+lang+"-damage")
	var volley := screen._result_volley
	for target in [Vector2(100,100),Vector2(1100,300),Vector2(1200,600)]:
		var projected := volley._camera.unproject_position(ParticleFx.godot(volley._particle_point(target)))
		check(projected.distance_to(target)<0.1,"native particle projection reaches the exact requested HUD pixel")
	var actor: GameUnit = battle.world.unit_rows()[0]
	var at := screen.field.camera.unproject_position(actor.global_position+Vector3.UP)
	var start := volley.get_global_transform_with_canvas().affine_inverse() * (screen.field.get_global_transform_with_canvas()*at)
	var target := screen._volley_target(1)
	volley.present(PackedVector2Array([start]),target,7,false,screen._hud.scale.x,screen._volley_target.bind(1))
	volley.set_process(false); volley._process(0)
	check(volley._flights.size()==1,"one surviving fighter launches one tracked native bolt")
	if not volley._flights.is_empty():
		var missile: Dictionary = volley._flights[0].missile
		check(volley._camera.unproject_position(ParticleFx.godot(missile.pos)).distance_to(start)<0.1,"bolt starts on the actual fighter")
		check(volley._camera.unproject_position(ParticleFx.godot(missile.point)).distance_to(target)<0.1,"bolt ends on the defeated player's name")
		screen.run.rival_health[0] = 80; screen._build_standings(); await frames(6)
		var moved := screen._volley_target(1)
		check(moved.distance_to(target)>10,"fixture reorders the defeated player's standings row")
		volley._process(ParticleFx.TICK)
		check(volley._camera.unproject_position(ParticleFx.godot(missile.point)).distance_to(moved)<0.1,"in-flight bolt follows the same player after row reordering")
		for index in 6: volley._process(ParticleFx.TICK); await frames(1)
		await shot("post-battle-"+lang+"-volley")
	volley.clear()
	volley.present(PackedVector2Array([Vector2(0,400)]),Vector2(4000,400),1,false,1.0)
	volley.set_process(false)
	for index in 65: volley._process(ParticleFx.TICK)
	check(is_instance_valid(volley._fx) and not volley._fx.missiles.is_empty(),"high-resolution flight survives beyond the old three-second cutoff")
	for index in 90: volley._process(ParticleFx.TICK)
	check(not is_instance_valid(volley._fx),"long flight reaches its destination and releases the effect")
	volley.clear()
	for dimensions in [Vector2i(1024,768),Vector2i(1600,900)]:
		get_window().size = dimensions; await frames(6)
		var current := screen._volley_target(1)
		check(volley._camera.unproject_position(ParticleFx.godot(volley._particle_point(current))).distance_to(current)<0.1,
			"particle destination stays aligned after viewport and HUD scaling")
	get_window().size = Vector2i(1280,800); await frames(6)
	screen.run.rival_health[0] = 0; screen.run.placements[1] = 0
	screen._capture_health_changes(); screen._build_standings(); await frames(6)
	var pending: Button
	for button: Button in screen._standing_rows.find_children("*","Button",true,false):
		if int(button.get_meta("board_player",-1))==1: pending=button
	check(pending.get_parent().get_child(1).text==RemakeText.t("Out"),"unsettled elimination shows localized status instead of place zero")
	check(screen._elimination_queue.size()==1,"zero health queues an immediate elimination notice")
	screen._update_eliminations(0,false)
	check(screen._elimination_notice.visible and screen._elimination_notice.text.contains(screen.run.player_title(1)),"elimination notice names the eliminated player")
	screen._capture_health_changes()
	check(screen._elimination_queue.is_empty(),"repeated snapshots do not repeat elimination notices")
	screen.run.placements[1] = 9; screen._build_standings(); await frames(6)
	for button: Button in screen._standing_rows.find_children("*","Button",true,false):
		if int(button.get_meta("board_player",-1))==1:
			check(button.get_parent().get_child(1).text=="#9","settled elimination shows the assigned finishing place")
	bounded(screen._elimination_notice,"localized elimination notice")
	await shot("post-battle-"+lang+"-elimination")
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(), "no runtime errors: "+JSON.stringify(errors.messages.slice(0,3)))
	print("ARENA_POST_BATTLE_UI ",checks," checks; failures=",JSON.stringify(failures))
	OS.remove_logger(errors); TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
