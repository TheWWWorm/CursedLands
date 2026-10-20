extends "third_person_kbm.gd"
## Real camp command dispatcher and authored recipes. Resource conservation,
## rejected transactions, spell capacity and weapon-slot lifecycle.
func bag_counts(items: Array) -> Dictionary:
	var out := {}
	for item: String in items: out[item]=int(out.get(item,0))+1
	return out

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"confine_mouse":0,
		"net_lan":0,"net_directory":0,"net_upnp":0},true)
	s=Session.new(); add_child(s); s.set_physics_process(false)
	g=Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("bz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz1g",1,false)
	s.world.set_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear(); s.world.vm.briefings.active=""; s.world.vm.briefings._pending_dialog={}
	g.hud._dialog.hide(); hero=s.party_units(0)[0]; hero.blocked=false
	s.state.shops[1]={"restock":false,"goods":{},"sold":{}}
	mode="camp lifecycle"
	var cases:=0
	for bp: String in ["bp:stone axe","bp:gipat medium plate","bp:long sword"]:
		check(Items.valid_blueprint(bp),bp+" is an original constructible recipe")
		for mat: Dictionary in Items.materials_for(bp).slice(0,3):
			var material:=String(mat.name).to_lower()
			var ingredients: Array=[bp]
			for i in Items.components(bp): ingredients.append(Items.material_unit(material))
			var product:=bp.substr(3)+"."+material
			var price:=Items.construct_price(bp,material,"")
			check(price>0 and Items.can_deconstruct(product),product+" has a positive service fee and reversible recipe")
			s.state.items=ingredients.duplicate(); s.state.money=price-1
			s.apply_command({"t":"construct","shop":1,"bp":bp,"mat":material},0)
			check(s.state.items==ingredients and s.state.money==price-1,product+" unaffordable construction changes nothing")
			s.state.money=1000000
			s.apply_command({"t":"construct","shop":1,"bp":bp,"mat":"not_a_material"},0)
			check(s.state.items==ingredients and s.state.money==1000000,product+" invalid material consumes nothing")
			s.apply_command({"t":"construct","shop":1,"bp":bp,"mat":material},0)
			check(s.state.items==[product] and s.state.money==1000000-price,product+" construction consumes the complete recipe exactly once")
			s.apply_command({"t":"construct","shop":1,"bp":bp,"mat":material},0)
			check(s.state.items==[product] and s.state.money==1000000-price,product+" stale repeated construction cannot invent ingredients")
			var worn:=Items.with_wear(product,Items.durability(product)*0.25)
			s.state.items=[worn]
			var fee:=Items.deconstruct_price(worn); var money:=s.state.money
			s.apply_command({"t":"deconstruct","shop":1,"item":worn},0)
			check(bag_counts(s.state.items)==bag_counts(ingredients) and s.state.money==money-fee,product+" worn dismantling returns exact recipe components")
			s.apply_command({"t":"deconstruct","shop":1,"item":worn},0)
			check(bag_counts(s.state.items)==bag_counts(ingredients) and s.state.money==money-fee,product+" stale repeated dismantling has no second payout")
			cases+=1
	check(cases==9,"nine weapon/armour recipe and material combinations exercised")

	var h: Dictionary=hero.get_meta("hero")
	h.weapons=[]; h.weapon_slots=[]; h.armors=[]; h.spells=[]
	h.skills={"astral":100}; h.int=100.0
	Combat.hero_stats(hero,h)
	var weapons: Array=[]
	for i in 5: weapons.append(Items.with_wear("stone axe.rock",float(i)))
	s.state.items=weapons.duplicate()
	for item: String in weapons: s.apply_command({"t":"equip","unit":hero.uid,"item":item},0)
	check(h.weapons.size()==4 and s.state.items==[weapons[4]],"fifth carried weapon is rejected without removing it from the bag")
	s.apply_command({"t":"select_weapon","unit":hero.uid,"item":weapons[2]},0)
	check(h.weapons[0]==weapons[2] and Session.weapon_slots(h)==weapons.slice(0,4),"active weapon change preserves displayed slot order")
	s.apply_command({"t":"unequip","unit":hero.uid,"item":weapons[2]},0)
	check(h.weapons.size()==3 and h.weapons[0]==weapons[3] and s.state.items.has(weapons[2]),"removing active weapon selects the next cell and returns the same worn instance")
	var before: Array=h.weapons.duplicate()
	s.apply_command({"t":"unequip","unit":hero.uid,"item":weapons[0]},1)
	check(h.weapons==before,"foreign owner cannot remove equipment")

	s.state.items=[]
	for i in 9: s.state.items.append("spell:healing")
	for i in 9: s.apply_command({"t":"learn","unit":hero.uid,"item":"spell:healing"},0)
	check(h.spells.size()==8 and s.state.items==["spell:healing"],"eight duplicate spell objects fit; ninth remains in the bag")
	s.apply_command({"t":"unlearn","unit":hero.uid,"item":"spell:healing"},0)
	check(h.spells.size()==7 and s.state.items.count("spell:healing")==2,"unlearning returns one spell container")
	var known: Array=h.spells.duplicate(); var bag:=s.state.items.duplicate()
	s.world.zone.type="game"
	s.apply_command({"t":"learn","unit":hero.uid,"item":"spell:healing"},0)
	s.apply_command({"t":"unlearn","unit":hero.uid,"item":"spell:healing"},0)
	check(h.spells==known and s.state.items==bag,"field commands cannot change learned inventory")
	s.world.zone.type="brief"
	check(s.save_game("camp_actions")==OK,"camp transactions save")
	var saved:=CampaignState.load_from(SaveInfo.path("camp_actions"))
	check(saved!=null and saved.items==s.state.items and saved.heroes[0][0].spells==h.spells
		and saved.heroes[0][0].weapons==h.weapons,"equipment, spell duplicates and returned items survive save/load")
	g.queue_free(); s.queue_free(); await frames(8)
	print("CAMP_ACTION_LIFECYCLE ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
