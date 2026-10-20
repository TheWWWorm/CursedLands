extends "arena_expansion_ui.gd"
func player_button(player: int) -> Button:
	for button: Button in screen._standing_rows.find_children("*","Button",true,false):
		if int(button.get_meta("board_player",-1))==player: return button
	return null
func _ready() -> void:
	OS.add_logger(errors); await frames(12)
	GameData._window_gen += 1; GameData.arena_mode=1
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): lang=arg.trim_prefix("--lang=")
	RemakeText.lang=lang
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,800)
	await frames(6)
	screen=ArenaPveScreen.new(); add_child(screen); await frames(12)
	screen._seed_input.text="7191"; screen._begin(); screen.run.auto_save=false
	for plan: Dictionary in screen.run.bot_plans: plan.done=true
	await frames(18); screen.set_process(false)
	screen.run.wave=2; screen.run.last_result={"wave":1,"winner":0}
	screen.run.company(1).last_result={"wave":1,"winner":1}
	screen.run.company(2).last_result={"wave":1,"winner":-1}
	screen._build_standings(); await frames(6); screen._update_name_flashes(3)
	check(player_button(0).get_theme_color("font_color")==ArenaPveScreen.STANDING_WIN,"winner stays green throughout preparation")
	check(player_button(1).get_theme_color("font_color")==ArenaPveScreen.STANDING_LOSS,"loser stays red throughout preparation")
	check(player_button(2).get_theme_color("font_color")==ArenaCreatureCard.SNOW_INK,"draw keeps a neutral name")
	check(player_button(0).tooltip_text.contains(RemakeText.t("Last battle: %s")%RemakeText.t("Victory")),"result is also available in localized text")
	screen._show_player(1); await frames(6)
	check(player_button(1).get_theme_color("font_color")==ArenaPveScreen.STANDING_LOSS,"scouting retains the loser's result color")
	check(player_button(1).get_theme_stylebox("normal").border_width_left==3,"watched player keeps the independent selection marker")
	screen._show_player(0); await frames(6)
	await shot("standings-results-"+lang+"-prepare")
	screen.run.stage="fight"; screen.run.preparing_battle=true
	check(screen._standing_color(0)==ArenaPveScreen.STANDING_WIN and screen._standing_color(1)==ArenaPveScreen.STANDING_LOSS,"staging the next battle preserves result colors")
	screen.run.preparing_battle=false
	screen._update_name_flashes(0)
	check(player_button(0).get_theme_color("font_color")==ArenaCreatureCard.SNOW_ACCENT,"next battle clears the previous winner color")
	check(player_button(1).get_theme_color("font_color")==ArenaCreatureCard.SNOW_INK,"next battle clears the previous loser color")
	screen.run.company(1).last_result={"wave":2,"winner":0}; screen._update_name_flashes(0)
	check(player_button(1).get_theme_color("font_color")==ArenaPveScreen.STANDING_WIN,"finished board receives its current result while other battles continue")
	screen.run.stage="prepare"; screen.run.wave=3; screen._update_name_flashes(0)
	check(player_button(1).get_theme_color("font_color")==ArenaPveScreen.STANDING_WIN,"result remains through the following preparation")
	if lang == "en":
		screen.run.wave=1; screen.run.army.clear(); screen.run.last_result.clear()
		for family in ArenaRules.FAMILIES.size():
			if String(ArenaRules.FAMILIES[family].forms[0]).to_lower()=="ancientcursem25":
				var entry:=screen.run._recruit(family,2,9); entry.deployed=true; entry.point=[32.0,32.0]
		screen._refresh(); await frames(18)
		var battle:=screen.battle; battle.formation_motion.settle(battle.world)
		battle.set_process(false); battle.world.process_mode=Node.PROCESS_MODE_DISABLED
		var actor:GameUnit=battle.world.unit_rows()[0]
		actor.model.set_process(false)
		var clip:=actor._cast_clip()
		actor.model.player.play("ei/"+clip,0); actor.model.player.seek(float(GameUnit._clip_hit_frame(actor.model.template,clip))/EIAnim.FPS,true)
		actor.model.flush_pending_pose()
		var fx:=ParticleFx.of(battle.world); fx.set_process(false)
		fx.spell_cast({"spell":"curse_magic","a":actor.uid,"x":actor.pos.x+5,"y":actor.pos.y})
		screen.field.camera.size=9
		screen.field.camera.position=actor.global_position+Vector3(-10,9,12)
		screen.field.camera.look_at(actor.global_position+Vector3(2,1.6,0))
		fx._process(0.01)
		check(screen.field.camera.unproject_position(ParticleFx.godot(fx.cast_point(actor))).distance_to(screen.field.camera.unproject_position(ParticleFx.godot(fx.unit_point(actor,0))))>10,"rendered Horror fingertip source is visibly separate from the torso")
		await shot("horror-fingertip-cast")
		actor.hp=0; actor.die()
		battle.phase=ArenaMatch.Phase.FINISHED
		for i in 16: battle._process(0.1)
		check(actor.is_frozen() and absf(ArenaPveMatch._corpse_clearance(actor))<0.001,"rendered Horror corpse lands after the battle clock stops")
		await shot("horror-grounded-corpse")
		battle.world.remove_unit(actor); await frames(4)
		actor=battle._spawn({"id":"DragonBrownM16","team":0,"rank":2,"run_uid":1000,"point":Vector2(32,32)})
		actor.model.set_process(false)
		clip=actor._cast_clip(); actor.model.play(clip,0,true)
		actor.model.player.seek(float(GameUnit._clip_hit_frame(actor.model.template,clip))/EIAnim.FPS,true)
		actor.model.flush_pending_pose()
		fx=ParticleFx.of(battle.world); fx.set_process(false)
		fx.cast_fx({"uid":actor.uid,"spell":"fireball","secs":1.0})
		var charge:ParticleFx.Effect=fx.effects.back()
		for i in 10: fx._process(ParticleFx.TICK)
		check(charge.e.wp.distance_to(fx.cast_point(actor))<0.001,"rendered dragon charge-up converges on its animated mouth")
		await shot("dragon-mouth-charge")
		fx.spell_cast({"spell":"fireball","a":actor.uid,"x":actor.pos.x+5,"y":actor.pos.y})
		check(fx._pending_fireballs.back().pos.distance_to(charge.e.wp)<0.001,"rendered dragon release shares the charge-up origin")
		fx._process(ParticleFx.TICK)
		await shot("dragon-mouth-release")
		# Result salutes are a separate HUD effect; they must use the same
		# muzzle as combat, including the watched board's local world offset.
		screen.run.pairings.assign([{"a":0,"b":1,"ghost":false}])
		screen._capture_health_changes()
		var volley:=screen._result_volley; volley.process_mode=Node.PROCESS_MODE_DISABLED
		screen.run.rival_health[0]-=7; screen._capture_health_changes()
		await frames(4)
		check(volley._events.size()==1,"a dragon survivor queues one result salute: "+str(volley._events.size()))
		if not volley._events.is_empty():
			var muzzle:=screen.field.camera.unproject_position(ParticleFx.godot(fx.cast_point(actor))+fx.display_origin())
			var expected:=volley.get_global_transform_with_canvas().affine_inverse()*(screen.field.get_global_transform_with_canvas()*muzzle)
			check((volley._events[0].start as Vector2).distance_to(expected)<0.1,"result salute starts at the dragon's mouth instead of its body")
	screen.queue_free(); screen=null; await frames(8)
	check(errors.messages.is_empty(),"no runtime errors: "+JSON.stringify(errors.messages.slice(0,3)))
	print("ARENA_STANDINGS_RESULTS ", JSON.stringify({"checks":checks,"failures":failures}))
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
