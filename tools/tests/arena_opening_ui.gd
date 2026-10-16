extends "arena_expansion_ui.gd"
## Final opening-only layout/framing pass after the functional rendered suite.
func _ready()->void:
	OS.add_logger(errors);await frames(24)
	GameData._window_gen+=1
	get_tree().root.mode=Window.MODE_WINDOWED
	var lang:="en";var dimensions:=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec:=arg.get_slice("=",1).split(",")
			lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size=dimensions;get_tree().root.position=Vector2i.ZERO;RemakeText.lang=lang
	await frames(8)
	screen=ArenaPveScreen.new();add_child(screen);await frames(24)
	bounded(screen._landing_panel,"opening")
	bounded(screen._landing_start,"begin action")
	var previews:=screen._landing_layer.find_children("*","WikiPreview",true,false)
	for preview:WikiPreview in previews:preview_fits(preview,"full native model")
	await shot("opening-%s-%d"%[lang,dimensions.x])
	screen._saved=true;screen._refresh();screen._seed_input.show();screen._layout_landing();await frames(12)
	bounded(screen._landing_panel,"resume and optional seed")
	bounded(screen._landing_start,"new expedition in expanded layout")
	# Presentation fixture: exercise result and camp layouts without claiming
	# that an artificial result is a native combat/balance measurement.
	screen._saved=false;screen._begin();screen.run.auto_save=false
	Fixture.buy_company(screen.run,0);screen.set_process(false)
	screen.run.wave=5;screen.run.start_battle()
	screen.battle.phase=ArenaMatch.Phase.FINISHED;screen.battle.winner=0
	screen.run.resolve(0,42,[35.0,5.0]);await frames(16)
	bounded(screen._outcome,"compact victory")
	check(is_equal_approx(screen._round_panel.size.y,44.0),"one-line wave badge fits its text")
	check(not screen._phase.visible and not screen._clock.visible,"empty round details take no space")
	check(not screen._outcome.decorated and not screen._outcome_shade.visible,"result has no border or background")
	check(screen._outcome.size.y<80,"victory uses two compact rows")
	await shot("compact-victory-%s-%d"%[lang,dimensions.x])
	screen.run.advance();await frames(12)
	bounded(screen._outcome,"camp after borderless notice")
	check(screen._outcome.decorated,"camp retains its decision panel")
	check(errors.messages.is_empty(),"no scene or script errors")
	print("ARENA_OPENING_UI ",checks," checks; failures=",JSON.stringify(failures)," errors=",JSON.stringify(errors.messages))
	get_tree().quit(0 if failures.is_empty() else 1)
