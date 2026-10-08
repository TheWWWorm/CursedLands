extends Node
## Personal hero/purse merge follows the same protagonist as the import.
## Complete party-context transfer is a separate concern: these cases all
## start with an existing chapter or temporary substitution in the recipient.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func merge_hero(st: CampaignState, strength: float, money: int, items: Array, move := false) -> void:
	var hero := CoopProgress.main_hero(st).duplicate(true)
	hero.str = strength
	hero.name = "Guest network name"
	hero.pos = Vector2(19, 27)
	var pkg := {"campaign_id":st.campaign_id, "hero":hero, "purse":{"money":money, "items":items}}
	if move: pkg.move = {"zone":"gz2h", "day":3, "world_time":8.5}
	CoopProgress.merge(st, pkg)

func chapter(st: CampaignState, name: String, unit: String, prototype: String) -> void:
	st.create_party(name)
	st.add_party_unit(name, unit, prototype)
	st.set_current_party(name)

func _ready() -> void:
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	var st := CoopProgress.fresh_state()
	st.heroes[0][0].name = "Personal name"
	st.heroes[0][0].str = 31.0
	st.money = 123
	st.items = ["rune:e1"]
	st.heroes[0][0].pos = Vector2(2, 3)
	var waiting_before: Dictionary = st.heroes[0][0].duplicate(true)
	if astral:
		chapter(st, "FPrison", "Hero", "Hero1")
		st.heroes[0][0].name = "Personal Kir"
		st.heroes[0][0].pos = Vector2(5, 6)
		merge_hero(st, 64, 9876, ["rune:it"])
		check(st.heroes[0][0].str == 64, "LiA chapter hero receives learned attributes")
		check(st.heroes[0][0].name == "Personal Kir", "chapter retains personal display name")
		check(st.heroes[0][0].unit_name == "Hero", "chapter retains original script identity")
		check(st.heroes[0][0].pos == Vector2(5, 6), "unmoved progress retains personal position")
		check(st.money == 9876 and st.items == ["rune:it"], "active chapter receives its own purse")
		check(st.parties[""][0] == waiting_before, "dormant opening hero remains intact")
		check(st.party_bags[""].money == 123 and st.party_bags[""].items == ["rune:e1"], "dormant opening bag remains intact")
		chapter(st, "FSusel", "Hero2", "Hero2")
		st.heroes[0][0].name = "Personal Kir"
		merge_hero(st, 71, 456, ["rune:ic"], true)
		check(st.heroes[0][0].str == 71 and st.heroes[0][0].unit_name == "Hero2", "later chapter receives progress with its own script name")
		check(st.current_zone == "gz2h" and st.heroes[0][0].pos == Vector2(19, 27), "credited travel uses received position")
		check(st.parties.FPrison[0].str == 64, "previous chapter remains waiting")
		chapter(st, "Shaina", "merc8", "merc8")
		st.money = 19
		st.items = ["rune:e1"]
		var shaina: Dictionary = st.heroes[0][0].duplicate(true)
		merge_hero(st, 83, 654, ["rune:it"])
		check(st.heroes[0][0] == shaina and st.money == 19 and st.items == ["rune:e1"], "temporary Shaina and her bag remain intact")
		check(st.parties.FSusel[0].str == 83 and st.party_bags.FSusel.money == 654 and st.party_bags.FSusel.items == ["rune:it"], "waiting Kir receives guest hero and purse")
		check(st.parties[""][0] == waiting_before and st.party_bags[""].money == 123, "temporary chapter does not overwrite pre-chapter record")
		st.set_current_party("FSusel")
		check(st.heroes[0][0].str == 83 and st.money == 654, "return from Shaina deploys updated Kir")
	else:
		chapter(st, "Pretty", "Nalo", "Human Hadagan Pretty")
		st.money = 19
		st.items = ["rune:ic"]
		var pretty: Dictionary = st.heroes[0][0].duplicate(true)
		merge_hero(st, 64, 456, ["rune:it"])
		check(st.heroes[0][0] == pretty and st.money == 19 and st.items == ["rune:ic"], "Nalo and her personal bag remain intact")
		check(st.parties[""][0].str == 64 and st.parties[""][0].name == "Personal name", "waiting Zak receives guest progress")
		check(st.party_bags[""].money == 456 and st.party_bags[""].items == ["rune:it"], "waiting Zak receives guest purse")
		st.set_current_party("")
		check(st.heroes[0][0].str == 64 and st.money == 456, "return from Nalo deploys updated Zak")
	var before := st.to_dict().duplicate(true)
	CoopProgress.merge(st, {"campaign_id":CampaignProfile.ORIGINAL if astral else CampaignProfile.ASTRAL, "hero":st.heroes[0][0], "purse":{"money":999,"items":[]}})
	check(st.to_dict() == before, "different campaign package changes nothing")
	var path := "user://progress-chapter.sav"
	check(st.save(path) == OK, "merged chapter saves")
	var restored := CampaignState.load_from(path)
	check(restored != null and restored.current_party == st.current_party and CoopProgress.main_hero(restored).str == CoopProgress.main_hero(st).str and CoopProgress.main_bag(restored) == CoopProgress.main_bag(st), "save reload preserves merged protagonist and purse")
	print("COOP_PROGRESS_CHAPTERS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
