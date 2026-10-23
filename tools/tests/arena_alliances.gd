extends Node
const Fixture = preload("arena_fixture.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func fresh(seed_value := 1741) -> ArenaRun:
	var run := ArenaRun.new(); run.auto_save = false; run.begin(seed_value)
	return run
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := fresh()
	var other := fresh()
	check(run.army.is_empty() and run.gold == 10 and run.capacity() == 3, "buy an opening army with ten gold at level three")
	check(run.shop.size() == 6 and run.shop.all(func(o):return o.rank == 0), "all opening roles, all at one star")
	check(run.snapshot() == other.snapshot(), "seeded opening deterministic")
	run._recruit(0,0,1)
	for level in range(3, 10):
		run.training = ArenaRules.LEVEL_XP[level]; run.wave = 1; run.gold = 10000
		check(run.capacity() == level, "XP threshold yields level %d" % level)
		var counts := [0,0,0,0,0]
		for roll in 400:
			run._roll_shop(false)
			for offer in run.shop:
				counts[int(ArenaRules.FAMILIES[int(offer.family)].tier) - 1] += 1
				if int(offer.rank) != 0: failures.append("shop created stars")
		var odds: Array = ArenaRules.SHOP_ODDS[level]
		check(odds.reduce(func(a,b):return a+b,0) == 100,"shop probabilities sum to 100")
		for tier in 5:
			check(absf(float(counts[tier])/20.0-int(odds[tier])) < 5.5,"observed tier odds match published table")
		var loaded := other.restore(JSON.parse_string(JSON.stringify(run.snapshot())))
		check(loaded, "every level saves")
		check(other.shop == JSON.parse_string(JSON.stringify(run.shop)), "every shop survives JSON")
	run = fresh(); run.gold = 20; run.buy(0)
	var old_gold := run.gold; var old_shop := run.shop.duplicate(true)
	check(run.train().is_empty() and run.training == 5 and run.gold == old_gold - 5,"five gold buys five XP")
	check(run.capacity() == 3 and run.level_progress() == 5 and run.level_needed() == 6,"progress to next level is explicit")
	check(run.shop == old_shop,"training never secretly rerolls offers")
	run.undo(); check(run.training == 0 and run.gold == old_gold,"training undo restores cost and XP")
	run.training = ArenaRules.MAX_TRAINING; old_gold = run.gold
	check(not run.train().is_empty() and run.gold == old_gold,"max level cannot spend XP gold")
	# Count families once across every star, and ignore reserves and old guests.
	run = fresh(); run.gold = 100; run.training = 126
	for family in [0,0,2,4,5,6,10,1,3,7,9,8,11]: run._recruit(family,0,1)
	for entry in run.army: entry.deployed = true
	run._recruit(-1,0,9,"orcfemalem3").deployed = true
	var counts := run.alliances()
	check(counts == {"beast":8,"horde":2,"warrior":3,"hunter":6,"mage":2,"spirit":2},"current roster counts overlapping traits without duplicate families")
	check(ArenaAlliances.rank("beast",6)==3 and ArenaAlliances.rank("mage",4)==2,"thresholds scale bonuses")
	run.army[0].rank = 1; run.army[0].prototype = ArenaRules.prototype(0,1)
	check(run.alliances()==counts,"evolution stars do not inflate alliance progress")
	for entry in run.army: entry.deployed = false
	check(run.alliances().values().all(func(n):return n == 0),"reserves never activate an alliance")
	# Preparation applies recruit budgets; behavioral alliances start at the bell.
	run = fresh(); run.training = 126; run.wave = 25
	for family in [0,3,4,11,13,14,19,21,22]: run._recruit(family,0,1)
	run.arrange()
	var battle := ArenaPveMatch.new(); battle.run = run; battle.rendered = false
	add_child(battle); battle.set_process(false); battle._world_parent = self; battle.prepare()
	check(battle.team_count(0)==9,"no summoned pact guests")
	var identity := {}; var boosted := {}
	for unit in battle.world.unit_rows():
		identity[unit.get_instance_id()] = true
		boosted[unit.uid] = {"stats":unit.stats.duplicate(true),"hp":unit.max_hp}
		var base: Dictionary = unit.get_meta("alliance_base")
		var placement: Dictionary = unit.get_meta("arena_placement")
		if int(placement.team) == 1:
			var encounter: Dictionary=base.stats.duplicate(true)
			ArenaRules.creep_stats(run.wave,encounter)
			check(is_equal_approx(unit.stats.armor[3],encounter.armor[3]),"preparation leaves encounter elemental armor unchanged")
		else:
			var family := int(run.unit(placement.run_uid).family)
			# Alliances modify the recruit budget, not campaign boss statistics.
			var recruit:=ArenaUnitInfo.values(unit.info.prototype,null,family,0)
			check(is_equal_approx(unit.stats.dmg_min,recruit.min),"Beasts keep their own attack budgets")
			check(is_equal_approx(unit.max_hp,recruit.max_hp),"Horde keeps recruit health budgets")
			check(is_equal_approx(unit.stats.armor[0],recruit.armor[0]),"Warriors protect through guarding, not flat armor")
			check(is_equal_approx(unit.stats.to_hit,recruit.attack),"Hunters keep native accuracy")
			check(is_equal_approx(unit.stats.armor[3],recruit.armor[3]),"Spirits keep recruit resistance budgets")
	for repeat in 4: battle.prepare()
	for unit in battle.world.unit_rows():
		check(identity.has(unit.get_instance_id()),"alliance recalculation retains actors")
		check(boosted[unit.uid].stats == unit.stats and is_equal_approx(boosted[unit.uid].hp,unit.max_hp),"bonuses never accumulate on repeated preparation")
	ArenaAlliances.apply(battle.world, [])
	for unit in battle.world.unit_rows():
		var base: Dictionary = unit.get_meta("alliance_base")
		var expected: Dictionary=base.stats.duplicate(true)
		if int(unit.get_meta("arena_placement").team)==1: ArenaRules.creep_stats(run.wave,expected)
		check(unit.stats == expected and is_equal_approx(unit.max_hp,base.hp),"withdrawing traits restores base values while preserving encounter limits")
	battle.queue_free()
	# Every recipe works from wave one; all resulting forms remain native.
	for family in ArenaRules.FAMILIES.size():
		for rank in ArenaRules.FAMILIES[family].forms.size() - 1:
			run = fresh(); run.gold=100
			var needed := ArenaRules.evolution_copies(family,rank)
			for copy in needed - 1: run._recruit(family,rank,1)
			var kept := run.army[0]; run.deploy(kept.uid,Vector2(27,32))
			run.shop[0]={"family":family,"rank":rank,"locked":false}
			check(run.buy(0).is_empty() and run.unit(kept.uid).rank==rank+1,"automatic evolution from wave one")
			check(run.unit(kept.uid).prototype==ArenaRules.prototype(family,rank+1),"evolution uses native form")
			check(other.restore(run.snapshot()),"evolved run roundtrip")
	# Thirty-wave flow and camp choices never produce pacts.
	run=fresh(); Fixture.buy_company(run,0)
	for wave in 30:
		run.start_battle();run.resolve(0,12,[20,5])
		var bank := run.gold;run.resolve(0,12,[20,5])
		check(run.gold==bank,"settlement pays once")
		run.advance()
		if run.stage=="reward":
			check(run.wave%5==0 and run.rewards.all(func(r):return r.kind not in ["pact","pact_upgrade"]),"camp only offers non-pact upgrades every five clears")
			check(other.restore(run.snapshot()),"camp persists")
			run.choose_reward(0)
		check(other.restore(run.snapshot()),"progression roundtrip at every wave")
	check(run.stage=="won", "final wave terminates")
	# Camp cash is flexible, while training gives more XP per reward.
	for reward in ["experience", "purse"]:
		run=fresh(); run.wave=5; run.stage="reward"; run._make_rewards()
		var before_xp:=run.experience();var before_gold:=run.gold
		var choice:=run.rewards.find_custom(func(r):return r.kind==reward)
		check(choice>=0 and run.choose_reward(choice).is_empty(),"camp offers " + reward)
		check(run.gold-before_gold==8 if reward=="purse" else run.experience()-before_xp==11,"camp grants eight gold or ten XP plus cleared-wave XP")
	run=fresh();Fixture.buy_company(run);run.start_battle();run.resolve(1,10,[1,5]);run.advance()
	check(run.free_refresh and run.refresh_cost()==0,"loss grants one recovery refresh")
	var bank:=run.gold;run.refresh()
	check(not run.free_refresh and run.gold==bank and run.refresh_cost()==2,"free refresh is consumed once")
	# Schema seven paid army slots and shop investment survive the replacement.
	run=fresh();Fixture.buy_company(run);var old:=run.snapshot()
	old.version=7;old.preparation_left=45;old.wave=10;old.training=6;old.pact="hunt";old.pact_rank=1;old.shop_level=2
	for entry in old.army: entry.prototype=ArenaRules.LEGACY_FORMS[entry.family][entry.rank]
	check(other.restore(old) and other.capacity()>=8 and not other.snapshot().has("pact"),"legacy capacity and investments migrate without pact state")
	check(other.restore(other.snapshot()),"migrated save reloads under schema eight")
	old.stage="reward";old.wave=3;old.training=0;old.pact="";old.pact_rank=0
	old.last_result={"wave":3,"winner":0,"seconds":12,"damage":[20,1],"gold":6}
	old.rewards=[{"kind":"pact","pact":"hunt"},{"kind":"pact","pact":"tribe"},{"kind":"pact","pact":"vanguard"}]
	check(other.restore(old) and other.stage=="prepare" and other.wave==4,"old pact selection resumes directly into preparation")
	var valid:=other.snapshot()
	for value in [-1,INF,"5",null]:
		var invalid:=valid.duplicate(true);invalid.training=value
		check(not other.restore(invalid) and other.snapshot()==valid,"corrupt XP is rejected atomically")
	check(hash(GameData.db.tables)==native,"native prototype tables unchanged")
	check_localized_roster()
	print("ARENA_ALLIANCES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func check_localized_roster() -> void:
	# Run with each edition's archives: native names come from texts.res, not
	# RemakeText. Proper names may legitimately match between EN and DE.
	var ids := {}
	for family: Dictionary in ArenaRules.FAMILIES:
		for id: String in family.forms: ids[id] = true
	for row: Array in ArenaRules.WAVES:
		for id: String in row.slice(1): ids[id] = true
	for id: String in ArenaRules.COMPANIONS: ids[id] = true
	for id: String in ids:
		var title := GameUnit.unit_title(id)
		check(not title.is_empty() and title!=id, "native creature has a localized display name: " + id)
		for spell: String in GameData.db.find("monster_prototypes",id).get("spells",[]):
			var parsed := Spells.parse(spell)
			if parsed.has("code"):
				var native_title:=GameData.text("spell "+String(parsed.code)).get_slice("\n",0).strip_edges()
				if not native_title.is_empty():
					check(WikiCatalog.spell_title(parsed.code)==native_title,"spell name comes from the loaded edition: "+str(parsed.code))
				else:
					check(WikiCatalog.SPELL_NAMES.has(parsed.code) and WikiCatalog.spell_title(parsed.code)==RemakeText.t(WikiCatalog.SPELL_NAMES[parsed.code]),"unnamed native spell has a translated display name: "+str(parsed.code))
