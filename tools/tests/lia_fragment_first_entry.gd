extends "lia_kel_support.gd"
## Fortune and Rod-fragment maps entered through their own WorldScript.
## lia_kel_suslanger/gipat/ingos clear the startup threads and start only the
## quest watchers, so a startup script that undoes an already accepted quest
## on the first visit cannot show there. The Wormfaces' Riddle did exactly
## that: with the last fortune bought before the first Wormface cave visit,
## Start disabled the three levers after VLever1#0#0 had enabled them.

func _ready() -> void: run.call_deferred()

func levers_usable(ids: Array) -> bool:
	return ids.all(func(id): return s.world.lever_sys.usable(id))

const RIDDLE := [16426,1047355,1088298]

## Correct 3-1-2 answer, revealed chest, first fragment.
func solve_riddle(label: String) -> void:
	use(1088298); use(16426); use(1047355); ticks(5)
	check(value("CaveLever") == 5000,label+": 3-1-2 order resolves the riddle")
	var chest: Node3D = s.world.objects.get(33345906)
	check(chest != null and Vector2(chest.get_meta("ei").position.x,chest.get_meta("ei").position.y).distance_to(Vector2(202,52)) < 0.01,
		label+": correct answer reveals the fragment chest")
	use(33345906)
	check(value("q.gz4h.fq6") == 2 and s.state.quest_items.has("kel1"),label+": revealed chest grants the first Rod fragment")

func run() -> void:
	boot()
	# The Wormface caves open with the elder's q19h. The last fortune is
	# bought from the fortune-teller before the first cave visit.
	for key: String in ["b.skelet.fq2","b.skelet.fq3","b.skelet.fq4","b.skelet.fq5","b.skelet.fq6"]:
		s.state.set_var(0,key,2)
	for key: String in ["q.gz1h.fq2","q.gz2h.fq3","q.gz1h.fq4","q.gz2h.fq5"]:
		s.state.set_var(0,key,2)
	s.state.set_var(0,"q.gz4h.q19h",1)
	await visit("gz4h")
	check(not running("Start") and not running("VLever1#0#0"),"both one-shot riddle startup checks ran on the first visit")
	check(value("q.gz4h.q19h.1") == 1,"first visit still starts the elder's cave quest")
	check(levers_usable(RIDDLE),"fortune bought before the first visit leaves all three riddle levers usable")
	await roundtrip("lia_riddle_first_visit",["q.gz4h.q19h.1"])
	check(levers_usable(RIDDLE),"riddle levers stay usable after save/reload")
	check(vm().ast.has_meta(&"wormface_riddle"),"shipped riddle scripts are recognized")
	# Saves made before the repair: both checks consumed, levers disabled.
	for id: int in RIDDLE: s.world.levers[id].enabled = false
	check(s.save_game("lia_riddle_stuck") == OK and await s.load_game_shown("lia_riddle_stuck"),"reload a riddle left with disabled levers")
	freeze()
	check(not levers_usable(RIDDLE) and not running("Start") and not running("VLever1#0#0"),"stuck riddle state is restored as saved")
	ticks()
	check(levers_usable(RIDDLE),"stuck riddle levers are released on the next script tick")
	solve_riddle("fortune before first visit")
	await roundtrip("lia_riddle_first_visit_solved",["q.gz4h.fq6","CaveLever"],["kel1"])

	# Ordinary order: first visit without the fortune, buy it, revisit.
	await boot_again()
	s.state.set_var(0,"q.gz4h.q19h",1)
	await visit("gz4h")
	check(not levers_usable(RIDDLE),"without the last fortune the riddle levers stay disabled")
	check(running("VLever1#0#0"),"riddle waits for the last fortune")
	await enter_away("gz3h")
	s.state.set_var(0,"b.skelet.fq6",2)
	await visit("gz4h")
	check(levers_usable(RIDDLE),"fortune bought after the first visit enables the riddle on return")
	solve_riddle("fortune after first visit")

	# A wrong answer is final in the original: the levers stay pulled.
	await boot_again()
	s.state.set_var(0,"b.skelet.fq6",2)
	s.state.set_var(0,"q.gz4h.q19h",1)
	await visit("gz4h")
	use(16426); use(1047355); use(1088298); ticks(5)
	check(value("CaveLever") == 5000 and value("q.gz4h.fq6") == 0,"wrong 1-2-3 order consumes the riddle without the fragment")
	await enter_away("gz3h"); await visit("gz4h")
	check(not levers_usable(RIDDLE) and not s.state.quest_items.has("kel1"),"repair does not reopen an answered riddle")

	# Second fragment: Uyka's crypt key bought before or after the first
	# Hall of the Great visit.
	for early: bool in [true, false]:
		var label := "crypt key before first visit" if early else "crypt key after first visit"
		await boot_again()
		await enter_away("gz11g")
		if early: crypt_key()
		await visit("gz11d1")
		if not early:
			use(1712,false)
			check(int(s.world.levers[1030051].state) == 0,label+": crypt door stays closed without the key")
			await enter_away("gz11g"); crypt_key(); await visit("gz11d1")
		use(1712)
		check(int(s.world.levers[1030051].state) == 1,label+": key opens the crypt door")
		use(4357253)
		check(value("q.gz11d1.fq13") == 2 and s.state.quest_items.has("kel2"),label+": crypt chest grants the second Rod fragment")

	# Third fragment: Khabburu's mine key granted before or after the
	# first visit to the mine.
	for early: bool in [true, false]:
		var label := "mine key before first visit" if early else "mine key after first visit"
		await boot_again()
		await enter_away("bz23k")
		if early: mine_key()
		await visit("gz24k")
		if not early:
			use(4374,false)
			check(value("q.gz24k.fq19") == 0,label+": mine route stays locked without the key")
			await enter_away("bz23k"); mine_key(); await visit("gz24k")
		for pair: Array in [[4374,4555],[14357306,4305],[14357307,4301]]:
			use(pair[0])
			check(int(s.world.levers[pair[1]].state) == 1,label+": key opens route door "+str(pair[1]))
		var money := s.state.money
		use(4367); ticks(8)
		check(s.state.quest_items.has("kel3") and value("q.gz24k.fq19") == 2 and s.state.money == money+70000,
			label+": mine chest grants the third Rod fragment once")
	await finish("LIA_FRAGMENT_FIRST_ENTRY","Fortune and Rod-fragment maps entered through their authored WorldScript in both purchase orders; real lever use, chest, save/reload and revisit. Quest flags before the visit are supplied; travel is direct map entry.")

## The original briefing rewards rather than an invented key.
func crypt_key() -> void:
	s.state.money = maxi(s.state.money,500)
	vm().briefings._rewards("fq13")
	check(s.state.quest_items.has("ambushkey04"),"thirteenth fortune grants the original crypt key")

func mine_key() -> void:
	s.state.set_var(0,"b.Haburu.fq19",2)
	vm().briefings._rewards("fq19")
	check(s.state.quest_items.has("kkey07"),"final Khabburu briefing grants the original mine key")
