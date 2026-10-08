extends Node
## Additive old-shop migration and normal replenishment. Uses the native
## runes and enchantment restrictions, including a saved sold-out shop.
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var added:=GameData.campaign_id!=CampaignProfile.ASTRAL
	var mods: Array=Shops.lists(2,{}).spell_modifiers.map(func(r):return String(r.code))
	for code: String in ["ic","it"]:
		check(mods.has(code)==(added or Items._in_shop(Spells.mod_row(code),1)),"witch infusion list follows campaign scope: "+code)
		check(Items.price("rune:"+code)>0 and not Items.look("rune:"+code).is_empty(),"native infusion has artwork and price: "+code)
	var rng:=RandomNumberGenerator.new()
	for value in 20:
		rng.seed=value
		var goods:=Shops.generate(2,{},{"*":100},rng)
		check(not added or (int(goods.get("rune:ic",0)) in range(20,51) and int(goods.get("rune:it",0)) in range(20,51)),"both native infusion runes appear at restock seed "+str(value))
	for id in [1,3,4,5]:
		var found: Array=Shops.lists(id,{}).spell_modifiers.map(func(r):return String(r.code))
		check([found.has("ic"),found.has("it")]==[Items._in_shop(Spells.mod_row("ic"),id-1),Items._in_shop(Spells.mod_row("it"),id-1)],"other trader keeps authored infusion mask "+str(id))
	Shops.network=true
	check(not Shops.exists(2),"native multiplayer trader table unchanged")
	Shops.network=false
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g);s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	var rec:={"restock":false,"goods":{"keystone:healing":2,"rune:ic":0},"sold":{"spell_prototypes":["healing"]}}
	s.state.shops[2]=rec
	s.open_shop(2)
	check(rec.goods["keystone:healing"]==2 and rec.goods["rune:ic"]==0 and rec.sold=={"spell_prototypes":["healing"]},"opening old shop preserves existing goods, sold prototypes and exhausted stock")
	check(int(rec.goods.get("rune:it",0))==(20 if added else 0),"old shop receives missing infusion stock once")
	if added:
		rec.goods["rune:it"]=0;s.open_shop(2)
		check(rec.goods["rune:it"]==0,"reopening cannot refill sold-out infusion stock")
	check(s.state.save("user://infusion_shop.sav")==OK,"shop record saves")
	s.state=CampaignState.load_from("user://infusion_shop.sav");s.open_shop(2);rec=s.state.shops[2]
	check(rec.goods["rune:ic"]==0 and int(rec.goods.get("rune:it",0))==0 and rec.goods["keystone:healing"]==2,"save/reload preserves exhausted stock and unrelated goods")
	s.restock_shops();s.open_shop(2);rec=s.state.shops[2]
	check(not added or (int(rec.goods.get("rune:ic",0))>=20 and int(rec.goods.get("rune:it",0))>=20),"normal quest replenishment includes both infusion runes")
	var fitting:={"weapon":false,"armor":false}
	# Verify original item prototypes/materials can use the supplied rune,
	# retaining their ordinary slot/energy restrictions.
	for table: String in ["weapons","armors"]:
		for row: Dictionary in GameData.db.table(table):
			for mat: Dictionary in GameData.db.table("materials"):
				if row.get("material_type")!=mat.get("type"):continue
				var id:=String(row.name).to_lower()+"."+String(mat.name).to_lower()
				if Items.can_enchant(id,"healing{ic}") or Items.can_enchant(id,"arrow{it}"):
					fitting["weapon" if table=="weapons" else "armor"]=true;break
			if bool(fitting["weapon" if table=="weapons" else "armor"]):break
	check(fitting.weapon and fitting.armor,"native weapon and armour recipes accept supplied infusion runes")
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	print("GIPAT_INFUSIONS ",GameData.campaign_id," ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
