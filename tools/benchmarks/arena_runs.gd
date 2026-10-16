extends Node
## Seeded full-run economy + real native combat. No synthetic HP/DPS formula.
## --arena-seeds=12 --arena-seed-start=100 --arena-policy=balanced

var policy := "balanced"
var total := 12
var seed_start := 100
var challenge := 0
var pact_choice := "auto"
var source_hashes := {}
var results := []
var run: ArenaRun
var match_state: ArenaPveMatch
var field: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-seeds="): total = maxi(1, int(arg.get_slice("=", 1)))
		if arg.begins_with("--arena-seed-start="): seed_start = int(arg.get_slice("=", 1))
		if arg.begins_with("--arena-challenge="): challenge = clampi(int(arg.get_slice("=", 1)), 0, 2)
		if arg.begins_with("--arena-policy="): policy = arg.get_slice("=", 1)
		if arg.begins_with("--arena-pact="): pact_choice = arg.get_slice("=", 1)
	if not ArenaRules.available():
		printerr("Original expedition content missing")
		get_tree().quit(1)
		return
	for key in ["arena_rules", "arena_run", "arena_pve_match", "arena_terrain"]:
		source_hashes[key] = FileAccess.get_sha256("res://src/game/%s.gd" % key)
	var native_hash := hash(GameData.db.tables)
	run = ArenaRun.new()
	run.auto_save = false
	match_state = ArenaPveMatch.new()
	match_state.rendered = false
	match_state.run = run
	add_child(match_state)
	match_state.set_process(false)
	field = Node3D.new()
	add_child(field)
	match_state._world_parent = field
	for number in total:
		run.begin(seed_start + number, (seed_start + number) % 3, challenge)
		var trace := []
		while run.stage not in ["won", "lost"]:
			if run.stage == "prepare":
				shop_turn()
				match_state.prepare()
				var snapshot := {"wave": run.wave, "gold": run.gold, "lives": run.lives,
					"pact": run.pact, "pact_rank": run.pact_rank, "pact_active": run.pact_active(),
					"army": run.army.filter(func(u): return u.deployed).duplicate(true)}
				if not match_state.start():
					printerr("Simulation failed to start: ", snapshot)
					get_tree().quit(1)
					return
				for tick in 5500:
					if match_state.phase != ArenaMatch.Phase.FIGHT: break
					match_state.simulate_tick()
				if run.stage == "fight":
					printerr("Simulation did not terminate")
					get_tree().quit(1)
					return
				snapshot.merge(run.last_result, true)
				trace.append(snapshot)
				await get_tree().process_frame
			elif run.stage == "result":
				run.advance()
			elif run.stage == "reward":
				var choice := 0
				if run.rewards[0].kind == "pact":
					var desired := pact_choice
					if desired == "auto": desired = "vanguard" if policy == "melee" else "hunt" if policy == "ranged" or run.starter == 1 else "tribe"
					for i in run.rewards.size():
						if run.rewards[i].pact == desired: choice = i
				elif run.lives < 3:
					for i in run.rewards.size():
						if run.rewards[i].kind == "life": choice = i
				run.choose_reward(choice)
		var record := {"seed": run.run_seed, "starter": run.starter, "outcome": run.stage,
			"wave": run.wave, "lives": run.lives, "pact": run.pact, "pact_rank": run.pact_rank, "trace": trace}
		results.append(record)
		print("ARENA_RUN ", policy, " seed=", run.run_seed, " outcome=", run.stage, " wave=", run.wave, " lives=", run.lives)
		_write()
	get_tree().quit(0 if check_native(native_hash) else 1)


func shop_turn() -> void:
	merge_all()
	run.arrange()
	var refreshes := 0
	for step in 40:
		if run.bench_count() >= run.bench_limit():
			# Ordinary decisions can be imperfect: recover one stale unmerged
			# copy only when its family has no matching companion on the bench.
			var removable := run.army.filter(func(u): return not u.deployed and u.family >= 0 and u.rank == 0 and run.copies(u).size() == 1)
			if not removable.is_empty() and run.gold >= 3: run.sell(removable[0].uid)
			else: break
		var selected := -1
		var best := -INF
		for i in run.shop.size():
			var family := int(run.shop[i].family)
			if family < 0 or run.gold < int(ArenaRules.FAMILIES[family].cost): continue
			var owned := run.army.filter(func(u): return u.family == family and u.rank == 0).size()
			var affinity := run.army.filter(func(u): return u.family == family).size()
			var preferred: Array = ArenaRules.STARTERS[run.starter].families
			if policy == "melee": preferred = [0, 1, 2]
			elif policy == "ranged": preferred = [3, 4, 5]
			elif policy == "diverse": preferred = [0, 1, 2, 3, 4, 5]
			if pact_choice in ArenaRules.PACTS and policy != "novice": preferred = ArenaRules.PACTS[pact_choice].families
			var score := float(owned * 4 + mini(affinity, 3)) + (5 if family in preferred else -7)
			# A ranged policy still needs a third beast family for Wild kin.
			# Buy one melee family if absent; it competes with another evolution.
			if run.pact == "hunt" and family in [0, 2] and not run.army.any(func(u): return int(u.family) in [0, 2]): score += 14
			if policy == "novice": score = 1 # Buy the first affordable offer.
			if run.army.size() < run.capacity(): score += 10
			if score > best:
				best = score
				selected = i
		if selected >= 0 and best >= 0:
			run.buy(selected)
			merge_all()
			run.arrange()
		elif run.gold >= 5 and refreshes < (1 if policy == "novice" else 3):
			run.refresh()
			refreshes += 1
		else: break
	run.arrange()


func merge_all() -> void:
	for attempt in 20:
		var merged := false
		for entry: Dictionary in run.army.duplicate():
			if run.evolution_error(entry.uid).is_empty():
				run.evolve(entry.uid)
				merged = true
				break
		if not merged: break


func check_native(want: int) -> bool:
	if hash(GameData.db.tables) != want:
		printerr("Native prototype data changed during simulation")
		return false
	return true


func _write() -> void:
	var output := {"rules_version": ArenaRules.VERSION, "policy": policy, "count": results.size(),
		"pact_choice": pact_choice,
		"source_sha256": source_hashes, "challenge": challenge,
		"seed_start": seed_start, "results": results,
		"scope": "Actual run economy, native AI/combat/spells/projectiles, authored terrain and scenery navigation. Manual 55ms ticks; no visual/audio presentation. Policy clear rates are not human clear rates."}
	var file := FileAccess.open("user://arena-runs-%s-%d.json" % [policy, seed_start], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
