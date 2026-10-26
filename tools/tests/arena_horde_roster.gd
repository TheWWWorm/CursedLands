extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	check(ArenaRules.FAMILIES.size() > 38 and 38 in ArenaRules.ACTIVE_FAMILIES, "Orc archer is a base-game recruit")
	if ArenaRules.FAMILIES.size() <= 38: finish(); return
	var native := hash(GameData.db.tables)
	check(ArenaRules.FAMILIES[38].cost == 3 and ArenaRules.FAMILIES[38].tier == 3, "archer fills the three-gold ranged Horde role")
	check(ArenaAlliances.traits(38) == ["horde","hunter"], "archer has Horde and Hunter alliances")
	check(38 not in ArenaRules.recruit_pool(4) and 38 in ArenaRules.recruit_pool(5), "archer enters at the normal tier-three shop level")
	for star in 3:
		var proto := GameData.db.find("monster_prototypes",ArenaRules.prototype(38,star))
		check(not proto.is_empty() and ArenaRules.bow_user(proto) and proto.spells.is_empty(), "original bow kit exists at every star")
		check(float(proto.tuning_actions) == 101.0, "native slow bow cadence is preserved")
		var run := ArenaRun.new(); run.auto_save = false; run.begin(6291); run.army.clear()
		var entry := run._recruit(38,star,ArenaRules.FAMILIES[38].cost*int(pow(3,star)))
		run.items.assign([{"uid":1,"kind":"haste","unit_uid":0}]); run.next_item_uid=2
		check(run.equip_item(1,entry.uid).is_empty(), "archer accepts Swift Boots")
		var loaded := ArenaRun.new(); loaded.auto_save=false
		check(loaded.restore(JSON.parse_string(JSON.stringify(run.snapshot()))) and loaded.item_for(entry.uid)=="haste", "archer and item survive save/load")
		if star<2:
			for i in 2: run._recruit(38,star,3)
			run._merge(entry)
			check(run.army.size()==1 and run.army[0].rank==star+1 and run.item_for(entry.uid)=="haste", "promotion keeps the archer and equipment")
	for language in ["en","ru","de"]:
		RemakeText.lang=language
		for key in [ArenaRules.FAMILIES[38].name, ArenaRules.FAMILIES[38].hook, "Orc archer"]:
			check(not RemakeText.t(key).is_empty() and (language=="en" or RemakeText.t(key)!=key), "archer text localized: "+language)
	var old := ArenaRun.new(); old.auto_save=false; old.begin(9163); old._recruit(11,1,6); old.reserve_slots()
	var snapshot := old.snapshot(); snapshot.version=16
	var migrated := ArenaRun.new(); migrated.auto_save=false
	var restored := migrated.restore(snapshot)
	check(restored and migrated.army==old.army, "schema 16 keeps existing Woodsfolk identity")
	check(ArenaRules.saved_family_count(16)==38 and ArenaRules.saved_family_count(17)==39, "old schema cannot claim the new family id")
	check(ArenaOnlineSession.PROTOCOL==5, "new roster requires matching network rules")
	check(hash(GameData.db.tables)==native, "new recruit does not mutate campaign prototypes")
	finish()
func finish() -> void:
	print("ARENA_HORDE_ROSTER ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
