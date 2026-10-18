extends "arena_expansion_ui.gd"
func _ready()->void:
	OS.add_logger(errors);await frames(24);hold_preparation=false
	GameData._window_gen+=1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"gfx_hd_textures":0},true)
	var lang:="en";var dimensions:=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--feedback-ui="):
			var spec:=arg.get_slice("=",1).split(",");lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	RemakeText.lang=lang
	get_window().mode=Window.MODE_WINDOWED;get_window().size=dimensions;get_window().position=Vector2i.ZERO
	var c:=ArenaOnlineSession.new();c.player_name="Worm";add_child(c)
	check(c.host(29847)==OK,"host starts");check(c.start_game(7191).is_empty(),"online game starts");c.game.set_process(false)
	await frames(12)
	var online:=ArenaOnlineScreen.new();online.connection=c;add_child(online);screen=online
	await frames(20);c.request("buy",[0]);await frames(20);c.request("buy",[1]);await frames(20)
	check(screen.run.player_title(0)=="Worm","standings use player name")
	screen.battle.formation_motion.settle(screen.battle.world)
	var actor:GameUnit=screen.battle.world.unit_rows()[0]
	await move(point(actor));await get_tree().create_timer(0.5).timeout
	check(screen._inspector.visible,"host hover opens details")
	var steady:=true
	for i in 30:
		c.game.run.preparation_left-=0.1
		c.view.apply_state(c.game.state_for(0,c._names()))
		await frames(1)
		steady=steady and screen._inspector.visible and screen._inspected_unit==actor
	check(steady,"countdown updates never blink host details")
	await shot("feedback-"+lang+"-hover")
	await move(Vector2(5,dimensions.y-5));await frames(20)
	await shot("feedback-"+lang+"-standings")
	screen._show_boards();await frames(30)
	for i in 3:
		c.game.run.gold+=1
		c.view.apply_state(c.game.state_for(0,c._names()))
		await frames(3)
	check(screen.field.showing_boards(),"state refresh preserves overview")
	for player in range(9):
		var b:ArenaPveMatch=screen.battle if player==0 else screen._tournament_battles.boards[player]
		var origin:=ArenaTournamentBattles.board_offset(player)
		check(is_instance_valid(b.world) and b.world.is_visible_in_tree() and b.world.global_position==origin,"overview contains board "+str(player))
		var at:=screen.field.camera.unproject_position(origin+Vector3(32,0,-32))
		check(screen.field._map_player(at)==player,"overview selects board "+str(player))
	await shot("feedback-"+lang+"-overview")
	screen._show_player(0);await frames(8)
	check(screen.battle.world.global_position==Vector3.ZERO and screen.field.camera.far>=90,"return restores focused board and camera")
	c.game.start_round();await frames(15)
	online._toggle_speed();await frames(15)
	check(screen._speed.visible and not screen._speed.disabled and c.view.battle_speed==2 and Engine.time_scale==2,"host can use shared 2x control")
	var marked:=false
	for button in screen._standing_rows.find_children("*","Button",true,false):
		if button.get_meta("board_player",-1)==0:marked=button.icon!=null
	check(marked,"fighting player has sword before name")
	bounded(screen._standings,"standings");bounded(screen._round_panel,"round")
	await shot("feedback-"+lang+"-combat")
	# A finished home board must not supply the timer or opponent while scouting.
	c.game.home.phase=ArenaMatch.Phase.FINISHED;c.game.home.winner=0;c.game.home.world.time=15.0
	c.game.encounter(1).world.time=65.0;c.game.encounter(2).world.time=82.0
	c.game.run.company(2).gold=37
	c.game.run.pairings.assign([{"a":0,"b":1,"ghost":false},{"a":2,"b":3,"ghost":true}])
	c.view.apply_state(c.game.state_for(0,c._names()))
	online._show_player(1);await frames(20)
	check(screen._clock.text=="1:05 / 1:30" and screen._phase.text==RemakeText.t("Battle"),"spectator timer and phase follow an active rival after home finishes")
	check(screen._opponent.text==RemakeText.t("Opponent: %s")%"Worm" and screen._scout_name.text==c.view.player_title(1),"spectator shows watched owner and opponent")
	c.game.encounter(1).world.time=70.0;await frames(20)
	check(screen._clock.text=="1:10 / 1:30","spectated timer continues receiving time")
	online._show_player(2);await frames(20)
	check(screen._clock.text=="1:22 / 1:30" and screen._clock.get_theme_color("font_color")==Color("ff9377"),"switching boards changes timer and urgency")
	check(screen._opponent.text==RemakeText.t("Opponent: %s (copy)")%c.view.player_title(3),"watched ghost opponent is identified")
	check(screen._scout_details.is_visible_in_tree() and screen._scout_details.text==RemakeText.t("Level %d")%c.view.company(2).capacity()+" · "+RemakeText.t("%d gold")%37,"spectator sees watched player's level and gold")
	await shot("feedback-"+lang+"-spectator")
	c.game.encounter(2).phase=ArenaMatch.Phase.FINISHED;c.game.encounter(2).winner=1;await frames(20)
	check(screen._phase.text.begins_with(RemakeText.t("Defeat")) and screen._clock.modulate.a==1.0,"finished rival shows its result without timer pulse")
	online._show_player(0);await frames(20)
	check(screen._clock.text=="0:15 / 1:30" and screen._phase.text.begins_with(RemakeText.t("Victory")),"returning home restores own result and time")
	c.close();screen.queue_free();c.queue_free();screen=null;await frames(6)
	# Xvfb may lack a desktop mouse grab; actual script/render errors still fail.
	check(errors.messages.filter(func(message):return not message.begins_with("NO GRAB")).is_empty(),"no runtime/render errors: "+str(errors.messages))
	print("ARENA_ONLINE_FEEDBACK_UI ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
