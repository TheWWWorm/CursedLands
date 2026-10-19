extends Node
## Export real tuned combatants and native post-armor samples for analysis.
func _ready() -> void:
	var rows := []
	var native := hash(GameData.db.tables)
	for family in ArenaRules.ACTIVE_FAMILIES:
		for rank in 3:
			var run := ArenaRun.new(); run.auto_save=false; run.begin(8519)
			run.army.clear(); run._recruit(family,rank,1); run.arrange()
			var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
			add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
			battle.prepare()
			var unit: GameUnit=battle.world.unit_rows()[0]
			var spells := []
			for spec: String in unit.proto.get("spells",[]):
				var p := Spells.parse(spec)
				spells.append({"code":p.code,"effect":p.get("effect",0),"area":p.get("area",0),"targets":p.get("targets",1),
					"actions":p.proto.get("actions",0),"duration":p.get("duration",0),"target_budget":ArenaRules.spell_target_budget(p)})
			var row := {"family":family,"rank":rank,"name":ArenaRules.FAMILIES[family].name,"cost":ArenaRules.FAMILIES[family].cost,
				"role":ArenaRules.recruit_role(family,rank),"hp":unit.max_hp,"armor":Array(unit.stats.armor),
				"attack":unit.stats.to_hit,"defense":unit.stats.parry,"actions":unit.stats.actions,"cadence":unit.proto.get("tuning_actions",0),
				"attack_types":Array(unit.stats.dmg_types),"min":unit.stats.dmg_min,"max":unit.stats.dmg_max,
				"spells":spells,"regen":unit.stats.health_regen,"planner_power":ArenaBotPlanner.power(family,rank),"hits":[]}
			for raw in [12.0,30.0,70.0]:
				var damage := []
				for type in 7:
					var types := PackedFloat32Array([0,0,0,0,0,0,0]); types[type]=1
					damage.append(battle.world.combat.absorb(unit,raw,types))
				row.hits.append({"raw":raw,"after_armor":damage})
			rows.append(row)
			battle.queue_free(); await get_tree().process_frame
	FileAccess.open("user://arena-balance-catalog.json",FileAccess.WRITE).store_string(JSON.stringify({"units":rows,"odds":ArenaRules.SHOP_ODDS,"xp":ArenaRules.LEVEL_XP},"\t"))
	assert(hash(GameData.db.tables)==native)
	print("BALANCE_CATALOG units=",rows.size()," native_absorption_samples=",rows.size()*21)
	get_tree().quit()
