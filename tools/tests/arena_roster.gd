extends Node
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _ready()->void:
	check(ArenaRules.FAMILIES.size()==40 and ArenaRules.recruit_pool(3).size()==16,"expanded roster and opening pool")
	var tiers := [0,0,0,0,0]
	for family: Dictionary in ArenaRules.FAMILIES: tiers[int(family.tier)-1]+=1
	check(tiers==[7,9,10,8,6],"every shop tier has multiple role and tribe choices")
	check(ArenaRules.available(),"every recruited form exists in the loaded localized game")
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
	check(sampled.size()==16,"all sixteen opening families appear across seeds")
	var duplicate_rate:=float(matching)/pairs
	check(duplicate_rate<0.12,"early pairwise duplicate rate is below the old 19.3 percent")
	for family in ArenaRules.FAMILIES.size():
		check(not ArenaAlliances.traits(family).is_empty(),"every recruit participates in alliances")
		for lang in ["en","ru","de"]:
			RemakeText.lang=lang
			check(lang=="en" or RemakeText.TEXTS.has(ArenaRules.FAMILIES[family].name),"family title localized")
		for rank in 3:
			run.begin(7719+family);run.army.clear();run._recruit(family,rank,1);run.arrange()
			var values:=ArenaUnitInfo.values(run.army[0].prototype,null,family,rank)
			check(values.hp>0 and values.max>0,"every recruit has combat stats")
			if family in [11,36] and rank==2:
				var stats := {"armor":values.armor.duplicate()}
				# Rebuild the raw value before applying the same combat adjustment.
				for type in stats.armor.size():stats.armor[type]*=150.0/44.0
				ArenaRules.recruit_stats(family,rank,stats)
				check(is_equal_approx(values.armor[6],44.0) and stats.armor==values.armor,"inspector and combat use the same recruit armor")
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
	check(hash(GameData.db.tables)==native,"roster tuning leaves native campaign data unchanged")
	caster.free()
	print("ARENA_ROSTER checks=",checks," opening_pair_duplicate_rate=",duplicate_rate," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
