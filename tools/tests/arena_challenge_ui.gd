extends "arena_expansion_ui.gd"
class InlineScreen extends ArenaPveScreen:
	func _create_boards() -> ArenaTournamentBattles: return ArenaTournamentBattles.new()
func _ready() -> void:
	OS.add_logger(errors); await frames(12)
	GameData._window_gen+=1; GameData.arena_mode=1; GameData.options.confine_mouse=0
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): lang=arg.trim_prefix("--lang=")
	RemakeText.lang=lang
	get_window().mode=Window.MODE_WINDOWED; get_window().size=Vector2i(1280,800)
	screen=InlineScreen.new(); add_child(screen); await frames(12)
	screen._seed_input.text="7319"; screen._begin(); screen.run.auto_save=false
	screen.run.gold=60; screen.run.training=90
	for pair in [[0,2],[1,1],[2,1],[4,2],[5,1],[12,0],[24,0]]:
		screen.run._recruit(pair[0],pair[1],9)
	screen.run.arrange(); screen.run.shop.clear()
	for family in [0,2,5,24,18]: screen.run.shop.append({"family":family,"rank":0,"locked":false})
	screen._refresh()
	for i in 360:
		await frames(1)
		if screen._shop.get_children().all(func(box):return not box.get_child(0)._preview_pending): break
	await frames(16)
	check(screen.battle.time_limit()==90.0,"90 second battle limit")
	for card in screen._shop.get_children(): check(card.get_child(0).cost<=5,"shop costs at most five gold")
	for entry in screen.run.army: check(ArenaPortraits.texture(entry.prototype)!=null,"native portrait exists")
	for unit: GameUnit in screen.battle.world.unit_rows():
		check(EnemyBars.head_top(unit)<5.0,"large native figures fit the challenge board")
	screen._round_banner._age=10; await shot("challenge-"+lang+"-prepare")
	var press := InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_RIGHT; press.pressed=true
	screen.field._gui_input(press)
	var drag := InputEventMouseMotion.new(); drag.relative=Vector2(50,45); drag.button_mask=MOUSE_BUTTON_MASK_RIGHT
	screen.field._gui_input(drag); press.pressed=false; screen.field._gui_input(press)
	check(screen.field.pitch_offset>0.1,"right drag changes pitch")
	var pose := [screen.field.yaw,screen.field.pitch_offset,screen.field.zoom,screen.field.pan_offset]
	screen._show_player(0)
	check(pose==[screen.field.yaw,screen.field.pitch_offset,screen.field.zoom,screen.field.pan_offset],"return to own board preserves camera")
	screen.field.reset_camera()
	for i in screen.run.army.size(): screen.battle.friendly_damage[int(screen.run.army[i].uid)]=float((7-i)*121)
	screen.run.stage="fight"; screen.battle.phase=ArenaMatch.Phase.FIGHT; screen._refresh(); await frames(12)
	await shot("challenge-"+lang+"-battle")
	check(screen._damage_panel.rows.size()==7,"friendly damage roster contains only owned units")
	screen.run.stage="result"; screen.battle.phase=ArenaMatch.Phase.FINISHED; screen.battle.winner=0; screen.run.last_result={"winner":0,"gold":12,"income":{"base":5,"interest":5,"victory":1,"streak":1,"total":12},"health_lost":0}
	screen.set_process(false); screen._round_banner.update_round(screen.run,0.1,4,false)
	await shot("challenge-"+lang+"-victory")
	screen.battle.winner=1; screen.run.last_result.winner=1; screen.run.last_result.health_lost=12
	screen._battle_changed()
	screen._round_banner.update_round(screen.run,0.1,4,false)
	await shot("challenge-"+lang+"-defeat")
	screen.run.wave=2; screen.run.stage="prepare"; screen._round_banner.update_round(screen.run,0.1,4,false)
	await shot("challenge-"+lang+"-income")
	hold_preparation=false; screen.run.preparation_left=7; screen._round_banner.update_round(screen.run,0.1,4,false)
	await shot("challenge-"+lang+"-countdown")
	for control in [screen._battle_sidebar,screen._round_banner]: bounded(control,"challenge panel")
	check(errors.messages.is_empty(),"no engine errors: "+str(errors.messages))
	print("ARENA_CHALLENGE_UI ",checks," checks; failures=",JSON.stringify(failures))
	screen.queue_free(); screen=null; await frames(3)
	get_tree().quit(0 if failures.is_empty() else 1)
