extends Node
const Fixture = preload("arena_fixture.gd")
## Regression checks for automatic recipes, shop progression and the opening AI.
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr('FAIL ',label)
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := ArenaRun.new()
	run.auto_save = false
	Fixture.begin(run, 6519, 1)
	var wolf: Dictionary = run.army[1]
	var uid := int(wolf.uid)
	var position: Array = wolf.point.duplicate()
	run.gold = 60
	run.shop = [{'family':2,'rank':0,'locked':false},{'family':2,'rank':0,'locked':false},{'family':-1,'locked':false},{'family':-1,'locked':false},{'family':-1,'locked':false}]
	check(run.buy(0).is_empty() and run.unit(uid).rank == 0,'second wolf stays a separate form')
	var before := run.snapshot()
	check(run.buy(1).is_empty(),'third wolf can be purchased in wave one')
	check(run.wave == 1 and run.unit(uid).prototype == 'wolfgreyf3','wave-one wolves evolve automatically')
	check(run.unit(uid).deployed and run.unit(uid).point == position,'evolution preserves deployed identity and placement')
	check(run.unit(uid).investment == 9 and run.army.size() == 3,'evolution retains cost and consumes exactly three')
	run.undo()
	check(run.snapshot() == before,'undo reverses purchase and its automatic evolution together')
	run.buy(1)
	# Completing a first-tier recipe also completes an existing second-tier one.
	run._recruit(2,1,9); run._recruit(2,1,9)
	run.combine_ready()
	check(run.unit(uid).prototype == 'wolfwhitef6' and run.unit(uid).deployed,'final evolution is also available in wave one')
	var restored := ArenaRun.new()
	restored.auto_save = false
	check(restored.restore(run.snapshot()) and restored.snapshot() == run.snapshot(),'early final forms round-trip through saves')
	Fixture.begin(run, 12,1)
	uid = int(run.army[1].uid)
	run._recruit(2,0,3)
	for i in 5: run._recruit(-1,0,9,'orcfemalem3')
	run.shop[0] = {'family':2,'rank':0,'locked':false}
	check(run.bench_count() == 6 and run.purchase_error(0).is_empty(),'full reserves admit a purchase completing a recipe')
	check(run.buy(0).is_empty() and run.unit(uid).rank == 1 and run.bench_count() == 5,'automatic evolution frees reserve space atomically')
	Fixture.begin(run, 13)
	run.gold = 80
	run.lock_offer(0)
	var locked: Dictionary = run.shop[0].duplicate()
	var old_gold := run.gold
	var price := run.shop_upgrade_cost()
	check(run.upgrade_shop().is_empty() and run.shop_level == 1 and run.gold == old_gold-price,'shop improvement charges once')
	check(run.shop[0] == locked and not run.can_undo(),'improvement keeps locked offers and seals revealed randomness')
	var ranks := [0,0,0]
	for i in 120:
		run._roll_shop(false)
		for offer: Dictionary in run.shop: ranks[int(offer.rank)] += 1
	check(ranks[1] > 125 and ranks[1] < 235 and ranks[2] == 0,'first improvement offers upgraded native forms at the advertised rate')
	check(run.upgrade_shop().is_empty() and run.shop_level == 2,'second recruitment improvement')
	ranks = [0,0,0]
	for i in 120:
		run._roll_shop(false)
		for offer: Dictionary in run.shop:
			ranks[int(offer.rank)] += 1
			check(not ArenaRules.prototype(offer.family,offer.rank).is_empty(),'every generated quality has a valid native form')
	check(ranks[2] > 20 and ranks[2] < 90 and ranks[1] > 200,'fully improved shop offers all native qualities')
	check(not run.upgrade_shop().is_empty(),'maximum shop quality cannot be purchased again')
	var saved := run.snapshot()
	check(restored.restore(saved) and restored.snapshot() == saved,'quality and ranked offers survive save/load')
	run.refresh(); restored.refresh()
	check(run.shop == restored.shop,'quality rolls remain deterministic after save/load')
	for value in [-1,3,1.5,'2']:
		var broken := saved.duplicate(true)
		broken.shop_level = value
		check(not restored.restore(broken),'malformed shop quality is rejected')
	var legacy := saved.duplicate(true)
	legacy.version = 2
	legacy.erase('shop_level')
	for offer in legacy.shop: offer.erase('rank')
	check(restored.restore(legacy) and restored.shop_level == 0,'legacy expedition keeps its original shop quality')
	# Both sides must be active before any damage, including the side ticked last.
	for starter in 3:
		Fixture.begin(run, 6519,starter)
		var match_state := ArenaPveMatch.new()
		match_state.run = run
		match_state.rendered = false
		add_child(match_state)
		match_state.set_process(false)
		match_state._world_parent = self
		match_state.prepare()
		var starts := {}
		for unit: GameUnit in match_state.world.unit_rows(): starts[unit.uid] = unit.pos
		check(match_state.start(),'native encounter starts')
		match_state.simulate_tick()
		for unit: GameUnit in match_state.world.unit_rows():
			check(unit.order.get('type','') in ['attack','cast'],'both sides immediately acquire combat orders')
			check(unit.hp == unit.max_hp,'engagement precedes first damage')
			var enemies := match_state.world.ai.enemies(unit)
			var unique := {}
			for foe: GameUnit in enemies: unique[foe.uid] = true
			check(enemies.size() == unique.size(),'noticed opponents are not duplicated')
			if unit.faction == 2: check(unit.pos.distance_to(starts[unit.uid]) > 0.01,'enemy advances on the very first tick')
		for i in 8: match_state.simulate_tick()
		check(match_state.damage == [0.0,0.0],'both teams engage before being struck')
		match_state.queue_free()
		await get_tree().process_frame
	check(hash(GameData.db.tables) == native,'all native prototype stats remain unchanged')
	print('ARENA_USABILITY ',checks,' checks; failures=',failures)
	get_tree().quit(0 if failures.is_empty() else 1)
