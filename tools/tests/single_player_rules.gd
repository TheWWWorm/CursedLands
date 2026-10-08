extends Node
## The local worker's transport must not select multiplayer gameplay rules.
var checks := 0
var failures := 0

class ProbeSession extends Session:
	var events: Array = []
	func broadcast(event: Dictionary) -> void: events.append(event)
	func sync_state() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func hero(w: GameWorld, id: int, merc := false) -> GameUnit:
	var u := GameUnit.new()
	u.uid = id; u.controller = 0; u.world = w
	var record := {"exp":0.0,"exp_total":0.0,"exp_debt":0.0,
		"int":25.0,"str":25.0,"dex":25.0,"perks":[]}
	if merc: record.merc = 2
	u.set_meta("hero", record)
	w.set_unit(id, u)
	return u

func _ready() -> void:
	GameData.options.merge({"sp_full_xp":0,"coop_full_xp":1,"unit_fog":0,"coop_clock":1},true)
	GameData.difficulty = 1
	var original: Array = []
	for mode: String in ["inline", "single_worker", "coop"]:
		var s := ProbeSession.new()
		var w := GameWorld.new()
		var host := LocalHost.new()
		s.local_host = host; host.session = s
		s.online = mode != "inline"
		host.single_player = mode == "single_worker"
		s.world = w; w.session = s
		s.state = CampaignState.new()
		var main := hero(w, 1500000001)
		var merc := hero(w, 1500000002, true)
		var enemy := GameUnit.new()
		enemy.uid = 42; enemy.world = w
		var combat := Combat.new(w)
		var expected_xp := 100.0 if mode == "coop" else 50.0
		for source: String in ["kill", "quest", "talk", "side"]:
			var before := float(main.get_meta("hero").exp_total)
			XpRules.give(s, 100.0, source)
			check(main.get_meta("hero").exp_total - before == expected_xp, mode + " hero XP " + source)
			check(merc.get_meta("hero").exp_total == main.get_meta("hero").exp_total, mode + " companion XP " + source)
		var observed := []
		for key: String in ["Attack", "Defence", "Absorption"]:
			var factor := combat.difficulty(enemy, key)
			observed.append(factor)
			check(is_equal_approx(factor, 1.0 if mode == "coop" else GameData.ai_value("DifficultyLevels",key,1.0,1)), mode + " difficulty " + key)
		if mode == "inline": original = observed
		elif mode == "single_worker": check(observed == original, "worker preserves offline difficulty")
		check(UnitFog.sight_active(s) == (mode == "coop"), mode + " honors optional single-player fog")
		check(s.coop_clock_enabled() == (mode == "coop"), mode + " selects correct clock")
		check(not s.sp_main_hero_dead(), mode + " live main hero")
		main.dead = true
		check(s.sp_main_hero_dead() == (mode != "coop"), mode + " main hero death rule")
		check(s.sp_game_over() == (mode != "coop"), mode + " dead hero blocks travel")
		check(s.events.any(func(ev): return ev.t == "game_over") == (mode != "coop"), mode + " death sends single-player game-over event")
		w.units = {}; main.free(); merc.free(); enemy.free(); w.free(); host.free(); s.free()
	print("SINGLE_PLAYER_RULES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
