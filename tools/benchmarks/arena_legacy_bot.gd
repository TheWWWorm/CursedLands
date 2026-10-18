extends RefCounted
## Frozen pre-change policy for paired balance comparisons.
static func legacy_step(bot: ArenaRun, player: int, round_number: int, hp: int, plan: Dictionary) -> void:
	if plan.done: return
	plan.actions += 1
	if plan.actions >= 40: plan.done = true; return
	var desired_level := mini(ArenaRules.MAX_ARMY, 3 + (round_number - 1) / 3)
	if bot.capacity() < desired_level and bot.gold >= ArenaRules.TRAINING_COST + 4:
		if bot.train().is_empty(): return
	var reserve_gold := 10 if round_number >= 8 and hp > 35 else 0
	var best := -1
	var best_score := -INF
	for index in bot.shop.size():
		if not bot.purchase_error(index).is_empty(): continue
		var offer: Dictionary = bot.shop[index]
		var family := int(offer.family)
		var copies := bot.army.filter(func(entry): return int(entry.family) == family and int(entry.rank) == 0).size()
		var needed := ArenaRules.evolution_copies(family, 0)
		var merging := needed > 0 and copies + 1 >= needed
		if bot.gold - bot.offer_cost(offer) < reserve_gold and not merging and bot.deployed_count() >= bot.capacity(): continue
		var score := float(ArenaRules.FAMILIES[family].tier) * 2.0
		if ArenaTournamentRun.STYLES[(player - 1) % ArenaTournamentRun.STYLES.size()] in ArenaAlliances.traits(family): score += 5
		if copies > 0: score += 8 + copies * 3
		if merging: score += 20
		if not bot.army.any(func(entry): return int(entry.family) == family): score += 2
		if score > best_score: best = index; best_score = score
	if best >= 0:
		bot.buy(best)
		bot.arrange()
	elif bot.bench_count() >= bot.bench_limit():
		var spare := bot.army.filter(func(entry): return not entry.deployed and int(entry.rank) == 0)
		spare.sort_custom(func(a,b): return int(a.investment) < int(b.investment))
		if not spare.is_empty(): bot.sell(int(spare[0].uid))
		else: plan.done = true
	elif plan.rerolls < 5 and bot.gold >= reserve_gold + bot.refresh_cost() + 3 and bot.refresh().is_empty():
		plan.rerolls += 1
	else: plan.done = true
	bot._undo.clear()
