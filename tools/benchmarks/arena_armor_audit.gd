extends Node
## Report native post-armor damage, not an HP/attack-only proxy. Uses the same
## per-type absorption, resistance ratios and 80% cap as playable Trials.
func _ready() -> void:
	var rows := []
	for family in ArenaRules.ACTIVE_FAMILIES:
		var run := ArenaRun.new(); run.auto_save=false; run.begin(8519)
		run.army.clear(); run._recruit(family,2,9); run.arrange()
		var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
		add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
		battle.prepare()
		var unit: GameUnit = battle.world.unit_rows()[0]
		var row := {"family":family,"id":unit.info.prototype,"title":ArenaRules.title(unit.info.prototype),
			"tier":ArenaRules.FAMILIES[family].tier,"hp":unit.max_hp,"armor":Array(unit.stats.armor),
			"attack_types":Array(unit.stats.dmg_types),"attack_min":unit.stats.dmg_min,"attack_max":unit.stats.dmg_max,
			"spells":unit.proto.spells,"regen":unit.stats.health_regen,"hits":[]}
		for raw in [12.0,30.0,70.0]:
			var damage := []
			for type in 7:
				var types := PackedFloat32Array([0,0,0,0,0,0,0]); types[type]=1
				damage.append(battle.world.combat.absorb(unit,raw,types))
			row.hits.append({"raw":raw,"after_armor":damage})
		rows.append(row); print("ARMOR_AUDIT ",JSON.stringify(row))
		battle.queue_free(); await get_tree().process_frame
	FileAccess.open("user://arena-armor-audit.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	get_tree().quit()
