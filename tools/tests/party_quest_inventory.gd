extends Node
## Native transfer ordering and save compatibility, independent of map scripts.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func save_data(data: Dictionary, name: String) -> CampaignState:
	var path := "user://"+name+".sav"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_var(data); file.close()
	return CampaignState.load_from(path)

func _ready() -> void:
	var s := CampaignState.new()
	s.ensure_hero(0,"Human Hero")
	for name: String in ["A","B","C"]:
		s.create_party(name); s.add_party_unit(name,"Hero","Human Hero")
	s.set_current_party("A"); s.store_party_quest_items()
	s.quest_items["kel1"] = true
	check(s.party_quest_items.A.is_empty(),"new live fragment does not update its named snapshot")
	var saved := save_data(s.to_dict(),"unsynchronized")
	check(saved != null and saved.quest_items == {"kel1":true} and saved.party_quest_items.A.is_empty(),
		"save and reload preserve live inventory without synchronizing its archive")
	saved.move_loot("A","B",false); saved.set_current_party("B"); saved.store_party_quest_items()
	check(saved.quest_items.is_empty(),"unsynchronized AddLoot cannot transfer a newly given fragment")
	saved.set_current_party("A"); saved.store_party_quest_items()
	check(saved.quest_items == {"kel1":true},"return to source recovers its collected live fragment")
	s.store_party_quest_items()
	s.quest_items.erase("kel1")
	check(s.party_quest_items.A == {"kel1":true},"consuming live fragments leaves the stored snapshot intact")
	s.move_loot("A","B",false)
	check(s.party_quest_items.A == {"kel1":true} and s.party_quest_items.B == {"kel1":true},
		"AddLoot reads the stored source and preserves it")
	s.set_current_party("B")
	check(s.quest_party == "A" and s.quest_items.is_empty(),"selection does not deploy the target quest bag")
	s.move_loot("A","C",false)
	check(s.party_quest_items.C == {"kel1":true},"AddLoot after selection still reads the old loaded party snapshot")
	s = save_data(s.to_dict(),"pending-selection")
	check(s != null and s.current_party == "B" and s.quest_party == "A" and s.quest_items.is_empty(),
		"save retains a pending party selection and consumed live inventory")
	s.store_party_quest_items()
	check(s.quest_items == {"kel1":true} and s.party_quest_items.A.is_empty() and s.quest_party == "B",
		"redeployment collects old live bag and restores target's earlier copied fragment")
	s.quest_items["kel2"] = true
	check(s.party_quest_items.B == {"kel1":true},"loaded live inventory does not alias its archive")
	s.move_loot("C","C",true)
	check(s.party_quest_items.C.is_empty(),"native CopyLoot to itself clears the shared source and destination snapshot")
	s.move_loot("B","B",false)
	check(s.party_quest_items.B == {"kel1":true},"AddLoot to itself keeps set membership without importing live items")
	s.move_loot("A","B",true)
	check(s.party_quest_items.B.is_empty() and s.quest_items == {"kel1":true,"kel2":true},
		"CopyLoot to selected party replaces archive without changing its loaded items")
	s.set_current_party("C"); s.set_current_party("B")
	check(s.quest_items == {"kel1":true,"kel2":true} and s.quest_party == "B",
		"selecting away and back without deployment preserves the loaded inventory")
	s.store_party_quest_items()
	check(s.quest_items == {"kel1":true,"kel2":true} and s.party_quest_items.B == s.quest_items,
		"same-party collection replaces its archive with the actual live bag")
	s.set_current_party("C"); s.store_party_quest_items()
	s.quest_items.clear(); s.move_loot("B","C",false)
	check(s.quest_items.is_empty() and s.party_quest_items.C == {"kel1":true,"kel2":true},
		"AddLoot to deployed party affects only its stored bag")
	var legacy := s.to_dict().duplicate(true)
	legacy.erase("party_quest_items"); legacy.erase("quest_party")
	legacy.quest_items = {"note02":true}
	var migrated := save_data(legacy,"legacy")
	check(migrated != null and migrated.quest_items == {"note02":true} and migrated.quest_party == "C",
		"legacy load preserves its known live inventory and owner")
	check(migrated.party_quest_items == {"C":{"note02":true}},
		"legacy migration seeds only known active inventory without inventing inactive history")
	migrated.quest_items["kel3"] = true
	check(migrated.party_quest_items.C == {"note02":true},"migrated live and stored dictionaries are independent")
	var again := save_data(migrated.to_dict(),"migrated")
	check(again.quest_items == {"note02":true,"kel3":true} and again.party_quest_items.C == {"note02":true},
		"new saves after migration retain unsynchronized differences")
	again.store_party_quest_items()
	check(again.quest_items == {"note02":true,"kel3":true},"legacy inventory survives subsequent same-party travel")
	var alias := CampaignState.new()
	alias.quest_items = {"note02":true}; alias.items = ["stone axe.rock"]; alias.money = 7
	alias.store_party_quest_items()
	alias.move_loot("unknown-source","unknown-target",true)
	check(alias.party_quest_items[""].is_empty() and alias.quest_items == {"note02":true},
		"unknown party aliases clear the same stored main quest bag without changing live inventory")
	check(alias.items.is_empty() and alias.money == 7,"native self CopyLoot clears ordinary items while retaining money")
	print("PARTY_QUEST_INVENTORY %d checks %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
