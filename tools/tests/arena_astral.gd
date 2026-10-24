extends "arena_combat_effects.gd"
## Run with both editions registered only in an isolated test profile.
func _ready() -> void:
	var astral := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): astral = arg.trim_prefix("--astral-path=")
	var original_rows := {}
	for table in ["weapons", "armors", "materials", "monster_prototypes", "race_models"]:
		for row: Dictionary in GameData.db.table(table): original_rows[[table, String(row.name)]] = row.duplicate(true)
	GameData.campaign_roots.erase(CampaignProfile.ASTRAL)
	check(not ArenaExpansion.available() and not ArenaExpansion.mount(), "base-only installation cannot unlock expansion")
	GameData.campaign_roots[CampaignProfile.ASTRAL] = astral
	check(ArenaExpansion.available() and ArenaExpansion.mount(), "both installations unlock and mount expansion")
	if not ArenaExpansion.mounted(): get_tree().quit(1); return
	for key: Array in original_rows:
		check(GameData.db.find(key[0], key[1]) == original_rows[key], "source row preserved: " + str(key))
	var mounted_hash := hash(GameData.db.tables)
	check(ArenaExpansion.mount() and hash(GameData.db.tables) == mounted_hash, "mounting is idempotent")
	check(ArenaRules.available(), "standard arena remains available after mounting")
	for family: int in ArenaExpansion.FAMILIES:
		var rule: Dictionary = ArenaRules.FAMILIES[family]
		for rank_value in 3:
			var id := ArenaRules.prototype(family, rank_value)
			var row := GameData.db.find("monster_prototypes", id)
			check(not row.is_empty(), "native prototype " + id)
			check(ArenaRules.recruit_role(family, rank_value) == rule.role, "consistent role " + id)
			var look := ArenaAppearance.info(id, family, rank_value)
			var model := EIUnitModel.create(look, true)
			check(model != null and model.has_anim("cidle0") or model != null and model.anim_names().size() > 0, "native animated model " + id)
			if model: model.free()
		for lang in ["en", "ru", "de"]:
			RemakeText.lang = lang
			check(lang == "en" or RemakeText.t(rule.name) != rule.name, "localized family " + str(family) + lang)
			check(lang == "en" or RemakeText.t(rule.hook) != rule.hook, "localized hook " + str(family) + lang)
	RemakeText.lang = "en"
	var appearances := []
	for who: String in ArenaCommanders.choices(true): appearances.append_array(ArenaCommanders.skins(who))
	for id: String in appearances:
		check(ArenaCommanders.valid(id) == id, "valid native skin " + id)
		for language in ["en", "ru", "de"]:
			RemakeText.lang = language
			check(language == "en" or ArenaCommanders.skin_title(id) != ArenaCommanders.SKINS.get(ArenaCommanders.character(id), [["", "Original appearance", ""]])[maxi(0,ArenaCommanders.skins(id).find(id))][1], "localized skin " + id + language)
		RemakeText.lang = "en"
		var proto := GameData.db.find("monster_prototypes", ArenaCommanders.prototype(id))
		check(not proto.is_empty() and ArenaCommanders.title(id) != id, "native named commander " + id)
		var race := GameData.db.find("race_models", proto.base_race)
		var names := Portrait.proto_face_names(proto, race, Vector3.ZERO)
		var source := EIFigure.build_mesh(EIFigure.get_model(names[0]).parts.values()[0], DetailedHead.FIT_C)
		var original: PackedVector2Array = source.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var mapped: PackedVector2Array = DetailedHead._mesh(names[0]).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var matching := original.size() == mapped.size()
		for i in original.size():
			matching = matching and mapped[i].is_equal_approx(original[i] * 2.0 - Vector2(0, 1))
		check(matching, "bust face mapping matches original interface atlas " + id)
	check(ArenaCommanders.valid("hero:invalid") == "hero" and ArenaCommanders.valid("lia_hero:wrapped",false) == "hero", "unknown and unavailable skins normalize safely")
	check("hero" not in ArenaCommanders.opponents("hero:jun"), "skin never duplicates its character among NPCs")
	check(GameData.db.find("monster_prototypes", ArenaCommanders.prototype("lia_hero")).skin == 44, "Kir transformed skin uses native Hero4 identity")
	var standard := ArenaTournamentRun.new(); standard.auto_save = false; standard.begin(93013)
	var extra := ArenaTournamentRun.new(); extra.auto_save = false; extra.expansion = true; extra.commander = "lia_hero:wrapped"; extra.begin(93013)
	check(extra.rivals.all(func(r): return r.expansion), "every expansion company shares the roster")
	check(standard.save_path() != extra.save_path(), "expansion save is separate")
	check(standard.pool_left().size() == 29 and extra.pool_left().size() == 37, "separate shared recruit pools")
	var seen := {}
	for roll in 100:
		standard._roll_shop(false); extra._roll_shop(false)
		check(standard.shop.all(func(o): return o.family < 30), "standard shop excludes expansion " + str(roll))
		for offer in extra.shop: seen[offer.family] = true
	check(seen.has(30) and seen.has(31) and seen.has(32), "low-tier expansion creatures appear in real rolls")
	extra.gold = 100
	for copy in 3:
		extra.shop[0] = {"family":32,"rank":0,"locked":false}
		check(extra.buy(0).is_empty(), "purchase exploding rabbit " + str(copy))
	check(extra.army.size() == 1 and extra.army[0].rank == 1, "three rabbits merge once")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(extra.snapshot()))
	var restored := ArenaTournamentRun.new(); restored.auto_save = false
	check(restored.restore(snapshot) and restored.expansion and restored.commander == "lia_hero:wrapped", "expansion JSON save restores army, mode and identity")
	var restored_army := restored.army.duplicate(true)
	for pair in [["hero:hadagan", "hero"], ["lia_hero:armored", "lia_hero:unmasked"], ["lia_merc2:armored", "lia_merc2"]]:
		var old_skin := snapshot.duplicate(true)
		old_skin.commander = pair[0]
		check(restored.restore(old_skin) and restored.commander == pair[1] and restored.army == restored_army, "retired skin save preserves the face and army " + pair[0])
		var replica := ArenaOnlineView.new()
		ArenaOnlineView._copy_company(replica, old_skin)
		check(replica.commander == pair[1], "retired skin snapshot preserves the face " + pair[0])
		check(ArenaCommanders.skin_title(pair[0]) == ArenaCommanders.skin_title(pair[1]), "retired skin label uses the retained choice " + pair[0])
	snapshot.expansion = false
	check(not restored.restore(snapshot), "mixed-mode snapshot cannot import expansion recruits into standard mode")
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(standard.snapshot()))
	legacy.version = 15; legacy.erase("expansion")
	for rival in legacy.rivals: rival.version = 15; rival.erase("expansion")
	check(restored.restore(legacy) and not restored.expansion, "schema-15 standard saves remain readable")
	for rank_value in 3:
		setup([32,0], [0,0,0,0], [], [], rank_value)
		var rabbit := own[0]; var ally_health := own[1].hp
		for i in enemies.size(): enemies[i].pos = rabbit.pos + Vector2(1.0, i * 0.2)
		var fx := battle.world.arena_effects
		fx.tick(); check(not rabbit.dead and fx.rows[rabbit.uid].has("fuse"), "proximity arms visible fuse at star " + str(rank_value))
		battle.world.time += 0.59; fx.tick(); check(not rabbit.dead, "fuse does not detonate early")
		battle.world.time += 0.02; fx.tick()
		check(rabbit.dead and fx.totals.get("popper_blast",0) == 1, "one detonation at star " + str(rank_value))
		check(enemies.filter(func(u): return u.hp < u.max_hp).size() == 3, "blast affects at most three enemies")
		check(own[1].hp == ally_health, "blast does not hurt allies")
		var after := enemies.map(func(u): return u.hp)
		fx.on_death(rabbit,null); fx.tick()
		check(after == enemies.map(func(u): return u.hp), "death event and subsequent ticks cannot repeat a blast")
	setup([32], [4])
	enemies[0].pos = own[0].pos + Vector2(8,0)
	var hp := enemies[0].hp
	own[0].die(enemies[0])
	check(enemies[0].hp == hp, "ranged kill outside radius counters a rabbit")
	var signatures := []
	for repeat in 2:
		setup([32,33,35], [31,34,37])
		for tick in 1700:
			if battle.phase != ArenaMatch.Phase.FIGHT: break
			battle.simulate_tick()
		signatures.append([battle.winner, battle.world.time, battle.damage.duplicate(), battle.world.arena_effects.totals.duplicate()])
	check(signatures[0] == signatures[1], "native expansion combat is deterministic")
	check(hash(GameData.db.tables) == mounted_hash, "combat and portraits preserve all mounted source rows")
	print("ARENA_ASTRAL checks=",checks," failures=",JSON.stringify(failures)," battle=",JSON.stringify(signatures[0]))
	get_tree().quit(0 if failures.is_empty() else 1)
