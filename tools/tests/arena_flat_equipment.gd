extends "arena_combat_effects.gd"
## Player-visible preparation values, fixed star-independent budgets, native spells.
func unit_for(uid: int) -> GameUnit:
	for actor: GameUnit in battle.world.unit_rows():
		if actor.get_meta("arena_placement", {}).get("run_uid", -1) == uid and actor.faction == 1: return actor
	return null

func _ready() -> void:
	for rank in 3:
		for spec in [["vitality", "health", 40.0], ["blade", "dmg_min", 5.0], ["haste", "actions", 3.0], ["mail", "armor", 4.0]]:
			setup([0], [24], [spec[0]], [], rank, false)
			var actor := own[0]
			var base: Dictionary = actor.get_meta("arena_combat_base")
			var delta := actor.max_hp - float(base.hp) if spec[1] == "health" else float(actor.stats.armor[0]) - float(base.stats.armor[0]) if spec[1] == "armor" else float(actor.stats[spec[1]]) - float(base.stats[spec[1]])
			check(is_equal_approx(delta, spec[2]), "%s adds a fixed amount at star %d during preparation" % [spec[0], rank + 1])
			check(battle.world.arena_effects == null, "preparation cannot trigger combat effects")
			var shown := ArenaUnitInfo.values(actor.info.prototype, actor)
			check(shown.max_hp == ceili(actor.max_hp) and shown.min == int(actor.stats.dmg_min), "inspection uses the prepared budget")
			var before := [actor.max_hp, actor.stats.duplicate(true)]
			battle.start()
			check([actor.max_hp, actor.stats] == before, "bell preserves the preview without adding equipment twice")
		setup([3], [24], ["focus"], [], rank)
		var target := enemies[0]
		target.max_hp = 500; target.hp = 500
		target.stats.armor = PackedFloat32Array([0,0,0,0,0,0,0])
		var fx := battle.world.arena_effects
		fx.rows[own[0].uid].item = ""
		Spells._spell_damage(battle.world, own[0], Spells.parse("arrow{t2}"), target)
		var unarmed := 500 - target.hp
		target.hp = 500
		fx.rows[own[0].uid].item = "focus"
		Spells._spell_damage(battle.world, own[0], Spells.parse("arrow{t2}"), target)
		check(absf((500 - target.hp) - unarmed - 8.0) < 0.01, "native spell gains eight damage at star %d" % (rank + 1))
		setup([0], [24], ["fang"], [], rank)
		own[0].hp = own[0].max_hp * 0.4
		var before := own[0].hp
		hit(own[0], enemies[0])
		check(absf(own[0].hp - before - 4.0) < 0.001, "life steal restores four health regardless of stars")
	setup([0,1], [24], ["vitality"], [], 0, false)
	var first := int(battle.run.army[0].uid); var second := int(battle.run.army[1].uid)
	var hp1 := own[0].max_hp - 40; var hp2 := own[1].max_hp
	check(battle.run.equip_item(1, second).is_empty(), "item can move before the bell")
	battle.prepare()
	check(is_equal_approx(unit_for(first).max_hp, hp1) and is_equal_approx(unit_for(second).max_hp, hp2 + 40), "moving equipment immediately updates both health labels")
	check(battle.run.equip_item(1, 0).is_empty(), "equipment can return to inventory")
	battle.prepare()
	check(is_equal_approx(unit_for(first).max_hp, hp1) and is_equal_approx(unit_for(second).max_hp, hp2), "removal restores both native budgets")
	for lang in ["en", "ru", "de"]:
		RemakeText.lang = lang
		for kind: String in ArenaItems.RULES:
			var description := ArenaItems.description(kind, false)
			check(description.length() <= 280 and description.split("\n").size() <= 2, "compact localized item identity: " + lang + "/" + kind)
	var old := ArenaTournamentRun.new(); old.auto_save = false; old.commander = "merc3"; old.begin(7191)
	var data := old.snapshot(); data.erase("commander")
	for rival: Dictionary in data.rivals: rival.erase("commander")
	var restored := ArenaTournamentRun.new(); restored.auto_save = false
	check(restored.restore(data) and restored.commander == "hero", "older saves receive a valid default character")
	check(restored.rivals.map(func(r):return r.commander) == ArenaCommanders.opponents("hero"), "older NPCs receive distinct companion faces")
	print("ARENA_FLAT_EQUIPMENT ", checks, " failures=", JSON.stringify(failures))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
