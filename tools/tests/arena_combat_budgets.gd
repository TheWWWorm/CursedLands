extends Node
## Native-data isolation, live/preview agreement and regeneration behavior.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	var native := hash(GameData.db.tables)
	for family in ArenaRules.ACTIVE_FAMILIES:
		for rank in 3:
			var run:=ArenaRun.new();run.auto_save=false;run.begin(9917);run.army.clear()
			run._recruit(family,rank,1);run.army[0].deployed=true;run.army[0].point=[27.0,32.0]
			var battle:=ArenaPveMatch.new();battle.run=run;battle.rendered=false;battle.drives_clock=false
			add_child(battle);battle.set_process(false);battle.set_physics_process(false);battle._world_parent=self;battle.prepare()
			var unit:GameUnit=battle.world.unit_rows().filter(func(u):return u.faction==1)[0]
			var values:=ArenaUnitInfo.values(unit.info.prototype,null,family,rank)
			check(is_equal_approx(unit.max_hp,float(values.max_hp)),"preview and live health %d/%d"%[family,rank])
			check(is_equal_approx(unit.stats.dmg_min,float(values.min)) and is_equal_approx(unit.stats.dmg_max,float(values.max)),"preview and live attacks %d/%d"%[family,rank])
			check(is_equal_approx(unit.stats.actions,float(values.actions)),"preview and live cadence %d/%d"%[family,rank])
			check(battle.world.combat.defence_value(unit)==int(values.defense),"preview and live defense %d/%d"%[family,rank])
			unit.hp=unit.max_hp*0.5
			var before:=unit.hp
			unit._regenerate(GameUnit.TICK*15.0)
			# Native part health is stored as float32, then combined into health.
			# Compare within that storage precision, not float64 delta precision.
			check(absf(unit.hp-before-unit.max_hp*float(values.health_regen))<=maxf(0.0001,unit.max_hp*0.000001),"actual recovery uses Trials budget %d/%d"%[family,rank])
			check(float(values.health_regen)<=0.005001,"boss regeneration stays within round budget")
			var original:=unit.race.duplicate(true)
			unit.stats.erase("health_regen"); unit.hp=unit.max_hp*0.5; before=unit.hp
			unit._regenerate(GameUnit.TICK*15.0)
			check(absf(unit.hp-before-unit.max_hp*float(original.get("health_regen",0.0)))<=maxf(0.0001,unit.max_hp*0.000001),"unbudgeted actors retain native recovery")
			for lang in ["en","ru","de"]:
				RemakeText.lang=lang
				var summary:=ArenaUnitInfo.summary(unit.info.prototype,null,family,rank)
				check(not summary.is_empty() and (lang=="en" or not summary.contains("Recovery:")),"localized recovery summary")
			if family==20 and rank==1:
				var enemy:GameUnit=battle.world.unit_rows().filter(func(u):return u.faction==2)[0]
				unit.hp=unit.max_hp
				unit.order={"type":"attack","ai":true,"target":enemy}
				var choice:=battle.world.ai.choose(unit,[enemy])
				check(not choice.is_empty() and choice.opt.slot.begins_with("lightning"),"hybrid reconsiders its stronger spell against the last enemy")
				unit.stats.erase("trials_budget")
				choice=battle.world.ai.choose(unit,[enemy])
				check(not choice.is_empty() and choice.opt.slot.begins_with("lightning"),"native AI also evaluates all available actions against one enemy")
			if family==25 and rank==2:
				var damage_option:Dictionary=battle.world.ai.options(unit).a.filter(func(o):return o.slot.begins_with("curse_magic"))[0]
				check(damage_option.v[5]==175 and damage_option.v[6]==0,"Curse AI evaluates actual lightning damage rather than the knowledge school")
			if rank==2:
				for option:Dictionary in battle.world.ai.options(unit).b:
					if option.key not in ["infravision","silence"]: continue
					check(battle.world.ai._score(unit,unit,option,[unit],null,-INF)==UnitAI.NO_SCORE,"Trials prioritizes combat over "+option.key)
					unit.stats.erase("trials_budget")
					check(battle.world.ai._score(unit,unit,option,[unit],null,-INF)>UnitAI.NO_SCORE,"campaign retains "+option.key)
					unit.stats.trials_budget=true
			if family==20 and rank==2:
				var healing:Dictionary=battle.world.ai.options(unit).b.filter(func(o):return o.type==7)[0]
				unit.hp=unit.max_hp*0.8
				check(battle.world.ai._score(unit,unit,healing,[unit],null,-INF)==UnitAI.NO_SCORE,"Trials healer attacks through light wounds")
				unit.stats.erase("trials_budget")
				check(battle.world.ai._score(unit,unit,healing,[unit],null,-INF)>UnitAI.NO_SCORE,"campaign self-healing priorities are unchanged")
				unit.stats.trials_budget=true; unit.hp=unit.max_hp*0.4
				check(battle.world.ai._score(unit,unit,healing,[unit],null,-INF)>UnitAI.NO_SCORE,"Trials healer can recover below half health")
				check(not battle.world.ai._trials_protection_needed(unit,"fire"),"physical opponent does not prompt fire protection")
				var enemy:GameUnit=battle.world.unit_rows().filter(func(u):return u.faction==2)[0]
				enemy.proto=enemy.proto.duplicate(true); enemy.proto.spells=["arrow{}"]
				check(battle.world.ai._trials_protection_needed(unit,"fire"),"fire opponent makes fire protection useful")
			battle.queue_free();await get_tree().process_frame
	check(ArenaRules.recruit_role(17,2)=="Melee","noncasting hyena retains melee health and formation")
	for spell in ["inv_lit","acid_column","fireball"]:
		check(ArenaRules.spell_target_budget(Spells.parse(spell))>1.0,"area budget includes "+spell)
	check(ArenaRules.spell_target_budget(Spells.parse("lightning{t2}"))>ArenaRules.spell_target_budget(Spells.parse("lightning")),"extra bolts consume budget")
	var curse:=ArenaRules.recruit_prototype(25,2,GameData.db.find("monster_prototypes",ArenaRules.prototype(25,2)))
	check(Spells.parse(curse.spells[0]).code=="curse_magic" and Spells.parse(curse.spells[0]).effect<350.0 and curse._trials_cast_rate<1.0,"Curse retains its native spell with a smaller heavy hit and slower wind-up")
	check(hash(GameData.db.tables)==native,"Trials never mutate campaign data")
	print("ARENA_COMBAT_BUDGETS checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
