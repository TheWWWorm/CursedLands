extends Node
## Run separately with each campaign's original data. No save is required.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _ready() -> void:
	var st := CampaignState.new()
	st.ensure_hero(0,"Human Hero")
	var best := {}
	for school: String in Skills.SCHOOL:
		best[school] = Skills.knowledge(st.heroes[0][0],school)
	for id in Shops.records():
		if not Shops.sells_spells(id): continue
		var lists := Shops.lists(id,{})
		var templates := Shops._templates("spell_templates",lists)
		var runes := Shops._best_runes(lists.spell_modifiers)
		for caps in [best,{"*":0},{"*":5},{"*":25},{"*":100}]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 0
			var eligible := Shops._template_spells(templates,runes,caps,0,rng)
			for seed_value in 30:
				rng.seed = seed_value
				var goods := Shops.generate(id,{},caps,rng)
				var ready := goods.keys().filter(func(it):return String(it).begins_with("spell:"))
				check(eligible.is_empty() == ready.is_empty(),"shop %s seed %s retains feasible spells" % [id,seed_value])
				for item: String in ready:
					check(not Spells.parse(item.trim_prefix("spell:")).proto.is_empty(),"finished spell can be parsed")
					check(goods[item] == 1,"identical spell retries do not inflate stock")
	print("SHOP_SPELLS ",GameData.campaign_id," ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
