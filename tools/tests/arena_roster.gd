extends Node
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _ready()->void:
	check(ArenaRules.ACTIVE_FAMILIES.size()==29 and ArenaRules.recruit_pool(3).size()==14,"expanded roster and opening pool")
	var tiers := [0,0,0,0,0]
	for family in ArenaRules.ACTIVE_FAMILIES: tiers[int(ArenaRules.FAMILIES[family].tier)-1]+=1
	check(tiers==[7,7,5,5,5],"every shop tier has multiple role and tribe choices")
	check(ArenaRules.available(),"every recruited form exists in the loaded localized game")
	var species := {}
	for family_id: int in ArenaRules.ACTIVE_FAMILIES:
		var family: Dictionary = ArenaRules.FAMILIES[family_id]
		check(family.cost==family.tier and family.cost in range(1,6),"price equals its 1–5 shop tier")
		check(family.copies==[3,3],"nine base copies earn a final form")
		var native_race: String=GameData.db.find("monster_prototypes",family.forms[0]).base_race
		check(not species.has(native_race), "recruitment has one visually identifiable family per native species")
		species[native_race]=family
		for index in 3:
			check(GameData.db.find("monster_prototypes",family.forms[index]).base_race==native_race,"all ranks retain the recruit's species")
	var native:=hash(GameData.db.tables)
	var caster:=GameUnit.new();caster.controller=-1
	var run:=ArenaRun.new();run.auto_save=false
	var sampled:={};var matching:=0;var pairs:=0
	for number in 200:
		run.begin(9710+number)
		var offered:={}
		for offer in run.shop:offered[offer.family]=true;sampled[offer.family]=true
		check(offered.size()==6,"opening contains distinct creatures")
		check(run.shop.any(func(o):return ArenaRules.FAMILIES[o.family].role=="Melee") and run.shop.any(func(o):return ArenaRules.FAMILIES[o.family].role!="Melee"),"opening provides front line and ranged choices")
		for refresh in 10:
			run._roll_shop(false)
			for a in run.shop.size():
				for b in range(a+1,run.shop.size()):
					pairs+=1
					if run.shop[a].family==run.shop[b].family:matching+=1
	check(sampled.size()==14,"all fourteen opening families appear across seeds")
	var duplicate_rate:=float(matching)/pairs
	check(duplicate_rate<0.12,"early pairwise duplicate rate stays below twelve percent")
	for family in range(ArenaRules.saved_family_count(15)):
		check(not ArenaAlliances.traits(family).is_empty(),"every recruit participates in alliances")
		for lang in ["en","ru","de"]:
			RemakeText.lang=lang
			check(lang=="en" or RemakeText.TEXTS.has(ArenaRules.FAMILIES[family].name),"family title localized")
		for rank in 3:
			run.begin(7719+family);run.army.clear();run._recruit(family,rank,1);run.arrange()
			var values:=ArenaUnitInfo.values(run.army[0].prototype,null,family,rank)
			check(values.hp>0 and values.max>0,"every recruit has combat stats")

			var row:=GameData.db.find("monster_prototypes",run.army[0].prototype)
			var tuned:=ArenaRules.recruit_prototype(family,rank,row)
			for spell:String in tuned.get("spells",[]):
				if Spells.offensive(spell):check(caster._spell_cost(Spells.parse(spell))==0.0,"recruited creature uses the native stamina-free casting rule")
			var loaded:=ArenaRun.new();loaded.auto_save=false
			check(loaded.restore(JSON.parse_string(JSON.stringify(run.snapshot()))) and loaded.army==JSON.parse_string(JSON.stringify(run.army)),"each form survives save and reload")
			if rank<2:
				var needed:=ArenaRules.evolution_copies(family,rank)
				for copy in needed-1:run._recruit(family,rank,1)
				run._merge(run.army[0])
				check(run.army.size()==1 and run.army[0].rank==rank+1,"every evolution recipe reaches the next form")
	# All forty schema-10 lineages, including removed indices, remain loadable.
	for family in ArenaRules.LEGACY_FORMS:
		for rank in 3:
			run.begin(8219); run.army.clear(); run._recruit(0,rank,27)
			var saved := run.snapshot(); saved.version=10
			saved.army[0].family=family; saved.army[0].prototype=ArenaRules.LEGACY_FORMS[family][rank]
			saved.shop[0].family=family
			var immutable := saved.duplicate(true)
			var loaded := ArenaRun.new(); loaded.auto_save=false
			check(loaded.restore(saved),"legacy lineage migrates")
			check(saved==immutable,"migration never mutates caller data")
			check(loaded.army[0].prototype==ArenaRules.prototype(ArenaRules.migrated_family(ArenaRules.LEGACY_FORMS[family][rank]),rank),"migration preserves star rank")
	# Ownership must not make a target family easier to roll.
	var empty := ArenaRun.new(); var committed := ArenaRun.new()
	empty.auto_save=false; committed.auto_save=false
	empty.begin(9919); committed.begin(9919)
	# A nonempty comparison avoids the empty-company recovery offer.
	empty._recruit(1,0,1); committed._recruit(0,1,3)
	for refresh in 200:
		empty._roll_shop(false); committed._roll_shop(false)
		check(empty.shop==committed.shop,"shop odds are independent of owned copies")
	check(hash(GameData.db.tables)==native,"roster tuning leaves native campaign data unchanged")
	caster.free()
	print("ARENA_ROSTER ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
