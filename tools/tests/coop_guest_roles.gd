extends Node
## Original party instructions, distinct private/shared bags, temporary-role
## progression, late join and save reload. Network deployment is separate.
const Roles := preload("res://src/game/coop_guest_roles.gd")
const Progress := preload("res://src/game/coop_party_progress.gd")
var checks := 0
var failures := 0
var s: Session
var helper: Node
var entry: Dictionary
var original: Dictionary
var normal := ""

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_ev: Dictionary) -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func switch(mob: String, party: String, speaker := 1) -> void:
	s.coop.with_purse(speaker, func(): helper.transition(mob, party))
	check(s.state.current_party == party, "original host transition to " + party)
	check(s.state.heroes[1][0].name == "Network Guest", "live role keeps guest display name")
	check(s.coop._swap.is_empty(), "dialogue purse scope fully unwinds")

func lead(player := 1) -> Dictionary:
	return s.state.heroes[player][0]

func _ready() -> void:
	GameData.options["coop_share_loot"] = 0
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	s = QuietSession.new(); s.online = true
	s.coop = CoopProgress.new(); s.coop.session = s
	s.state = CoopProgress.fresh_state(); s.state.heroes[0][0].str = 91.0
	s.state.money = 9000; s.state.items = ["rune:r1"]
	s.state.ensure_hero(1, "Human Hero", "Network Guest")
	s.state.ensure_hero(2, "Human Hero", "Class Guest")
	s.state.heroes[2][0].unit_name = "Class::Guest"
	s.state.heroes[2][0].str = 43.0
	# Existing-slot rebinding preserves a network deployment name, which is
	# distinct from the original script's main-party Hero reference.
	s.state.ensure_hero(1, "Human Hero", "Network Guest")
	s.state.ensure_hero(2, "Human Hero", "Class Guest")
	lead().str = 31.0; lead().spells = ["fireball{e1}"]
	lead().pos = Vector2(20,30)
	original = lead().duplicate(true)
	var origin := CoopProgress.fresh_state()
	origin.heroes[0] = [original.duplicate(true)]; origin.heroes[0][0].name = "Personal Guest"
	origin.money = 222; origin.items = ["rune:e1"]
	entry = {"idx":1,"pid":2,"active":true,"in_sync":true,"clean":true,"present":true,
		"hero_in":original.duplicate(true),"orig_name":"Personal Guest","seq":0,
		"vars":{},"visited":{},"side_quests":{},"quest_items":{},
		"credits":{"vars":{},"visited":{},"side_quests":{},"quest_items":{},"zones":{}},
		"purse":{"money":222,"items":["rune:e1"]},"party_context":Progress.capture(origin)}
	s.coop.joiners.guest = entry
	s.world = GameWorld.new(); s.world.session = s
	helper = load(get_script().resource_path.get_base_dir()+"/coop_progress_context.gd").new()
	helper.s = s; helper.vm = ScriptVM.new(); helper.vm.session = s; helper.vm.world = s.world
	s.zone_id = "gz2h" if astral else "gz15h"
	if astral:
		switch("bz1h", "FPrison")
		switch("bz2h", "FSusel")
		normal = "FSusel"
		check(Roles.row(s.state,1).is_empty() and lead() == original, "permanent LiA chapter changes leave live guest hero intact")
		switch("bz5h", "Shaina", 2)
		check(lead().prototype == "merc8" and lead().str != 91.0 and lead().spells != original.spells, "Shaina guests use stock role abilities and equipment")
	else:
		switch("bz7g", "HeroAlone", 2)
		check(lead().prototype == "Human Hero Hadagan" and lead().str == 31.0, "captive guest has authored body and own stats")
		check(lead(2).str == 43.0, "network deployment names cannot break native stat copying")
		check(lead().spells != original.spells and entry.purse.money == 0 and entry.purse.items.is_empty(), "captive equipment and bag are restricted")
		check(Roles.personal(s,1,lead(),entry.purse).hero.spells == original.spells, "normal spells wait with original guest")
		lead().str = 34.0
		entry.purse.money = 17; entry.purse.items.append("rune:r2")
		s.coop.with_purse(2,func(): s.state.money += 11; s.state.items.append("rune:r3"))
		switch("bz13h", "Pretty")
		check(lead().prototype == "Human Hadagan Pretty" and lead().str != 91.0 and lead().str != 34.0, "Nalo guests use authored stats instead of normal hero")
		check(Roles.row(s.state,1).parties.HeroAlone[0].str == 34.0 and Roles.row(s.state,1).bags.HeroAlone.money == 17, "nested rescue parks captive progress and bag")
	var temp: String = s.state.current_party
	check(s.state.money == 0 and s.state.party_bags[normal].money == 9000, "host current and waiting bags stay independent")
	check(entry.purse.money == 0 and entry.purse.items.is_empty(), "private temporary role starts with empty bag")
	check(s.coop.purse_entry(2).get("purse",{}).get("money") == 0, "class guest cannot access waiting shared bag")
	check(s.state.party_records(1)[0].name != s.state.party_records(0)[0].name, "extra role does not duplicate narrative object name")
	lead().str = 37.0; lead().hp = 19.0; lead().pos = Vector2(55,66)
	s.coop.with_purse(1,func(): s.state.money += 13; s.state.items.append("rune:e2"))
	s.coop.with_purse(2,func(): s.state.money += 7; s.state.items.append("rune:e3"))
	check(entry.purse == {"money":13,"items":["rune:e2"]} and s.state.money == 0, "temporary private loot stays with that player")
	var pkg := s.coop.package(entry)
	check(pkg.hero.str == 31.0 and pkg.purse == {"money":222,"items":["rune:e1"]}, "temporary stats/loot do not overwrite main hero in progress package")
	var resumed := CoopProgress.fresh_state(); resumed.heroes[0][0].name = "Personal Guest"
	CoopProgress.merge(resumed,pkg)
	check(resumed.current_party == temp and resumed.heroes[0][0].str == 37.0 and resumed.money == 13 and resumed.items == ["rune:e2"], "credited save resumes guest's played temporary role and own loot")
	check(resumed.heroes[0][0].get("pos") == Vector2(55,66) and resumed.heroes[0][0].get("hp") == 19.0, "credited temporary role retains its own pose and health")
	check(CoopProgress.main_hero(resumed).str == 31.0 and CoopProgress.main_bag(resumed).money == 222, "independent load keeps normal hero and bag waiting")
	# A late visitor gets the same restriction without receiving quest credit.
	s.state.ensure_hero(3,"Human Hero","Late Guest"); s.state.heroes[3][0].str = 43.0
	check(Roles.ensure(s,3) and s.state.heroes[3][0].prototype == lead().prototype, "late class guest receives current temporary role")
	check(not Roles.ensure(s,3), "repeated deployment does not recreate role or duplicate inventory")
	var frozen: Dictionary = entry.party_context.duplicate(true)
	entry.clean = false
	var path := "user://guest-roles-roundtrip.sav"
	check(s.state.save(path) == OK, "host role journal saves")
	s.state = CampaignState.load_from(path)
	check(s.state != null, "host role journal reloads")
	entry.purse = Roles.row(s.state,1).purse
	Roles.ensure(s,1)
	check(lead().str == 37.0 and lead().hp == 19.0 and entry.purse.money == 13, "save/load retains live temporary progression")
	check(is_same(lead(),Roles.row(s.state,1).roster[0]), "loaded journal binds to the deployed character record")
	var legacy := CampaignState.load_from(path)
	var old_role := Roles.row(legacy,1)
	legacy.heroes[1] = old_role.parties[normal].duplicate(true)
	var old_bag: Dictionary = old_role.bags[normal].duplicate(true)
	legacy.coop.erase("guest_roles")
	check(legacy.save("user://guest-roles-legacy.sav") == OK, "write old-format unrestricted guest save")
	s.state = CampaignState.load_from("user://guest-roles-legacy.sav"); entry.purse = old_bag
	check(Roles.ensure(s,1) and lead().prototype == ("merc8" if astral else "Human Hadagan Pretty"), "old save projects unrestricted guest into current temporary role")
	check(Roles.personal(s,1,lead(),entry.purse).hero.spells == original.spells and Roles.personal(s,1,lead(),entry.purse).purse == old_bag, "legacy projection parks original gear and purse without loss")
	# The old-save guest can be disconnected while the host changes parties.
	s.state = CampaignState.load_from("user://guest-roles-legacy.sav"); entry.purse = old_bag.duplicate(true)
	Roles.operation(s,"SetCurrentParty",[0.0, "FSusel" if astral else "HeroAlone"])
	check(lead().prototype == (original.prototype if astral else "Human Hero Hadagan") and lead().str == 31.0,
		"offline guest from old save follows authored return before reconnect")
	s.state = CampaignState.load_from(path); entry.purse = Roles.row(s.state,1).purse; Roles.ensure(s,1)
	if astral:
		switch("bz5h", "FSusel", 2)
		check(lead() == original and entry.purse == {"money":222,"items":["rune:e1"]}, "Shaina return restores original guest and bag exactly")
		check(Roles.row(s.state,1).parties.Shaina[0].str == 37.0 and Roles.row(s.state,1).bags.Shaina.money == 13, "Shaina progression stays with Shaina")
		check(s.state.money == 9000 and s.state.items == ["rune:r1"], "class guest's Shaina bag is parked rather than leaking into normal shared bag")
	else:
		switch("zone15", "HeroAlone", 2)
		check(lead().str == 34.0 and entry.purse == {"money":17,"items":["rune:r2"]}, "Nalo return restores each captive's own earned progress")
		check(Roles.row(s.state,1).parties.Pretty[0].str == 37.0 and Roles.row(s.state,1).bags.Pretty.money == 13, "Nalo progression stays with Nalo")
		switch("bz13h", "", 2)
		check(lead().prototype == original.prototype and lead().str == 34.0 and lead().spells == original.spells, "rescue return copies earned captive stats but restores original gear")
		check(entry.purse.money == 239 and entry.purse.items == ["rune:e1","rune:r2"], "rescue return applies authored personal loot transfer once")
		check(s.state.money == 9011 and s.state.items == ["rune:r1","rune:r3"], "class captive loot returns once to shared bag without Nalo-only loot")
		check(s.coop.purse_entry(2).is_empty(), "class guest resumes the shared bag on return")
		entry.clean = true
		switch("bz7g", "JunParty")
		check(lead().prototype == "Jun Male Hero" and lead().str == 34.0 and lead().spells == original.spells, "Jun disguise copies guest stats and own equipment")
		check(entry.purse.money == 239 and entry.purse.items == ["rune:e1","rune:r2"], "Jun copies guest bag according to original script")
		check(Roles.row(s.state,2).purse.money == 0 and Roles.row(s.state,2).purse.items.is_empty(), "Jun does not clone shared host inventory for every class guest")
	check(entry.party_context == frozen if astral else true, "uncredited temporary return leaves progress context untouched")
	check(helper.failures == 0, "all original party operations executed")
	helper.free(); s.world.free(); s.coop.free(); s.free()
	print("COOP_GUEST_ROLES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
