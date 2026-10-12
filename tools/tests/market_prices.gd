extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var horn: String = Items.from_spec("Wand 5.Dragon Green Bones[acid_fog{r2;a2}]")[0]
	var inf := Items.info(horn)
	var native_price := int(float(inf.row.price) + float(inf.mat.price) + float(Spells.parse(Items.spell_of(horn)).price))
	check(Items.price(horn) == maxi(1,native_price), "signed quest-wand adjustment and all runes enter the completed price once")
	if GameData.campaign_id == CampaignProfile.ORIGINAL:
		check(Items.price(horn) == 2000 and Items.sell_price(horn) == 1000, "authored green dragon horn sells for 1000 gold")
		check(Items.price("wand 5.dragon green bones") == 1, "an incomplete negative-price item cannot credit money")
	check(Items.price(Items.with_charge(horn, 40.0)) == Items.price(horn), "remaining wand charge does not change its price")
	var enchanted := "long sword.steel|weak{it}"
	check(Items.price(enchanted) == Items.price(Items.plain(enchanted)) + Items.price("spell:weak{it}"), "ordinary enchanted equipment includes its complete spell once")

	var s := Session.new(); add_child(s); s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	var g := Game.new();g.session=s;s.game=g;add_child(g)
	await s.enter_zone("bz1g" if GameData.campaign_id == CampaignProfile.ORIGINAL else "bz1h",1,false)
	s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	s.state.set_var(0,"constr.current",1)
	s.state.shops[1]={"restock":false,"goods":{},"sold":{}}
	var panel:InventoryPanel=g.hud._inventory;panel.open(true,1)
	var camp:CampView=panel._camp;camp.set_process(false);camp.set_mode("itemconstr")
	for item: String in ["stone axe.rock", "gipat medium plate.thin", enchanted]:
		var i:=Items.info(item);var bp:=Items.blueprint(item);var mat:=String(i.material);var spell:=Items.spell_of(item)
		var fee:=int(Items.price(item)*0.05)
		s.state.items=[bp]
		for n in Items.components(bp):s.state.items.append(Items.material_unit(mat))
		if spell:s.state.items.append("spell:"+spell)
		s.state.money=1000000
		camp.c_bp=bp;camp.c_mat=mat;camp.c_spell=spell;camp.c_ready=""
		check(camp.constr_cost()==fee, "displayed assembly fee is 5% of "+item)
		s._construct({"shop":1,"bp":bp,"mat":mat,"spell":"spell:"+spell if spell else ""})
		check(s.state.items==[item] and s.state.money==1000000-fee, "authority assembles and charges the displayed fee for "+item)
		camp.c_ready=item
		check(camp.constr_cost()==fee, "displayed disassembly fee includes the full item value")
		s._deconstruct({"shop":1,"item":item})
		check(s.state.money==1000000-2*fee and s.state.items.has(bp), "authority disassembles for the same 5% fee")
		check(s.state.items.count(Items.material_unit(mat))==Items.components(bp) and (not spell or s.state.items.has("spell:"+spell)), "disassembly returns every component and enchantment")
	# Missing pieces still cost their purchase price in addition to service.
	s.state.items=["bp:stone axe"];s.state.money=1000000
	var n:=Items.components("bp:stone axe")
	s.state.shops[1].goods={"material.rock":n}
	var cost:=Items.construct_price("bp:stone axe","rock")+n*Items.buy_price("material.rock")
	var before:=s.state.items.duplicate();s.state.money=cost-1
	s._construct({"shop":1,"bp":"bp:stone axe","mat":"rock"})
	check(s.state.items==before and s.state.money==cost-1, "unaffordable assembly changes neither money nor pieces")
	s.state.money=cost
	s._construct({"shop":1,"bp":"bp:stone axe","mat":"rock"})
	check(s.state.items==["stone axe.rock"] and s.state.money==0 and s.state.shops[1].goods.get("material.rock",0)==0, "missing components are purchased and service rounds only once")
	s.state.items=[horn];s.state.money=0
	check(s._trade_apply({"shop":1,"buy":[],"sell":[horn]}) and s.state.money==Items.sell_price(horn), "actual confirmed sale uses the corrected horn price")
	var hero:GameUnit=s.party_units(0)[0]
	var h:Dictionary=hero.get_meta("hero")
	for stat in ["str","dex","int"]:h[stat]=100
	hero.max_mana=10000
	s.state.shops[3]={"restock":false,"goods":{},"sold":{}}
	panel.open(true,3);camp.set_mode("spellconstr")
	s.state.items=["keystone:fireball","rune:e1"];s.state.money=1000000
	camp.s_spell="fireball";camp.s_kind="keystone";camp.s_from="bag"
	camp.s_runes=["rune:e1"];camp.s_rune_from=["bag"]
	var fee:=int(Items.price("spell:fireball{e1}")*0.05)
	check(camp._spell_deal()[1]==fee,"spell assembly display charges 5% of the complete spell")
	var result:=s._spell_constr_apply({"shop":3,"unit":hero.uid,"pile":[["keystone:fireball","bag"],["rune:e1","bag"]]},0)
	check(not result.is_empty() and s.state.money==1000000-fee and s.state.items==["spell:fireball{e1}"],"spell assembly authority matches the displayed fee")
	camp.s_spell="fireball{e1}";camp.s_kind="spell";camp.s_runes=[];camp.s_rune_from=[]
	check(camp._spell_deal()[1]==fee,"spell disassembly displays the same 5% fee")
	result=s._spell_constr_apply({"shop":3,"unit":hero.uid,"pile":[["spell:fireball{e1}","bag"]]},0)
	check(not result.is_empty() and s.state.money==1000000-2*fee and s.state.items==["keystone:fireball","rune:e1"],"spell disassembly charges 5% and returns its keystone and rune")
	Items.coef=Shops.coef(5)
	if GameData.campaign_id == CampaignProfile.ORIGINAL:
		check(Items.construct_price("bp:stone axe","rock")==0 and Items.deconstruct_price(enchanted)==0, "authored free trader retains free service")
	Items.coef=Items.COEF
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	TexUpscale.shutdown()
	print("MARKET_PRICES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
