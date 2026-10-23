extends Node
## Autochess companies recruit from one limited pool; expeditions do not.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)


func held(run: ArenaTournamentRun) -> Dictionary:
	var out := {}
	for player in ArenaTournamentRun.PLAYER_COUNT:
		if run.health(player) <= 0: continue
		var company := run.company(player)
		for row: Dictionary in company.army + company.shop:
			var family := int(row.family)
			if family >= 0: out[family] = int(out.get(family, 0)) + ArenaRules.rank_copies(family, int(row.get("rank", 0)))
	return out


func _ready() -> void:
	var expedition := ArenaRun.new(); expedition.auto_save = false
	expedition.begin(4411)
	check(not expedition.shares_pool() and expedition.pool_left().is_empty(), "an expedition keeps unlimited offers")

	var run := ArenaTournamentRun.new(); run.auto_save = false
	run.begin(8123)
	for player in ArenaTournamentRun.PLAYER_COUNT:
		check(run.company(player).shares_pool(), "company %d draws from the shared pool" % player)
	var left := run.pool_left()
	var counted := held(run)
	for family in ArenaRules.ACTIVE_FAMILIES:
		check(int(left[family]) == ArenaRules.pool_size(family) - int(counted.get(family, 0)), "pool count of family %d matches every company's offers" % family)
	check(run.pool_left() == run.company(3).pool_left(), "every company sees the same pool")

	# Rich, maximum-level companies buy everything they are offered for many
	# refreshes; tier 5 (10 copies) must run out without ever going negative.
	for player in ArenaTournamentRun.PLAYER_COUNT:
		var company := run.company(player)
		company.training = ArenaRules.MAX_TRAINING
		company.wave = 20
	var negative := false
	var bought := {}
	for pass_index in 60:
		for player in ArenaTournamentRun.PLAYER_COUNT:
			var company := run.company(player)
			company.gold = 1000
			for index in company.shop.size():
				var family := int(company.shop[index].family)
				if family < 0: continue
				# Unlimited reserves: the pool, not the bench, is under test.
				company._recruit(family, 0, 1)
				company.shop[index] = {"family": -1, "locked": false}
				bought[family] = int(bought.get(family, 0)) + 1
			company.free_refresh = true
			company._roll_shop(false)
			for value in run.pool_left().values():
				if int(value) < 0: negative = true
	check(not negative, "no family is ever drawn past its pool")
	for family in ArenaRules.ACTIVE_FAMILIES:
		check(int(bought.get(family, 0)) <= ArenaRules.pool_size(family), "family %d bought at most its %d copies" % [family, ArenaRules.pool_size(family)])
	var tier5 := ArenaRules.ACTIVE_FAMILIES.filter(func(f): return int(ArenaRules.FAMILIES[f].tier) == 5)
	check(tier5.all(func(f): return int(run.pool_left()[f]) == 0), "tier 5 runs out after sustained buying")

	# Merging keeps the copies out of the pool; selling returns them.
	var company := run.company(0)
	var family: int = tier5[0]
	var before := int(run.pool_left()[family])
	var owned := company.army.filter(func(e): return int(e.family) == family)
	if owned.size() >= 3:
		company.stage = "prepare"
		company.combine_ready()
		check(int(run.pool_left()[family]) == before, "evolving keeps merged copies out of the pool")
	var sold: Dictionary = company.army.filter(func(e): return int(e.family) == family).front() if company.army.any(func(e): return int(e.family) == family) else {}
	if not sold.is_empty():
		var copies := ArenaRules.rank_copies(family, int(sold.rank))
		var pool_before := int(run.pool_left()[family])
		company.army.erase(sold)
		check(int(run.pool_left()[family]) == pool_before + copies, "selling returns a creature's copies")

	# An eliminated company's creatures and offers go back.
	var rival := run.company(4)
	var returned := {}
	for row: Dictionary in rival.army + rival.shop:
		if int(row.family) >= 0: returned[int(row.family)] = int(returned.get(int(row.family), 0)) + ArenaRules.rank_copies(int(row.family), int(row.get("rank", 0)))
	var pool_alive := run.pool_left()
	run.rival_health[3] = 0
	var pool_after := run.pool_left()
	check(returned.keys().all(func(f): return int(pool_after[f]) == int(pool_alive[f]) + int(returned[f])), "elimination returns the company's copies")

	# A saved tournament keeps sharing after restore.
	var fresh := ArenaTournamentRun.new(); fresh.auto_save = false
	fresh.begin(6151)
	var restored := ArenaTournamentRun.new(); restored.auto_save = false
	check(restored.restore(JSON.parse_string(JSON.stringify(fresh.snapshot()))), "tournament snapshot restores")
	if restored.rivals.size() == ArenaTournamentRun.PLAYER_COUNT - 1:
		check(restored.company(5).shares_pool() and restored.pool_left() == fresh.pool_left(), "restored companies share the same pool")
	print("ARENA_SHARED_POOL ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
