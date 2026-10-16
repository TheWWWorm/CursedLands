extends "arena_expansion_ui.gd"
## Readable pact benefit/requirements and shared model retention after purchases.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	get_tree().root.mode=Window.MODE_WINDOWED
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):lang=arg.get_slice("=",1).get_slice(",",0)
	get_tree().root.size=Vector2i(1024,768);get_tree().root.position=Vector2i.ZERO
	RemakeText.lang=lang
	await frames(8)
	screen=ArenaPveScreen.new();add_child(screen);await frames(16)
	screen._seed_input.text="1941";screen._begin();screen.run.auto_save=false
	Fixture.buy_company(screen.run,1)
	screen._hint("")
	screen.run.wave=3;screen.run.stage="fight";screen.run.resolve(0,20,[40,10]);screen.run.advance()
	await frames(15)
	bounded(screen._outcome,"pact choices")
	for label: Label in screen._dock.find_children("*","Label",true,false):
		check(screen._outcome.get_global_rect().grow(1).encloses(label.get_global_rect()),"pact choice text remains inside frame")
	await shot("pact-"+lang+"-choices")
	var chosen:=screen.run.choose_reward(0)
	check(chosen.is_empty(),"choose active beast pact")
	await frames(15)
	await move(screen._pact_hint.get_global_rect().get_center());await get_tree().create_timer(0.4).timeout
	bounded(screen._rail,"pact hover")
	check(screen._showing_company and screen._rail.visible,"pact hover opens")
	var ally_visible:=false
	for label:Label in screen._inspect_box.find_children("*","Label",true,false):
		if label.text==ArenaRules.title(screen.run.pact_prototype()):
			ally_visible=screen._rail.get_global_rect().encloses(label.get_global_rect())
	check(ally_visible,"summoned ally name is readable without scrolling")
	await shot("pact-"+lang+"-active")
	await move(Vector2(600,400));await get_tree().create_timer(0.3).timeout
	# One missing family and one merely waiting in reserves have distinct feedback.
	screen.run.bench(screen.run.army[1].uid)
	await frames();await move(screen._pact_hint.get_global_rect().get_center());await get_tree().create_timer(0.4).timeout
	check(screen._pact_hint.text==RemakeText.t("Pact %d/%d") % [2,3],"withdrawing one family updates visible pact progress")
	check(not screen.run.pact_active() and screen.battle.team_count(0)==2,"inactive pact removes guest")
	await shot("pact-"+lang+"-inactive")
	await move(Vector2(600,400));await get_tree().create_timer(0.3).timeout
	screen.run.gold=30;screen._refresh();await frames(12)
	var targets: Dictionary={}
	var buying:=-1
	for index in screen.run.shop.size():
		if screen.run.purchase_error(index).is_empty():buying=index;break
	for index in screen.run.shop.size():
		var card:=screen._shop.get_child(index).get_child(0) as ArenaCreatureCard
		if card and index!=buying:targets[index]=card.preview.creature._vp.get_instance_id()
	await click(screen._shop.get_child(buying).get_child(0).get_global_rect().get_center())
	for index in targets:
		var card:=screen._shop.get_child(index).get_child(0) as ArenaCreatureCard
		check(card.preview.creature._vp.get_instance_id()==targets[index],"purchase retains other offer render targets")
	var speed := Engine.time_scale
	Engine.time_scale = 2.0
	screen.run.preparation_left = 20
	screen._process(2.0)
	check(is_equal_approx(screen.run.preparation_left, 19.0), "preparation uses real time even at double combat speed")
	Engine.time_scale = speed
	screen.queue_free();await frames(8)
	check(errors.messages.is_empty(),"no script/render errors: "+JSON.stringify(errors.messages))
	print("ARENA_PACT_UI ",checks," checks; failures=",JSON.stringify(failures))
	OS.remove_logger(errors);get_tree().quit(0 if failures.is_empty() else 1)
