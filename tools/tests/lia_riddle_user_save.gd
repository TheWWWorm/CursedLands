extends "lia_fragment_first_entry.gd"
## Supplied save stuck at the Wormfaces' Riddle, copied into an isolated
## profile: --supplied-save=/absolute/path.sav. The source is never written.

func run() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--supplied-save="): source = arg.trim_prefix("--supplied-save=")
	boot()
	check(FileAccess.file_exists(source),"supplied save exists")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(source,SaveInfo.path("riddle-supplied")) == OK,"copy save into disposable slot")
	check(await s.load_game_shown("riddle-supplied"),"load supplied save through Session")
	freeze()
	check(s.zone_id == "gz4h" and value("b.skelet.fq6") == 2 and value("q.gz4h.fq6") == 0,"supplied save is in the Wormface caves with the riddle accepted")
	check(not running("Start") and not running("VLever1#0#0"),"both one-shot riddle startup checks were already consumed")
	check(RIDDLE.all(func(id): return not s.world.levers[id].enabled and int(s.world.levers[id].state) == 0),"riddle levers were saved disabled and unpulled")
	ticks()
	check(levers_usable(RIDDLE),"riddle levers are usable after one script tick")
	solve_riddle("supplied save")
	await finish("LIA_RIDDLE_USER_SAVE","Supplied save copied to an isolated profile; repair on load, real lever use and chest. Hero moved to each lever by the fixture.")
