extends Node
## Run/economy invariants and real ranged/magic encounter smoke tests.

var checks := 0
var failures: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)


func _ready() -> void:
	check(ArenaRules.available(), "original curated content is available")
	if not failures.is_empty():
		get_tree().quit(1)
		return
	var native_hash := hash(GameData.db.tables)
	var run := ArenaRun.new()
	run.auto_save = false
	run.begin(6519)
	check(run.army.size() == 3 and run.deployed_count() == 3 and run.gold == 6, "starter army and budget")
	var replay := ArenaRun.new()
	replay.auto_save = false
	check(replay.restore(run.snapshot()), "snapshot round trip")
	check(replay.shop == run.shop, "identical seeded shop")
	run.refresh(); replay.refresh()
	check(replay.shop == run.shop and replay.gold == run.gold, "RNG stream survives save")
	var before := run.snapshot()
	check(not run.deploy(run.army[0].uid, Vector2(60, 32)).is_empty(), "enemy-side placement rejected")
	check(run.snapshot() == before, "failed actions are atomic")
	run.wave = 4
	run.gold = 30
	run.shop = [{"family": 0, "locked": false}, {"family": 0, "locked": false}]
	check(run.buy(0).is_empty() and run.buy(1).is_empty(), "buy native duplicates")
	var id := int(run.army[0].uid)
	check(run.unit(id).rank == 1, "third purchase evolves automatically")
	check(run.unit(id).prototype == "boarredf3" and run.unit(id).investment == 9, "native output and invested cost")
	check(run.army.size() == 3 and run.sale_value(run.unit(id)) == 3, "merge frees two slots without resale profit")
	run.undo()
	check(run.army.size() == 4 and run.unit(id).prototype == "boarredf1", "purchase undo restores pre-merge copies")
	run.refresh()
	check(not run.can_undo(), "refresh cannot be undone for free information")
	run.lock_offer(0)
	check(run.shop[0].locked, "lock action")
	var locked := int(run.shop[0].family)
	run.refresh()
	check(run.shop[0].family == locked and run.shop[0].locked, "locked offer persists")
	# Saved expeditions are untrusted JSON. Reject malformed and impossible
	# state without partially replacing the existing run.
	var valid := ArenaRun.new()
	valid.auto_save = false
	valid.begin(9271)
	var good := valid.snapshot()
	var corrupted: Array[Dictionary] = []
	for field in ["deployed", "investment", "prototype", "point", "uid"]:
		var broken := good.duplicate(true)
		broken.army[0].erase(field)
		corrupted.append(broken)
	for value in ["six", null, -1, 2.5]:
		var broken := good.duplicate(true)
		broken.gold = value
		corrupted.append(broken)
	var wrong_proto := good.duplicate(true)
	wrong_proto.army[0].prototype = "ogregipatf7"
	corrupted.append(wrong_proto)
	var wrong_reward := good.duplicate(true)
	wrong_reward.rewards = [{"kind": "companion", "prototype": "ogregipatf7"}]
	corrupted.append(wrong_reward)
	var overlap := good.duplicate(true)
	overlap.army[1].point = overlap.army[0].point.duplicate()
	corrupted.append(overlap)
	for broken in corrupted:
		check(not valid.restore(broken) and valid.snapshot() == good, "invalid saved state rejected atomically")
	check(valid.save(), "separate expedition save writes atomically")
	check(replay.load_saved() and JSON.parse_string(JSON.stringify(replay.snapshot())) == JSON.parse_string(JSON.stringify(good)), "disk save preserves full state")
	valid.start_battle()
	var attempt_seed := valid.battle_seed()
	check(replay.restore(valid.snapshot()) and replay.stage == "prepare" and replay.battle_seed() == attempt_seed, "interrupted battle resumes same attempt")
	valid.resolve(1, 23.0, [12.0, 60.0])
	valid.advance()
	check(valid.lives == 2 and valid.gold == 6 and valid.wave == 1 and valid.battle_seed() != attempt_seed, "defeat costs life and retry gets fresh combat rolls without income")
	for victory in 6:
		valid.start_battle()
		valid.resolve(0, 20.0, [90.0, 10.0])
		valid.advance()
		if valid.stage == "reward" and valid.wave == 3: valid.choose_reward(0)
	check(valid.stage == "reward" and valid.rewards.size() == 3, "first boss offers three rewards")
	check(replay.restore(valid.snapshot()) and replay.rewards == valid.rewards, "reward selection survives reload")
	check(valid.choose_reward(0).is_empty() and valid.army.back().prototype == "orcfemalem3" and valid.wave == 7, "native specialist reward and next wave")
	var after_reward := valid.snapshot()
	check(not valid.choose_reward(0).is_empty() and valid.snapshot() == after_reward, "reward cannot be claimed twice")
	for family in ArenaRules.FAMILIES.size():
		for rank in ArenaRules.FAMILIES[family].forms.size() - 1:
			valid.begin(1)
			valid.army.clear()
			valid.wave = 4 if rank == 0 else 10
			for copy in ArenaRules.evolution_copies(family, rank): valid._recruit(family, rank, 3 * int(pow(3, rank)))
			var selected := int(valid.army[0].uid)
			check(valid.evolve(selected).is_empty() and valid.unit(selected).prototype == ArenaRules.prototype(family, rank + 1), "curated evolution uses exact original form")
			valid.arrange()
			check(replay.restore(valid.snapshot()), "evolved formation remains a valid save")
	# Final victory and progression are tested without pretending the stubbed
	# outcomes below measure combat strength; benchmark scripts run real fights.
	valid.begin(9)
	for number in ArenaRules.WAVE_COUNT:
		valid.start_battle(); valid.resolve(0, 20, [100, 0])
		if valid.stage == "won": break
		valid.advance()
		if valid.stage == "reward": valid.choose_reward(0)
	check(valid.stage == "won" and valid.wave == 18 and valid.lives == 3, "eighteen-wave progression reaches terminal victory")
	check(replay.restore(valid.snapshot()) and replay.stage == "won", "terminal victory reloads")
	# V1 expeditions retain their state and RNG; new saves require pact fields.
	var legacy := good.duplicate(true)
	legacy.version = 1; legacy.erase("pact"); legacy.erase("pact_rank")
	check(replay.restore(legacy) and replay.pact.is_empty() and replay.gold == int(legacy.gold), "legacy expedition migrates without a reset")
	var migrated := replay.snapshot()
	var unchanged := replay.snapshot()
	for field in ["pact", "pact_rank"]:
		var broken := migrated.duplicate(true)
		broken.erase(field)
		check(not replay.restore(broken) and replay.snapshot() == unchanged, "current saves require pact fields")
	for broken_pact in ["unknown", 4, null]:
		var broken := migrated.duplicate(true)
		broken.pact = broken_pact
		check(not replay.restore(broken) and replay.snapshot() == unchanged, "unknown pact rejected atomically")
	# Persistent challenge unlocks and recovery from a malformed profile.
	ArenaRun._write_json(ArenaRun.PROFILE_PATH, {"best_wave": "eighteen", "wins": [], "challenge": 99})
	check(ArenaRun.profile() == {"best_wave": 0, "wins": 0, "challenge": 0}, "corrupt profile fields recover safely")
	valid.auto_save = true
	valid._update_profile()
	check(ArenaRun.profile().challenge == 1 and ArenaRun.profile().wins == 1, "first clear unlocks veteran")
	valid.challenge = 1
	valid._update_profile()
	check(ArenaRun.profile().challenge == 2, "veteran clear unlocks champion")
	valid.auto_save = false
	# Camps are one-time decisions. Pact rank is an upgrade choice, not an
	# automatic level/stat multiplier. Duplicates and benched units never count.
	var expected_camps: Array[int] = []
	valid.begin(77)
	for number in ArenaRules.WAVE_COUNT:
		valid.start_battle(); valid.resolve(0, 20, [100, 0]); valid.advance()
		if valid.stage != "reward": continue
		expected_camps.append(valid.wave)
		check(replay.restore(valid.snapshot()) and replay.rewards == valid.rewards, "camp choices and RNG survive reload")
		valid.choose_reward(0)
		check(replay.restore(valid.snapshot()), "claimed camp state survives reload")
	check(expected_camps == [3, 6, 9, 12, 15] and valid.pact == "hunt" and valid.pact_rank == 2, "five camps with two optional pact upgrades")
	check(valid.pact_prototype() == "wolfwhitef6", "upgraded pact uses exact native form")
	valid.begin(88)
	valid.wave = 9; valid.stage = "reward"; valid.pact = "vanguard"
	valid._make_rewards()
	valid.choose_reward(2)
	check(valid.gold == 12 and valid.pact_rank == 0 and valid.wave == 10, "supplies forego the pact upgrade")
	valid.begin(89)
	valid.wave = 15; valid.pact = "hunt"; valid.stage = "fight"
	valid.boons.assign(["merchant", "reserve", "scout"]); valid._roll_shop(false)
	valid.resolve(0, 20, [100, 0]); valid.advance()
	check(valid.rewards.size() == 2 and valid.rewards[0].kind == "pact_upgrade" and valid.rewards[1].kind == "supplies", "exhausted boon pool leaves two distinct rewards without a dominated gold offer")
	check(replay.restore(JSON.parse_string(JSON.stringify(valid.snapshot()))), "two-choice camp survives JSON reload")
	for pact_key: String in ArenaRules.PACTS:
		var rule: Dictionary = ArenaRules.PACTS[pact_key]
		valid.begin(90); valid.wave = 10; valid.pact = pact_key; valid.army.clear()
		for i in int(rule.needed): valid._recruit(int(rule.families[i]), int(rule.min_rank), 9)
		check(not valid.pact_active(), "reserves do not activate a pact")
		valid.arrange()
		check(valid.pact_active(), "distinct eligible deployed families activate " + pact_key)
		var support := valid.support_placement()
		check(support.id == valid.pact_prototype() and valid.deployed_count() == int(rule.needed), "guest is extra and not stored in army")
		for entry: Dictionary in valid.army:
			check(support.point.distance_to(Vector2(entry.point[0], entry.point[1])) >= 2.5, "guest clears each deployed creature")
		var last := int(valid.army.back().uid)
		valid.bench(last)
		check(not valid.pact_active() and valid.support_placement().is_empty(), "benching a required family removes support")
		valid.undo()
		check(valid.pact_active(), "undo restores the pact condition")
		for i in 4: valid._recruit(-1, 0, 18, "orcfemalem5")
		valid.arrange()
		check(valid.pact_active() and valid.deployed_count() == valid.capacity(), "auto arrange preserves pact before filling strong specialists")
		check(replay.restore(JSON.parse_string(JSON.stringify(valid.snapshot()))) and replay.support_placement() == valid.support_placement(), "support position remains deterministic across JSON reload")
		replay.arrange()
		check(replay.pact_active(), "auto arrange preserves pact after JSON integer conversion")
	valid.begin(91); valid.wave = 4; valid.pact = "hunt"; valid.army.clear()
	for i in 3: valid._recruit(0, 0, 3)
	valid.arrange()
	check(not valid.pact_active() and valid.pact_families().size() == 1, "three copies of one family cannot fake a synergy")
	valid.pact = "tribe"; valid.army.clear()
	valid._recruit(1, 0, 3); valid._recruit(3, 0, 4); valid.arrange()
	check(not valid.pact_active(), "tribal pact requires evolved forms")
	# Swaps must work even with both budgets full, without a temporary extra
	# creature, lost investment or a partially committed failure.
	valid.begin(92)
	for i in valid.bench_limit(): valid._recruit(2, 0, 3)
	var before_swap := valid.snapshot()
	var reserve_id := int(valid.army.back().uid)
	var field_id := int(valid.army[0].uid)
	check(valid.swap_from_bench(reserve_id, field_id).is_empty(), "full bench and army swap directly")
	check(valid.unit(reserve_id).deployed and not valid.unit(field_id).deployed and valid.unit(reserve_id).point == before_swap.army[0].point, "swap transfers exact field position")
	check(valid.bench_count() == valid.bench_limit() and valid.deployed_count() == valid.capacity() and valid.gold == int(before_swap.gold), "swap preserves both budgets and gold")
	valid.undo()
	check(valid.snapshot() == before_swap, "swap undo restores complete preparation")
	check(not valid.swap_from_bench(field_id, reserve_id).is_empty() and valid.snapshot() == before_swap, "invalid swap is atomic")
	# Higher challenges add native combatants without moving or scaling the
	# base encounter. All eighteen formations must have distinct spawn points.
	for wave_number in range(1, ArenaRules.WAVE_COUNT + 1):
		var standard := ArenaRules.enemies(wave_number, 72)
		for difficulty in [1, 2]:
			var enemies := ArenaRules.enemies(wave_number, 72, difficulty)
			check(enemies.slice(0, standard.size()) == standard, "challenge preserves authored encounter and placement")
			var seen_points := {}
			for enemy: Dictionary in enemies: seen_points[enemy.point] = true
			check(seen_points.size() == enemies.size(), "reinforcements never overlap on wave " + str(wave_number))
	valid.begin(7)
	valid.wave = 6
	for i in valid.bench_limit(): valid._recruit(0, 0, 3)
	valid.stage = "reward"
	valid._make_rewards()
	check(valid.choose_reward(0).is_empty() and valid.bench_count() == valid.bench_limit() + 1, "full bench still accepts a boss companion")
	valid.shop[0] = {"family": 2, "rank": 0, "locked": false}
	check(not valid.buy(0).is_empty(), "overflow bench blocks purchases until a space is freed")
	valid.wave = 12; valid.stage = "reward"; valid._make_rewards()
	var overflow := valid.snapshot()
	check(not valid.choose_reward(0).is_empty() and valid.snapshot() == overflow, "second overflow companion cannot make save unrestorable")
	check(valid.choose_reward(2).is_empty() and valid.wave == 13, "overflow reserve still allows another reward")
	for kind in ["merchant", "reserve", "scout", "purse", "life"]:
		valid.begin(42)
		valid.wave = 6; valid.stage = "reward"; valid.lives = 2
		valid.rewards = [{"kind": kind}]
		check(valid.choose_reward(0).is_empty(), "boon can be claimed: " + kind)
		if kind == "merchant": check(valid.refresh_cost() == 1, "quartermaster changes reroll cost")
		elif kind == "reserve": check(valid.bench_limit() == 9, "pack train adds reserve spaces")
		elif kind == "scout": check(valid.shop.size() == 6, "scout immediately opens six offers")
		elif kind == "purse": check(valid.gold == 18, "war chest grants its stated gold")
		elif kind == "life": check(valid.lives == 3, "second wind restores one life")
	for starter in 3:
		run.begin(6519 + starter, starter)
		var match_state := ArenaPveMatch.new()
		match_state.rendered = false
		match_state.run = run
		add_child(match_state)
		match_state.set_process(false)
		var stage := Node3D.new()
		add_child(stage)
		match_state._world_parent = stage
		match_state.prepare()
		check(match_state.world.terrain.grid_w == 65, "authored courtyard navigation")
		check(match_state.world.combat.difficulty_override == 0, "isolated native combat difficulty")
		check(match_state.start(), "starter battle begins")
		for tick in 5500:
			if match_state.phase != ArenaMatch.Phase.FIGHT: break
			match_state.simulate_tick()
		check(run.stage == "result" and match_state.winner == 0, "starter clears first encounter")
		print("STARTER ", starter, " winner=", match_state.winner, " seconds=", match_state.world.time)
		var earned := run.gold
		match_state._resolved(0)
		check(run.gold == earned, "battle reward cannot be claimed twice")
		run.advance()
		check(run.wave == 2 and run.stage == "prepare", "next encounter")
		match_state.queue_free(); stage.queue_free()
		await get_tree().process_frame
	# A guest goes through actual native spawn, combat and death handling,
	# then returns from the pact rather than being duplicated into saved army.
	run.begin(9821, 1); run.wave = 4; run.pact = "hunt"
	var guest_match := ArenaPveMatch.new()
	guest_match.rendered = false; guest_match.run = run
	add_child(guest_match); guest_match.set_process(false)
	var guest_stage := Node3D.new()
	add_child(guest_stage); guest_match._world_parent = guest_stage
	guest_match.prepare()
	var guests := guest_match.world.unit_rows().filter(func(u): return u.get_meta("arena_placement", {}).has("pact"))
	check(guests.size() == 1 and guests[0].info.prototype == run.pact_prototype(), "native pact guest is present before commitment")
	check(guest_match.team_count(0) == run.deployed_count() + 1 and run.army.size() == 3, "guest does not spend or enter persistent army")
	check(guest_match.start(), "guest participates in native AI battle")
	for tick in 5500:
		if guest_match.phase != ArenaMatch.Phase.FIGHT: break
		guest_match.simulate_tick()
	check(run.stage == "result" and run.army.size() == 3, "pact battle resolves without persisting support")
	run.advance(); guest_match.prepare()
	check(guest_match.team_count(0) == run.deployed_count() + 1, "exactly one guest returns next battle")
	run.bench(run.army[0].uid); guest_match.prepare()
	check(guest_match.team_count(0) == run.deployed_count(), "guest disappears when the composition no longer qualifies")
	guest_match.queue_free(); guest_stage.queue_free()
	await get_tree().process_frame
	check(hash(GameData.db.tables) == native_hash, "native database unchanged")
	print("ARENA_PVE ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
