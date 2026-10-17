extends "arena_expansion_ui.gd"
## Regressions checked against the published 1.10.0 UI and live tournament boards.
class SoundScreen extends ArenaPveScreen:
	var started := {}
	func _play_cue(kind: String) -> void:
		super._play_cue(kind)
		started[kind] = _sound.mixer._chans.any(func(channel): return channel.snd.get("path", "").replace("\\", "/") == CUES[kind] and channel.player.playing)

func audible(path: String) -> bool:
	return screen._sound.mixer._chans.any(func(channel): return channel.snd.get("path", "").replace("\\", "/") == path and channel.player.playing)

func _ready() -> void:
	OS.add_logger(errors); await frames(24)
	GameData._window_gen += 1
	GameData.arena_mode = 0; GameData.arena_speed = 2
	GameData.options.merge({"confine_mouse":0, "auto_graphics":0}, true)
	get_tree().root.mode = Window.MODE_WINDOWED
	var lang := "en"; var dimensions := Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec := arg.get_slice("=",1).split(","); lang=spec[0]; dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size=dimensions; get_tree().root.position=Vector2i.ZERO; RemakeText.lang=lang
	await frames(8)
	screen=SoundScreen.new(); add_child(screen); await frames(20)
	var tag := "latest-%s-%d" % [lang,dimensions.x]
	var modes := screen._landing_panel.find_children("*Mode", "Button", true, false)
	check(modes.size()==2 and modes[0].size==modes[1].size, "mode tabs have identical dimensions")
	bounded(screen._landing_panel, "opening")
	await shot(tag+"-opening")
	screen._seed_input.text="7319"; screen._begin(); screen.run.auto_save=false
	for i in 3: screen._recruit_offer(i)
	await frames(12)
	check(screen.run.deployed_count()>0 and screen.selected_uid==0 and screen.field.ghost_id.is_empty(), "buy auto-deploys without entering placement")
	check(screen._speed.text==RemakeText.t("2×"), "new run preserves speed")
	screen.run.boons.append("reserve"); screen.run._recruit(2,0,1); screen.run._recruit(5,0,2); screen._refresh(); await frames(12)
	check(screen._army_row.get_child_count()==11, "all eleven extended reserve slots exist")
	for slot in screen._army_row.get_children(): bounded(slot, "reserve slot")
	check(not screen._bench_scroll.get_h_scroll_bar().visible, "reserve never scrolls horizontally")
	check(screen._bench_panel.get_theme_stylebox("panel") is StyleBoxEmpty,"reserves have no background")
	check(not screen._shop.find_children("OfferInfo","VBoxContainer",true,false).is_empty() and screen._shop.find_children("OfferInfo","PanelContainer",true,false).is_empty(),"prices and traits have no background")
	check(screen._army_row.get_child(0).size.y == screen._shop.get_child(0).size.y, "reserve and shop have matching heights")
	screen.run.gold=0; screen._refresh(); await frames(3)
	await click(screen._refresh_button.get_global_rect().get_center())
	check((screen as SoundScreen).started.get("reject", false), "failed reroll plays rejection sound")
	screen.run.gold=40; screen._refresh(); await frames(3)
	await click(screen._refresh_button.get_global_rect().get_center())
	check(audible("buttons/camp/buy.wav"), "successful reroll plays sound")
	await click(screen._train_button.get_global_rect().get_center())
	await click(screen._train_button.get_global_rect().get_center())
	check(screen._train_button.progress>=0 and audible("buttons/camp/perk.wav"), "level upgrade fills XP ring and plays sound")
	await move(point(body(screen.run.army[0].uid))); await get_tree().create_timer(0.4).timeout
	check(screen._inspector.visible, "creature hover opens inspector")
	var esc:=InputEventKey.new(); esc.keycode=KEY_ESCAPE; esc.pressed=true
	screen._unhandled_key_input(esc); await frames(2)
	check(not screen._modal_layer.visible and not screen._inspector.visible, "escape dismisses creature before menu")
	screen._show_menu(); await frames(8)
	var close:=screen._modal_box.find_child("CloseModal",true,false) as Button
	check(close.icon_alignment==HORIZONTAL_ALIGNMENT_CENTER and close.vertical_icon_alignment==VERTICAL_ALIGNMENT_CENTER, "close icon is centered")
	bounded(screen._modal_panel,"menu"); await shot(tag+"-menu")
	screen._close_modal(); await move(Vector2(500,400)); await shot(tag+"-reserves")
	check(screen.run.save(), "expedition saves with latest schema")
	screen.landing=true; screen._switch_mode(1); await frames(12)
	modes=screen._landing_panel.find_children("*Mode","Button",true,false)
	check(modes[0].size==modes[1].size, "mode dimensions stay equal after switching")
	screen._begin(); screen.run.auto_save=false
	var league:=screen.run as ArenaTournamentRun
	await get_tree().create_timer(1.6).timeout
	check(league.rivals.all(func(bot): return bot.army.size()>0), "all eight rivals recruit concurrently")
	check(league.rivals.any(func(bot): return bot.gold>0), "CPU preparation happens in steps")
	for player in range(1,9): check(not league.player_title(player).is_empty() and not league.player_title(player).contains("CPU"), "NPC player name")
	for i in 3: screen._recruit_offer(i)
	league.wave=4; league._prepare_round(); screen._refresh(); await frames(16)
	var opponent:=league.opponent_for(0)
	check(screen._opponent.visible and screen._opponent.text.contains(league.player_title(opponent)), "opponent named before combat")
	check(screen.battle.team_count(1)==0, "opponent copies wait until combat starts")
	screen._show_boards(); await frames(12)
	check(screen.field.showing_boards() and screen.battle.world.position==ArenaTournamentBattles.board_offset(0),"human board occupies the center of the 3 by 3 map")
	var offsets := {}
	for player in range(9): offsets[ArenaTournamentBattles.board_offset(player)] = true
	check(offsets.size()==9 and screen._tournament_battles.holders.values().all(func(holder):return holder.visible),"all nine live boards visible in overview")
	check(not screen._bench_panel.visible and not screen._shop_panel.visible,"board overview leaves map unobstructed")
	await shot(tag+"-all-boards")
	var board_point := screen.field.camera.unproject_position(ArenaTournamentBattles.board_offset(opponent)+Vector3(32,0,-32))
	await click(board_point); await frames(12)
	check(not screen.field.showing_boards() and screen._tournament_battles.viewed_player==opponent,"clicking a map cell focuses its live board")
	var watched:=screen.field.match_state
	check(watched==screen._tournament_battles.boards[opponent] and not screen._modal_layer.visible, "scouting switches to live board without modal pause")
	var total:=league.rivals.reduce(func(n,bot): return n+bot.gold,0)
	await get_tree().create_timer(2.0).timeout
	check(league.rivals.reduce(func(n,bot): return n+bot.gold,0)<total, "rivals keep buying while watched")
	check(screen.field.match_state==watched, "watching preserves board identity")
	check(screen._standings.get_global_rect().position.y>=screen._round_panel.get_global_rect().end.y+8,"standings clear the round panel")
	check(screen._standings.get_theme_stylebox("panel") is StyleBoxEmpty,"standings have no background")
	bounded(screen._standings,"compact standings"); check(screen._standings.size.x<=170,"compact standings width")
	await shot(tag+"-scouting")
	screen._standings_expanded=true; screen._build_standings(); await frames(6)
	bounded(screen._standings,"expanded standings"); await shot(tag+"-expanded")
	screen._standings_expanded=false; screen._build_standings(); screen._show_player(0)
	screen._fight(); await get_tree().create_timer(2.0).timeout
	check(screen.battle.team_count(1)>0,"opponent copies arrive on home board")
	check(screen._tournament_battles.boards.size()==8,"eight persistent CPU boards")
	check(screen._tournament_battles.boards.values().all(func(board):return board.phase!=ArenaMatch.Phase.DEPLOY),"all boards fight concurrently")
	screen._show_boards(); await get_tree().create_timer(0.7).timeout
	check(screen._tournament_battles.overview and screen._tournament_battles.holders.values().all(func(holder):return holder.visible),"overview stays live during combat")
	await shot(tag+"-all-battles")
	screen._show_player(0); await frames(5)
	check(screen._shop_panel.visible and league.can_shop(),"shop available during battle")
	var world_ids:=screen.battle.world.unit_rows().map(func(unit):return unit.get_instance_id())
	league.gold=40; league.shop[0]={"family":0,"rank":0,"locked":false}; screen._recruit_offer(0)
	check(screen.battle.world.unit_rows().map(func(unit):return unit.get_instance_id())==world_ids,"combat purchase preserves fighting figures")
	screen._show_player(opponent); await frames(12)
	check(screen.field.match_state.world.time>0,"scouted combat advances on native clock")
	await shot(tag+"-battle")
	screen._show_player(0); screen._show_menu(); await frames(4)
	var clocks:=screen._tournament_battles.boards.values().map(func(board):return board.world.time)
	await get_tree().create_timer(0.4).timeout
	check(clocks==screen._tournament_battles.boards.values().map(func(board):return board.world.time),"menu pauses every live board")
	screen._close_modal()
	check(league.save(),"live tournament saves")
	GameData.arena_mode=1;GameData.arena_speed=2;GameData.save_settings()
	screen.queue_free();await frames(12)
	check(is_equal_approx(Engine.time_scale,1.0),"exit restores game clock")
	check(errors.messages.is_empty(),"no native or script errors: "+JSON.stringify(errors.messages))
	print("ARENA_LATEST_UI ",tag," checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
