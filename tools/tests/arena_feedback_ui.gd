extends "arena_expansion_ui.gd"
## Pointer/keyboard interaction, complete notifications, persistent speed and both modes.
func key(code:Key)->void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed
		Input.parse_input_event(event);await frames(2)
func audible(path:String)->bool:
	return screen._sound.mixer._chans.any(func(channel):return channel.snd.get("path","")==path and channel.player.playing)
func _ready()->void:
	OS.add_logger(errors);await frames(24)
	GameData._window_gen+=1
	GameData.arena_mode=0;GameData.arena_speed=1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0},true)
	get_tree().root.mode=Window.MODE_WINDOWED
	var lang:="en";var dimensions:=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec:=arg.get_slice("=",1).split(",");lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size=dimensions;get_tree().root.position=Vector2i.ZERO;RemakeText.lang=lang
	await frames(8)
	screen=ArenaPveScreen.new();add_child(screen);await frames(20)
	var tag:="feedback-%s-%d"%[lang,dimensions.x]
	bounded(screen._landing_panel,"expedition opening")
	await shot(tag+"-opening")
	screen._saved=true;screen._refresh();screen._seed_input.show();screen._layout_landing();await frames(12)
	bounded(screen._landing_panel,"resume with seed expanded")
	bounded(screen._landing_start,"expanded start")
	screen._saved=false;screen._seed_input.text="7319";screen._begin();screen.run.auto_save=false
	# Interaction assertions need these particular recruits; the opening deal
	# deliberately changes when the recruit pool grows.
	screen.run.shop.clear()
	for family in 6: screen.run.shop.append({"family":family,"rank":0,"locked":false})
	screen._refresh(); await frames(12)
	for i in 3:
		var offer:=screen.run.shop.find_custom(func(row):return row.family==i)
		await click(screen._shop.get_child(offer).get_child(0).get_global_rect().get_center())
		check(screen.run.deployed_count()==i+1 and screen.selected_uid==0 and screen.field.ghost_id.is_empty(),"buy deploys without selecting placement")
	var reserve_offer:=screen.run.shop.find_custom(func(row):return row.family==3)
	await click(screen._shop.get_child(reserve_offer).get_child(0).get_global_rect().get_center())
	check(screen.run.bench_count()==1 and screen.selected_uid==0,"full army sends purchase to reserves without selecting")
	await move(get_viewport().get_visible_rect().size*Vector2(.98,.5));await frames(12)
	var shop_card:=screen._shop.get_child(screen.run.shop.find_custom(func(row):return row.family>=0)).get_child(0) as Control
	var reserve_card:=screen._army_row.get_child(0) as Control
	check(is_equal_approx(shop_card.size.y,reserve_card.size.y) and absf(shop_card.size.x-reserve_card.size.x)<=1,"reserve cards match shop width and height")
	for i in 100:
		if screen.battle.formation_motion.movers.is_empty():break
		await get_tree().create_timer(.05).timeout
	var uid:=int(screen.run.army[2].uid)
	var actor:=body(uid)
	var marker:Control=screen.field._unit_markers.get(actor.get_instance_id())
	check(marker!=null,"deployed creature has a retained health marker")
	if marker:
		var redraws:=[0]
		marker.draw.connect(func():redraws[0]+=1)
		var old_yaw:=screen.field.yaw
		var old_position:=marker.position
		screen.field.yaw+=0.2;screen.field._update_camera();await frames(4)
		check(marker.position.distance_to(old_position)>1 and redraws[0]==0,"camera movement repositions health text without rebuilding its canvas commands")
		var health:=actor.hp
		actor.hp*=0.5;await frames(3)
		check(redraws[0]>0,"taking damage refreshes the retained health marker")
		actor.hp=health;actor.dead=true;await frames(3)
		check(not screen.field._unit_markers.has(actor.get_instance_id()) and not is_instance_valid(marker),"dead creature releases its marker")
		actor.dead=false;screen.field.yaw=old_yaw;screen.field._update_camera();await frames(3)
		check(screen.field._unit_markers.has(actor.get_instance_id()),"revived creature gets current health and rank again")
	await move(point(body(uid)));await get_tree().create_timer(.4).timeout
	check(screen._rail.visible,"hover opens creature details")
	await key(KEY_ESCAPE)
	check(not screen._modal_layer.visible and not screen._rail.visible,"Escape dismisses hover without opening menu")
	await get_tree().create_timer(.4).timeout
	check(not screen._rail.visible,"dismissed hover stays closed while pointer stays still")
	await key(KEY_ESCAPE);check(screen._modal_layer.visible,"next Escape opens menu")
	await key(KEY_ESCAPE);check(not screen._modal_layer.visible,"Escape closes menu")
	if screen._modal_layer.visible: screen._close_modal()
	await move(get_viewport().get_visible_rect().size*Vector2(.98,.5));await frames(4)
	screen.run.gold=30;screen.run.training=0;screen._refresh()
	screen._train_button.pressed.emit()
	check(screen.run.capacity()==3 and screen.run.training==5 and audible("buttons\\camp\\buy.wav"),"XP purchase below a level also plays a sound")
	screen._train_button.pressed.emit()
	check(screen.run.capacity()==4 and audible("buttons\\camp\\perk.wav"),"level increase plays original sound")
	check(is_equal_approx(screen._train_button.progress,float(screen.run.level_progress())/screen.run.level_needed()),"XP ring follows exact progress")
	screen._refresh_button.pressed.emit()
	check(audible("buttons\\camp\\buy.wav"),"successful reroll plays original sound")
	# One complete two-model comparison. Hover does not hide it or consume its space.
	screen._evolution_notice.present([{"uid":uid,"from":"boarredf1","to":"boarredf3","old_rank":0,"rank":1}])
	await get_tree().create_timer(.4).timeout
	var notice:=screen._evolution_notice
	check(notice._ready_to_show and notice.modulate.a==1 and notice._previews.size()==2,"notice appears only with both framed models")
	check(notice.position.x==24 and notice.position.y>=screen._alliance_panel.position.y+screen._alliance_panel.size.y,"notice sits under alliances on left")
	for label:Label in notice.find_children("*","Label",true,false):check(not label.text.contains("%d"),"notice formats all numbers")
	for preview in notice._previews:preview_fits(preview,"evolution model")
	await move(point(body(uid)));await get_tree().create_timer(.35).timeout
	check(screen._rail.visible and notice.modulate.a==1 and not notice.get_global_rect().intersects(screen._rail.get_global_rect()),"notice coexists with hover on opposite side")
	await shot(tag+"-evolution")
	notice.clear();screen._clear_selection();await move(get_viewport().get_visible_rect().size*Vector2(.98,.5))
	# This global preference survives a run restore, new run, mode switch and a fresh screen.
	screen._speed.pressed.emit()
	check(GameData.arena_speed==2 and screen.battle.speed==2 and screen._speed.text==RemakeText.t("2×"),"one click toggles to double speed")
	var cfg:=ConfigFile.new();cfg.load(GameData.CONFIG_PATH)
	check(cfg.get_value("arena","battle_speed")==2,"speed is written to player settings")
	var saved:=screen.run.snapshot();screen.run.restore(saved);screen._refresh()
	check(screen.battle.speed==2 and screen._speed.text==RemakeText.t("2×"),"old run reload preserves speed preference")
	check(screen.run.save(),"expedition fixture saves")
	var expedition:=FileAccess.get_file_as_string(ArenaRun.SAVE_PATH)
	screen.landing=true;screen._saved=true;screen._refresh();await frames(12)
	await click(screen._landing_panel.find_child("AutochessMode",true,false).get_global_rect().get_center());await frames(20)
	check(screen.run is ArenaTournamentRun and not screen._challenge.visible,"second mode is available without expedition difficulty")
	bounded(screen._landing_panel,"autochess opening")
	await shot(tag+"-autochess-opening")
	screen._seed_input.text="7321";screen._begin();screen.run.auto_save=false
	check(screen.battle.speed==2 and screen._speed.text==RemakeText.t("2×"),"new mode and new run retain double speed")
	if not screen.run is ArenaTournamentRun:
		print("ARENA_FEEDBACK_UI mode switch failed; failures=",JSON.stringify(failures));get_tree().quit(1);return
	var league:=screen.run as ArenaTournamentRun
	ArenaTournamentRun.shop_for(league,1,league.wave,league.lives)
	league.wave=4;league._roll_shop(false);league._prepare_round();league._touch();await frames(24)
	check(league.rivals.size()==8 and screen._standing_rows.find_children("*","Button",true,false).size()==11,"standings show human plus eight CPUs and board controls")
	bounded(screen._standings,"standings")
	check(screen._wave_title.text==RemakeText.t("Round %d")%4 and screen._lives.text=="100","classic HUD shows rounds and health")
	await shot(tag+"-autochess")
	screen._show_boards();await frames(4)
	check(screen.field._unit_markers.is_empty(),"overview releases the single-board health markers")
	check(screen.field._board_headers.size()==9,"overview labels every board")
	var header:Control=screen.field._board_headers[0]
	var header_draws:=[0]
	var clock_changes:=[0]
	header.draw.connect(func():header_draws[0]+=1)
	screen._clock.theme_changed.connect(func():clock_changes[0]+=1)
	await frames(6)
	check(header_draws[0]==0,"unchanged board labels retain their canvas commands")
	check(clock_changes[0]==0,"stable countdown does not invalidate its theme every frame")
	var preparation_left:=league.preparation_left
	hold_preparation=false
	league.preparation_left=9;await frames(3)
	check(screen._clock.get_theme_color("font_color")==Color("ff9377") and screen._clock.get_theme_constant("outline_size")==2,"urgent countdown still gains its warning style")
	league.preparation_left=preparation_left;await frames(3)
	hold_preparation=true
	check(screen._clock.get_theme_color("font_color")==screen.GOLD and screen._clock.get_theme_constant("outline_size")==0,"normal countdown restores its style")
	var original_lives:=league.lives
	league.lives=37;await frames(3)
	check(header_draws[0]>0 and header.state[2]=="37","overview refreshes current player health")
	league.lives=original_lives
	screen._show_player(int(league.pairings[0].b));await frames(24)
	check(screen.field._board_headers.values().all(func(h):return not h.visible),"scouting hides every overview label")
	check(not screen.field._unit_markers.is_empty(),"scouting restores health markers for the viewed army")
	bounded(screen._modal_panel,"scouting")
	await shot(tag+"-scouting")
	screen._close_modal();screen._guide();await frames(12)
	bounded(screen._modal_panel,"classic guide");screen._close_modal()
	check(league.save() and FileAccess.get_file_as_string(ArenaRun.SAVE_PATH)==expedition,"classic saves cannot overwrite expedition")
	screen.landing=true;screen._saved=true;screen._refresh();await frames(12)
	screen._switch_mode(0);await frames(12)
	check(screen._saved and not screen.run is ArenaTournamentRun,"mode switch finds old expedition save")
	screen._switch_mode(1);await frames(12)
	check(screen._saved and screen.run is ArenaTournamentRun and screen.run.wave==4,"mode switch finds separate classic save")
	screen.landing=false;screen.run.auto_save=false;screen._refresh();await frames(16)
	screen._fight()
	var start_deadline := Time.get_ticks_msec() + 20000
	while screen.run.stage == "prepare" and Time.get_ticks_msec() < start_deadline:
		await frames()
	check(screen.run.stage=="fight" and screen._speed.visible and screen._speed is Button,"combat uses a speed toggle")
	await shot(tag+"-speed")
	screen._show_menu();await frames(4)
	await get_tree().create_timer(.3).timeout
	var paused_time := screen.battle.world.time
	await frames(12)
	check(screen._modal_layer.visible and screen.battle.world.time == paused_time,"menu pauses current classic board")
	screen._close_modal()
	screen.battle.set_process(false)
	screen.battle.world.set_process(false);screen.battle.world.set_physics_process(false)
	screen.battle.phase=ArenaMatch.Phase.FINISHED;screen.battle.winner=0;screen.battle.settle_remaining=0
	screen.run.resolve(0,10,[10,0],[3,0])
	for player in screen.run.alive_players():
		if not screen.run.board_results.has(player):screen.run.record_board(player,0,[3,0])
	await frames(6)
	check(screen.run.stage == "result" and not screen._outcome.visible and screen._standings.visible,"round result preserves standings and uses the top notification")
	bounded(screen._outcome,"classic result")
	await shot(tag+"-result")
	screen.queue_free();await frames(4)
	check(is_equal_approx(Engine.time_scale,1.0),"leaving both boards restores normal menu speed")
	check(errors.messages.is_empty(),"no scene or script errors")
	print("ARENA_FEEDBACK_UI ",checks," checks; failures=",JSON.stringify(failures)," errors=",JSON.stringify(errors.messages))
	get_tree().quit(0 if failures.is_empty() else 1)
