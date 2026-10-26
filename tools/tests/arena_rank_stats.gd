extends "arena_combat_effects.gd"
## Display values must agree with combat and keep the current star identifiable.
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "optional original recruits available")
	var native := hash(GameData.db.tables)
	for family: int in ArenaRules.active_families(true):
		for star in 3:
			for language in ["en", "ru", "de"]:
				RemakeText.lang = language
				var text := ArenaUnitInfo.summary(ArenaRules.prototype(family, star), null, family, star)
				check(text.count("[b]") >= 7 and text.count("[b]") == text.count("[/b]"), "all stats mark the current rank: %s/%s/%s" % [family,star,language])
				var health: int = ArenaUnitInfo.values(ArenaRules.prototype(family, star), null, family, star).max_hp
				check(text.contains("[b]%d[/b]" % health), "current maximum health is present without duplicate current/max")
				var proto := ArenaRules.recruit_prototype(family,star,GameData.db.find("monster_prototypes",ArenaRules.prototype(family,star)))
				var damaging: bool = proto.get("spells", []).any(func(spell): return Spells.DAMAGE_SCHOOLS.has(Spells.parse(spell).code))
				check(text.contains(RemakeText.t("Spells: ")) == damaging, "offensive casters disclose named spells and damage")
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		var text := ArenaUnitInfo.summary(ArenaRules.prototype(19, 1), null, 19, 1)
		var attack_label := {"en":"Attack ", "ru":"Атака ", "de":"Angriff "}
		check(text.contains(attack_label[language]) and not text.contains("Атаковать"), "attack stat uses the noun: " + language)
		check(text.contains(RemakeText.t("Spells: ") + RemakeText.t(WikiCatalog.spell_title("lightning")) + " ("), "spell name directly identifies its rank damage: " + language)
		var neutral := ArenaUnitInfo.summary("bansheedarkm12")
		check(not neutral.is_empty() and not neutral.contains("[b]") and neutral.contains(RemakeText.t("Spells: ")), "neutral caster has single-value stats without fabricated ranks: " + language)
	for star in 3:
		setup([3,5],[24],["focus"],[],star,false)
		var actor := own[0]
		var before := [actor.hp,actor.stats.duplicate(true),actor.buffs.duplicate(true)]
		var rows := ArenaUnitInfo.rank_values(3,star,actor,battle.run.army)
		check(rows[star].max_hp == ceili(actor.max_hp) and rows[star].min == int(actor.stats.dmg_min) and rows[star].actions == actor.actions(), "bold rank equals live preparation stats")
		for rank in 3:
			var parsed := Spells.parse(ArenaRules.recruit_prototype(3,rank,GameData.db.find("monster_prototypes",ArenaRules.prototype(3,rank))).spells[0])
			check(is_equal_approx(float(rows[rank].spells[0].damage), float(parsed.effect)*1.15+8), "all ranks include Mage alliance and fixed spell item")
		check(before == [actor.hp,actor.stats,actor.buffs], "reading rank comparisons cannot mutate the creature")
		battle.start()
		var target := enemies[0]; target.hp=10000; target.max_hp=10000
		target.stats.armor = PackedFloat32Array([0,0,0,0,0,0,0])
		var spell := Spells.parse(actor.proto.spells[0])
		var shown: float = ArenaUnitInfo.rank_values(3,star,actor,battle.run.army)[star].spells[0].damage
		Spells._spell_damage(battle.world,actor,spell,target)
		check(absf(10000-target.hp-shown)<0.01, "displayed spell damage matches a real unarmored hit")
		actor.hp -= 7
		check(ArenaUnitInfo.summary(actor.info.prototype,actor,-1,0,battle.run.army).contains(RemakeText.t("Remaining health: %d") % ceili(actor.hp)), "wounded creature shows remaining health separately")
	setup([11],[24],["haste"],[],1,false)
	check(ArenaUnitInfo.summary(own[0].info.prototype,own[0],-1,0,battle.run.army).contains("[b]18[/b]"), "Woodsfolk boots disclose the actual speed bonus")
	setup([3],[24],["berserker"],[],0)
	check(ArenaUnitInfo.summary(own[0].info.prototype,own[0]).contains(RemakeText.t("Casting disabled")), "disabled casting is explicit")
	check(hash(GameData.db.tables)==native, "stat presentation preserves original records")
	print("ARENA_RANK_STATS ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
