extends Node
const Fixture = preload("arena_fixture.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func _ready() -> void:
	var run := ArenaRun.new()
	run.auto_save = false
	run.begin(1901)
	check(run.preparation_left == 60, "opening gives 60 seconds")
	check(not run.elapse_preparation(12.5) and run.preparation_left == 47.5, "clock advances without starting early")
	run.elapse_preparation(-3)
	check(run.preparation_left == 47.5, "negative delta cannot add time")
	var saved := run.snapshot()
	var resumed := ArenaRun.new()
	resumed.auto_save = false
	check(resumed.restore(JSON.parse_string(JSON.stringify(saved))) and resumed.preparation_left == 47.5, "save retains exact countdown")
	for value in [-1, 61, INF, NAN, "60"]:
		var invalid := saved.duplicate(true); invalid.preparation_left = value
		check(not resumed.restore(invalid), "invalid clock rejected")
	var legacy := saved.duplicate(true); legacy.version = 6; legacy.pact = ""; legacy.pact_rank = 0; legacy.erase("preparation_left")
	check(resumed.restore(legacy) and resumed.preparation_left == 45, "older saves get full preparation time")
	var bought := run.buy(0)
	check(bought.is_empty() and run.preparation_left == 47.5, "recruit does not reset timer")
	run.elapse_preparation(3); run.undo()
	check(run.preparation_left == 44.5 and run.army.is_empty(), "undo never refunds elapsed time")
	check(not run.start_battle().is_empty(), "manual start still rejects empty army")
	check(not run.start_battle(true).is_empty(), "cannot forfeit before timeout")
	var battle := ArenaPveMatch.new()
	battle.run = run; battle.rendered = false
	add_child(battle); battle.set_process(false); battle._world_parent = self
	battle.prepare(); battle.expire_preparation()
	check(run.stage == "prepare", "early expiry request is ignored")
	check(run.elapse_preparation(60) and run.preparation_left == 0, "clock clamps at zero")
	battle.expire_preparation()
	check(run.stage == "result" and run.lives == 2 and run.last_result.empty_army, "unrecruited company forfeits exactly one life")
	battle.expire_preparation()
	check(run.lives == 2, "expiry cannot repeat after resolution")
	run.advance()
	check(run.stage == "prepare" and run.preparation_left == 60, "next wave resets preparation after a loss")
	run.shop = [{"family": 0, "rank": 0, "locked": false}, {"family": 2, "rank": 0, "locked": false}, {"family": 4, "rank": 0, "locked": false}, {"family": 1, "rank": 0, "locked": false}, {"family": 3, "rank": 0, "locked": false}]
	# Boar, wolf and bat are three distinct Beast families. Composition 1
	# contains a goblin after the species roster migration.
	Fixture.buy_company(run, 0)
	check(run.alliances().beast == 3,"fixture begins with three distinct deployed Beasts")
	for entry in run.army: entry.deployed = false
	battle.prepare(); run.elapse_preparation(60); battle.expire_preparation()
	check(run.stage == "fight" and run.deployed_count() == 3 and battle.phase == ArenaMatch.Phase.FIGHT, "timeout deploys reserves on an empty field and starts combat")
	check(run.preparation_left == 0 and not run.elapse_preparation(9), "combat does not advance preparation clock")
	check(resumed.restore(run.snapshot()) and resumed.stage == "prepare" and resumed.preparation_left == 60, "interrupted combat restores a full planning round")
	run.resolve(0, 1, [1,0]); run.advance()
	check(run.wave == 3 and run.preparation_left == 60, "next wave resets preparation")
	battle.prepare()
	var bodies := {}
	for unit in battle.world.unit_rows(): bodies[unit.get_instance_id()] = unit
	var uid := int(run.army[0].uid)
	var moved := run.deploy(uid, Vector2(29,39))
	check(moved.is_empty(), "formation move accepted")
	battle.prepare()
	for unit in battle.world.unit_rows():
		check(bodies.has(unit.get_instance_id()), "preparation retains native actor identity")
		check(battle.world.nav.registered_units.has(unit.get_instance_id()), "retained actor remains registered for navigation")
		if int(unit.get_meta("arena_placement",{}).get("run_uid",0)) == uid:
			check(unit.pos == Vector2(29,39), "moved actor updates position in place")
	var terrain := battle.world.terrain
	for x in range(19,46,2):
		for y in range(19,46,2): check(is_zero_approx(terrain.height_at(x,y)), "battlefield footing stays flat")
	run.wave = 5; run.stage = "fight"; run.resolve(0,1,[1,0]); run.advance()
	var clock := run.preparation_left
	check(run.stage == "reward" and not run.elapse_preparation(100) and run.preparation_left == clock, "camp choices are untimed")
	var reward := run.choose_reward(0)
	check(reward.is_empty() and run.preparation_left == 60, "leaving camp starts a fresh countdown")
	check(run.alliances().beast == 3, "deployed lineup retains automatic alliance progress")
	battle.queue_free()
	print("ARENA_FLOW ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
