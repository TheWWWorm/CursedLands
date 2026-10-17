extends "arena_expansion_ui.gd"
## Live, rendered coverage for scaling, board effects/audio and staged combat.
func _ready() -> void:
	OS.add_logger(errors); await frames(18)
	GameData._window_gen += 1
	GameData.arena_mode=1;GameData.arena_speed=1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0},true)
	var lang:="en";var dimensions:=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec:=arg.get_slice("=",1).split(",");lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.mode=Window.MODE_WINDOWED;get_tree().root.size=dimensions;get_tree().root.position=Vector2i.ZERO;RemakeText.lang=lang
	await frames(8)
	screen=ArenaPveScreen.new();add_child(screen);await frames(18)
	screen._seed_input.text="7319";screen._begin();screen.run.auto_save=false
	for i in 3: screen._recruit_offer(i)
	var league:=screen.run as ArenaTournamentRun
	league.wave=4;league._prepare_round();screen._refresh();await frames(12)
	var manager:=screen._tournament_battles
	var tag:="presentation-%s-%d"%[lang,dimensions.x]
	check(is_equal_approx(screen._ui_scale,maxf(0.85,minf(dimensions.x/1440.0,dimensions.y/900.0))),"HUD scales to the entire high-resolution display")
	for control in [screen._standings,screen._shop_panel,screen._bench_panel,screen._round_panel]:bounded(control,"scaled HUD")
	await get_tree().create_timer(1.5).timeout
	var opponent:=league.opponent_for(0)
	screen._show_player(opponent);await frames(6)
	var selected:Button
	for button in screen._standing_rows.find_children("*","Button",true,false):
		if button.get_meta("board_player",-1)==opponent:selected=button
	check(is_instance_valid(selected) and selected.get_theme_stylebox("normal").border_width_left==3,"watched player has a visible marker")
	check(selected.get_theme_stylebox("normal").bg_color.a==0,"selected board has no added background")
	check(screen._sound.mixer.sfx_on and screen._sound_world==screen.field.match_state.world,"scouting enables audio immediately")
	for variant in 4:
		ink_variant(screen,variant)
		await shot(tag+"-ink"+str(variant))
	ink_variant(screen,0)
	hold_preparation=false;league.preparation_left=8.0
	await frames(4)
	var alpha:=screen._clock.modulate.a
	await get_tree().create_timer(0.2).timeout
	check(screen._clock.get_theme_color("font_color")==Color("ff9377") and not is_equal_approx(alpha,screen._clock.modulate.a),"last ten seconds change color and pulse")
	await shot(tag+"-clock")
	league.preparation_left=60.0;hold_preparation=true
	manager.set_process(false)
	var start:=Time.get_ticks_usec();screen._fight()
	var request_ms:=(Time.get_ticks_usec()-start)/1000.0
	check(manager.starting and screen.battle.phase==ArenaMatch.Phase.DEPLOY,"battle request yields before constructing nine boards")
	check(not league.can_shop() and not league.can_undo(),"shared roster stays fixed during the short staging interval")
	var frame_times:=[]
	while manager.starting:
		start=Time.get_ticks_usec();manager._process(0);frame_times.append((Time.get_ticks_usec()-start)/1000.0)
		if manager.starting:
			check(screen.battle.phase==ArenaMatch.Phase.DEPLOY and manager.boards.values().all(func(board):return board.phase==ArenaMatch.Phase.DEPLOY),"no board gains combat time during setup")
		await frames(1)
	print("ARENA_START_PROFILE request_ms=",request_ms," frames_ms=",frame_times)
	manager.set_process(true);await frames(6)
	check(screen.battle.phase==ArenaMatch.Phase.FIGHT and manager.boards.values().all(func(board):return board.phase==ArenaMatch.Phase.FIGHT),"all nine boards start together")
	check(league.can_shop(),"shop reopens as combat starts")
	# A real attack event on the viewed board must reach a playing mixer channel.
	screen._show_player(opponent);await frames(3)
	var watched:=manager.watched_match();var heard:=false
	for i in 120:
		if screen._sound.mixer._chans.any(func(channel):return channel.player.playing and not String(channel.snd.get("path","")).begins_with("buttons/")):heard=true;break
		await frames(1)
	check(heard and screen._sound.mixer.sfx_on,"viewed CPU battle plays sound")
	# Create a native missile on a board, move its display origin, then hide it.
	var fx:=ParticleFx.of(watched.world)
	var unit:GameUnit=watched.world.unit_rows()[0]
	fx.spell_cast({"spell":"arrow","a":unit.uid,"tu":watched.world.unit_rows().back().uid,"x":unit.pos.x,"y":unit.pos.y})
	await frames(4)
	screen._show_boards();await frames(3)
	check(fx.display_origin()==ArenaTournamentBattles.board_offset(opponent),"overview effects use their board origin")
	check(fx.carrier_point(FxEmitter.new(),unit).distance_to(ParticleFx.ei(unit.global_position-fx.display_origin()))<0.01,"effect carriers stay in local board coordinates")
	screen._show_player(0);await frames(3)
	check(not fx.is_visible_in_tree() and fx.effects.all(func(effect):return not is_instance_valid(effect.mmi) or not effect.mmi.visible),"hidden board particle meshes are hidden")
	# The last hit freezes combat, while presentation drains remaining spells.
	watched.set_process(false);watched.world.set_process(false);watched.world.set_physics_process(false)
	watched.winner=0;watched.phase=ArenaMatch.Phase.FINISHED;watched.world.process_mode=Node.PROCESS_MODE_DISABLED;watched._resolved(0)
	var hp:=watched.world.unit_rows().map(func(u):return u.hp);var time:=watched.world.time
	for i in 100:watched._process(0.02)
	await frames(3)
	check(not is_instance_valid(fx) and watched.world.get_children().all(func(n):return not(n is Projectile or n is SpellFx or n is ParticleFx)),"round-end spells drain and disappear")
	check(hp==watched.world.unit_rows().map(func(u):return u.hp) and watched.world.time==time,"finishing effects cannot cause late damage or advance combat")
	screen.queue_free();await frames(12)
	check(errors.messages.is_empty(),"no runtime errors: "+JSON.stringify(errors.messages.slice(0,3)))
	print("ARENA_PRESENTATION_UI ",tag," checks=",checks," failures=",JSON.stringify(failures))
	OS.remove_logger(errors);get_tree().quit(0 if failures.is_empty() else 1)

func ink_variant(parent:Node,variant:int)->void:
	for child in parent.get_children():
		if child is Control and child.has_theme_color_override("font_outline_color") and child.get_theme_color("font_outline_color") in [Color("eeeeee"),Color("ffffff"),Color("181818"),Color.TRANSPARENT]:
			var accent:bool=child.get_theme_color("font_color")==ArenaCreatureCard.SNOW_ACCENT
			var color:Color=[Color("141414"),Color("101010"),Color("302118"),Color("ffffff")][variant]
			ArenaCreatureCard.snow_ink(child,ArenaCreatureCard.SNOW_ACCENT if accent else color)
			child.add_theme_color_override("font_outline_color",Color("181818") if variant==3 else Color.TRANSPARENT)
			child.add_theme_constant_override("outline_size",3 if variant==3 else 0)
			child.add_theme_font_override("font",preload("res://fonts/LiberationSans-Bold.ttf") if variant in [1,3] else preload("res://fonts/LiberationSans-Regular.ttf"))
			if child.has_meta("board_player"):
				child.add_theme_font_size_override("font_size",14)
		ink_variant(child,variant)
