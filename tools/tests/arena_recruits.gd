extends Node
## Appended recruit identities, original three-stage art, acquisition and saves.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	var native := hash(GameData.db.tables)
	var expected := {
		28: {"cost":2,"role":"Melee","traits":["horde","warrior"],"forms":["orcmalef3","orcmalef5","orcmalef7"]},
		29: {"cost":3,"role":"Magic","traits":["mage","spirit"],"forms":["driadgreenm7","driadsnowm9","driaddarkm11"]},
	}
	check(ArenaRules.VERSION == 14, "new roster uses schema 14")
	check(ArenaRules.saved_family_count(13) == 28, "published schema 13 keeps its original family bounds")
	for family: int in expected:
		var rule: Dictionary = ArenaRules.FAMILIES[family]
		check(rule.forms == expected[family].forms and rule.cost == expected[family].cost, "appended recruit identity %d" % family)
		check(ArenaAlliances.traits(family) == expected[family].traits, "recruit bridges its intended alliances %d" % family)
		var signatures := {}
		var race_name := ""
		for rank in 3:
			var id := ArenaRules.prototype(family, rank)
			var proto := GameData.db.find("monster_prototypes", id)
			var appearance := ArenaAppearance.info(id, family, rank)
			var race := GameData.db.find("race_models", proto.base_race)
			check(ArenaRules.recruit_role(family, rank) == expected[family].role, "native combat role is stable %d:%d" % [family,rank])
			if rank == 0: race_name = proto.base_race
			check(proto.base_race == race_name, "promotion retains its native body %d:%d" % [family,rank])
			var signature := [appearance.get("texture", ""), proto.skin, proto.hair, GameUnit.proto_complexion(proto), proto.weapon, proto.wears]
			check(not signatures.has(str(signature)), "each rank has a distinct original appearance %d:%d" % [family,rank])
			signatures[str(signature)] = true
			if family == 29:
				check(appearance.texture == ["driad00l","driad01l","driad02l"][rank], "seer uses the native clan leader palette %d" % rank)
				check(Array(race.textures).map(func(t):return t.to_lower()).has(appearance.texture) and GameData.textures.has(appearance.texture + ".mmp"), "leader palette belongs to this rig and exists")
			check(ArenaPortraits.texture(id, family, rank) != null, "every new rank has a real portrait %d:%d" % [family,rank])
			for language in ["en","ru","de"]:
				RemakeText.lang = language
				var title := ArenaRules.title(id, family, rank)
				check(not title.is_empty() and not title.to_lower().contains(id), "readable native name %d:%d:%s" % [family,rank,language])
				check(language == "en" or RemakeText.TEXTS.has(GameUnit.unit_title(id)), "native name translated %d:%d:%s" % [family,rank,language])
		RemakeText.lang = "en"
		var run := ArenaRun.new(); run.auto_save = false; run.begin(36791)
		run.gold = 100; run.army.clear()
		for copy in 9:
			run.shop[0] = {"family":family,"rank":0,"locked":false}
			check(run.buy(0).is_empty(), "normal purchase and merge %d:%d" % [family,copy])
		check(run.army.size() == 1 and run.army[0].family == family and run.army[0].rank == 2 and run.army[0].investment == rule.cost * 9, "nine purchases produce the native third stage %d" % family)
		var saved := run.snapshot()
		var restored := ArenaRun.new(); restored.auto_save = false
		check(restored.restore(saved) and restored.snapshot() == saved, "new recruit survives exact save round trip %d" % family)
		var invalid_old := saved.duplicate(true); invalid_old.version = 13
		check(not restored.restore(invalid_old), "new family cannot masquerade as a published schema-13 identity %d" % family)
	check(28 in ArenaRules.recruit_pool(3) and 29 not in ArenaRules.recruit_pool(3) and 29 in ArenaRules.recruit_pool(5), "new lines follow their existing tier unlocks")
	check(hash(GameData.db.tables) == native, "recruits leave native campaign data immutable")
	print("ARENA_RECRUITS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
