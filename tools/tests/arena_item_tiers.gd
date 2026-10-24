extends "arena_combat_effects.gd"
## Tier progression, old reward migration, and the highest-risk mixed effects.
func _ready() -> void:
	check(ArenaItems.RULES.size() == 40, "forty real item definitions")
	var simple := 0
	for kind: String in ArenaItems.RULES:
		if ArenaItems.effect(kind).is_empty(): simple += 1
	check(simple >= 20, "at least half the pool offers straightforward stats")
	for level in range(1, 6):
		check(ArenaItems.RULES.keys().filter(func(k): return ArenaItems.tier(k) == level).size() == 8, "eight items in tier %d" % level)
	for milestone: Array in [[3,1], [5,2], [10,3], [15,4], [20,5], [25,5], [100,5]]:
		for seed_value in range(1, 21):
			var offers := ArenaItems.offers(seed_value, milestone[0])
			check(offers.size() == 3 and offers[0] != offers[1] and offers[1] != offers[2] and offers[0] != offers[2] and offers.all(func(k): return ArenaItems.tier(k) == milestone[1]), "equal tier, distinct choices at %d seed %d" % [milestone[0],seed_value])
	var run := ArenaRun.new(); run.auto_save = false; run.begin(6112); run.wave = 4
	run.offer_items_after(3)
	var old := run.snapshot()
	old.version = 14; old.erase("item_offer_version")
	old.item_offers = ArenaItems.offers(run.run_seed, 3, 1)
	var restored := ArenaRun.new(); restored.auto_save = false
	check(restored.restore(JSON.parse_string(JSON.stringify(old))) and restored.item_offers == old.item_offers and restored.item_offer_version == 1, "old pending eight-item reward migrates without changing choices")
	var again := ArenaRun.new(); again.auto_save = false
	check(again.restore(JSON.parse_string(JSON.stringify(restored.snapshot()))) and again.item_offers == old.item_offers, "legacy pool survives saving again under the new schema")
	again.choose_item(1); again.undo()
	check(again.item_offer_version == 1 and again.item_offers == old.item_offers, "undo keeps the reward's original pool")
	again.wave = 11; again.offer_items_after(10)
	check(again.item_offer_version == 2 and again.item_offers.all(func(k): return ArenaItems.tier(k) == 3), "future milestone switches an old run to tiered loot")
	# A retired recruit may survive an old save, but cannot return to the shop.
	run = ArenaRun.new(); run.auto_save = false; run.begin(4412)
	var legacy := run._recruit(29, 0, int(ArenaRules.FAMILIES[29].cost))
	run.shop[0] = {"family":29, "rank":0, "locked":true}
	old = run.snapshot(); old.version = 14
	check(restored.restore(JSON.parse_string(JSON.stringify(old))) and restored.unit(legacy.uid).family == 29 and restored.shop[0].family == -1 and not restored.shop[0].locked, "old owned Woodsfolk seer remains valid; retired shop offer clears")
	old.version = ArenaRules.VERSION
	check(not again.restore(old), "new saves cannot forge retired recruit offers")
	# Neutral creatures use the native action-speed default rather than a recruit override.
	setup([0], [0])
	var neutral_base: Dictionary = enemies[0].get_meta("arena_combat_base")
	neutral_base.stats.erase("actions")
	battle.world.arena_effects._apply_stats(enemies[0])
	check(is_equal_approx(enemies[0].stats.actions, 15.0), "missing neutral action speed uses native default")
	# Stats add to alliance power, and recalculation cannot compound them.
	setup([0,1], [24], ["blade"])
	var base: Dictionary = own[0].get_meta("arena_combat_base")
	check(is_equal_approx(own[0].stats.dmg_min, base.stats.dmg_min * 1.3), "Beasts plus sword add to 30 percent")
	var once := own[0].stats.duplicate(true)
	battle.world.arena_effects._apply_stats(own[0])
	check(own[0].stats == once, "reapplying item stats does not compound them")
	setup([4,28], [24], ["worldheart"])
	base = own[0].get_meta("arena_combat_base")
	check(is_equal_approx(own[0].max_hp, base.hp * 2.65), "legendary health and Horde use one additive budget")
	setup([3,5], [24], ["focus"])
	check(is_equal_approx(battle.world.arena_effects.spell_damage_multiplier(own[0]), 1.35), "Mage and wand spell bonuses add before armor")
	setup([0], [24,24,24], ["thunderbolt"])
	var before := [enemies[1].hp, enemies[2].hp]
	for i in 3: hit(own[0], enemies[0])
	check(enemies[1].hp < before[0] and enemies[2].hp < before[1] and battle.world.arena_effects.rows[own[0].uid].hits == 3, "legendary lightning hits two secondary targets without recursion")
	setup([0,0], [24], ["plague", "venom"])
	hit(own[0], enemies[0]); battle.world.time += 2.0; hit(own[1], enemies[0])
	check(is_equal_approx(battle.world.arena_effects.healing_multiplier(enemies[0]), 0.25), "weaker poison does not overwrite stronger healing suppression")
	battle.world.time += 3.1
	check(is_equal_approx(battle.world.arena_effects.healing_multiplier(enemies[0]), 0.5), "weaker poison remains only for its own original duration")
	setup([0,0], [24], ["covenant", "ward"])
	own[1].hp = own[1].max_hp * 0.36
	hit(enemies[0], own[1], 8.0)
	check(not battle.world.arena_effects.rows[own[0].uid].used, "large ally shield is conserved while personal protection suffices")
	var fx := battle.world.arena_effects
	check(fx.shield_visual_state().size() == 1 and float(fx.shield_visual_state()[0].secs) <= 5.0, "replicas receive remaining shield duration")
	battle.world.time += 5.1; fx.tick()
	check(fx.shields.is_empty() and fx.shield_visual_state().is_empty(), "expired shields leave gameplay and replicated visual state")
	setup([3], [24], ["chronicle"], [], 1)
	for i in 2: battle.world.arena_effects.on_cast(own[0], "arrow{t2}", enemies[0], enemies[0].pos)
	check(battle.world.arena_effects.totals.get("echo", 0) == 1, "legendary echo fires on second offensive spell")
	print("ARENA_ITEM_TIERS checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
