extends Node
## Progression contracts, native late roster, shop arrivals and legacy saves.
const Fixture = preload("arena_fixture.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr("FAIL ",label)
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := ArenaRun.new();run.auto_save=false
	var restored := ArenaRun.new();restored.auto_save=false
	check(ArenaRules.WAVE_COUNT==30 and ArenaRules.WAVES.size()==30,"thirty authored waves")
	check(ArenaRules.FAMILIES.size()==12 and ArenaRules.available(),"twelve valid original families")
	for seed_value in range(8200,8203):
		Fixture.begin(run,seed_value)
		for wave in [1,9,10,12,13,18,19,30]:
			run.wave=wave
			var pool := ArenaRules.recruit_pool(wave)
			for family in pool:
				check(int(ArenaRules.FAMILIES[family].get("unlock",1))<=wave,"no later family appears before its arrival")
			for family in ArenaRules.FAMILIES.size():
				check(pool.has(family)==(int(ArenaRules.FAMILIES[family].get("unlock",1))<=wave),"unlocked families stay available")
			check(run.income_preview(30).base==5+ArenaRules.region(wave)*2,"bounty grows with recruitment costs")
		for milestone in [10,13,19]:
			run.wave=milestone-1;run._roll_shop(false);run.lock_offer(0)
			var locked := run.shop[0].duplicate(true)
			run._next_wave()
			check(run.shop[0]==locked,"arrival respects a saved offer")
			for family in ArenaRules.FAMILIES.size():
				if int(ArenaRules.FAMILIES[family].get("unlock",1))==milestone:
					check(run.shop.any(func(o):return int(o.family)==family),"first arrival shop guarantees each new family")
			check(restored.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"arrival shop reloads")
	for family in range(6,12):
		run.begin(8300+family);run.wave=int(ArenaRules.FAMILIES[family].unlock);run.gold=100;run._roll_shop(false)
		run.shop[0]={"family":family,"rank":0,"locked":false}
		check(run.buy(0).is_empty(),"late recruit can be bought")
		var uid := int(run.army[0].uid)
		run.deploy(uid,Vector2(27,32))
		run.shop[1]={"family":family,"rank":0,"locked":false}
		check(run.buy(1).is_empty() and run.unit(uid).rank==1,"later pair evolves immediately")
		check(run.unit(uid).prototype==ArenaRules.prototype(family,1) and run.unit(uid).deployed,"native evolution preserves formation")
		check(run.sale_value(run.unit(uid))<int(run.unit(uid).investment),"evolution cannot generate resale profit")
		check(restored.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"later forms reload")
		run.undo();check(run.unit(uid).rank==0 and run.army.size()==1,"late merge and spend undo together")
	for pact: String in ArenaRules.PACTS:
		Fixture.begin(run,8400);run.pact=pact
		for rank in 3:
			run.pact_rank=rank
			for wave in [9,10,19]:
				run.wave=wave
				check(not GameData.db.find("monster_prototypes",run.pact_prototype()).is_empty(),"every regional pact form is native")
	# Walk every camp with an exhausted boon pool; there must be no dead-end
	# choice, repeated maximum pact upgrade, or failed restore after wave 18.
	Fixture.begin(run,8401);run.boons.assign(["merchant","reserve","scout"]);run._roll_shop(false)
	for wave in 30:
		run.start_battle();run.resolve(0,10,[30,2]);run.advance()
		if run.stage=="reward":
			check(run.rewards.size() in [2,3],"late camps retain useful choices")
			check(not (run.rewards.any(func(r):return r.kind=="supplies") and run.rewards.any(func(r):return r.kind=="purse")),"no strictly worse gold choice")
			check(not run.rewards.any(func(r):return r.kind=="pact_upgrade" and run.pact_rank==2),"no spent pact upgrade")
			check(restored.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"each camp survives JSON save")
			check(run.choose_reward(0).is_empty(),"camp reward can be claimed")
		check(restored.restore(JSON.parse_string(JSON.stringify(run.snapshot()))),"progression survives each save")
	check(run.stage=="won" and run.wave==30,"expanded run reaches victory")
	var legacy := run.snapshot()
	legacy.version=4;legacy.wave=18;legacy.erase("wave_limit")
	legacy.last_result.wave=18;legacy.history=legacy.history.filter(func(r):return int(r.wave)<=18)
	legacy.army=legacy.army.filter(func(u):return u.family>=0 or u.prototype in ["orcfemalem3","orcfemalem5"])
	check(restored.restore(legacy) and restored.stage=="won" and restored.wave_limit==18,"completed legacy run stays completed")
	check(restored.restore(restored.snapshot()) and restored.wave_limit==18,"legacy completion survives migration and resave")
	legacy.stage="prepare";legacy.last_result={}
	check(restored.restore(legacy) and restored.wave_limit==30,"active older run can continue through thirty waves")
	check_localized_roster()
	check(hash(GameData.db.tables)==native,"all native combat stats preserved")
	print("ARENA_LONG_RUN ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func check_localized_roster() -> void:
	# Native editions supply their own names. The English reference also
	# exercises the remake fallbacks used by every localized UI fixture.
	if RemakeText.detect(GameData.texts) != "en": return
	var ids := {}
	for family: Dictionary in ArenaRules.FAMILIES:
		for id: String in family.forms: ids[id] = true
	for row: Array in ArenaRules.WAVES:
		for id: String in row.slice(1): ids[id] = true
	for pact: Dictionary in ArenaRules.PACTS.values():
		for id: String in Array(pact.forms) + Array(pact.later_forms[0]) + Array(pact.later_forms[1]): ids[id] = true
	for id: String in ArenaRules.COMPANIONS: ids[id] = true
	var titles := {}
	for id: String in ids:
		var title := GameUnit.unit_title(id)
		check(not title.is_empty(), "native creature has a display name: " + id)
		titles[title] = true
		for spell: String in GameData.db.find("monster_prototypes",id).get("spells",[]):
			var parsed := Spells.parse(spell)
			if parsed.has("code"): titles[Spells.title(parsed.code)] = true
	var previous := RemakeText.lang
	for lang: String in ["ru","de"]:
		RemakeText.lang = lang
		for title: String in titles:
			check(RemakeText.TEXTS.has(title) and RemakeText.t(title) != title, lang + " translates native creature/spell: " + title)
	RemakeText.lang = previous
