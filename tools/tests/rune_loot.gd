extends Node
## Native Rune.<code> loot from the original Gipath wife, plus recovery of
## the exact strings retained in old bags, guest purses and trader stock.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	check(Items.from_spec("Rune.E1 [3]")==["rune:e1",3],"native rune stack preserves modifier and count")
	check(Items.parse_stack("rune.e2")==["rune:e2",1],"native rune loot uses the modifier ID")
	check(Items.parse_stack("bansheerune00")==["bansheerune00",1],"banshee treasure remains its own item")
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz3g",1,false)
	s.world.set_physics_process(false);s.world.vm.instances.clear()
	if not s.world.units.has(3323):s.world.vm._add_mob("zone3obr.mob")
	var wife: GameUnit=s.world.units.get(3323)
	check(wife!=null and "rune.e1" in Items.split_list(wife.proto.get("items",[])),"original Gipath wife carries native rune.e1")
	var hero: GameUnit=s.party_units(0)[0]
	hero.stats.dex=999.0
	s.steal(hero,wife) # her authored quest item first
	s.steal(hero,wife) # then her remaining prototype loot
	check(s.state.items.has("rune:e1") and not s.state.items.has("rune.e1"),"stealing actual prototype loot grants the usable rune")
	check(Items.sell_price(String(s.state.items[0]))>0,"stolen rune has its modifier's sale value")
	wife.die(hero);s.take_loot(hero,wife)
	check(s.state.items.count("rune:e1")==1,"death after theft does not duplicate the rune")
	var saved:=CampaignState.new();saved.ensure_hero(0,"Human Hero")
	saved.items=["rune.e1","rune.e1","rune:e2","rune","rune.unknown","bansheerune00"]
	saved.money=321
	saved.party_bags["Waiting"]={"items":["rune.r2"],"money":432}
	saved.coop={"host":{"joiners":{"guest":{"purse":{"items":["rune.t1"],"money":543}}}}}
	saved.shops[2]={"goods":{"rune.e1":2,"rune:e1":3,"rune.unknown":1}}
	check(saved.save("user://legacy_runes.sav")==OK,"legacy inventory fixture saves")
	var loaded:=CampaignState.load_from("user://legacy_runes.sav")
	check(loaded.items==["rune:e1","rune:e1","rune:e2","rune","rune.unknown","bansheerune00"] and loaded.money==321,"load repairs only recognized codes and preserves all copies and money")
	check(loaded.party_bags.Waiting=={"items":["rune:r2"],"money":432},"waiting party keeps its recovered rune")
	check(loaded.coop.host.joiners.guest.purse=={"items":["rune:t1"],"money":543},"guest keeps its own recovered rune")
	check(loaded.shops[2].goods=={"rune:e1":5,"rune.unknown":1},"saved shop merges canonical stock without losing copies")
	loaded.save("user://recovered_runes.sav")
	check(CampaignState.load_from("user://recovered_runes.sav").to_dict()==loaded.to_dict(),"recovered save is stable across another load")
	check(CoopProgress._items(["rune.e1","rune.e1"])==["rune:e1","rune:e1"],"old co-op imported bags keep and recover both runes")
	var look:=Items.look("rune:e1")
	check(not look.is_empty() and GameData.has_figure(String(look.get("model",""))+".fig") and GameData.textures.has(String(look.get("texture",""))+".mmp"),"recovered modifier has original model and artwork")
	if DisplayServer.get_name()!="headless":
		var row:=HBoxContainer.new();add_child(row);row.position=Vector2(200,150)
		for id: String in ["rune.e1",String(loaded.items[0])]:
			var col:=VBoxContainer.new();row.add_child(col)
			var label:=Label.new();label.text=Items.title(id)+" — "+str(Items.sell_price(id));col.add_child(label)
			var view:=ItemView.new();view.custom_minimum_size=Vector2(250,250);col.add_child(view);view.show_item(id)
		for i in 8:await get_tree().process_frame
		check(get_viewport().get_texture().get_image().save_png("user://recovered-rune.png")==OK,"rune recovery comparison captured")
		row.queue_free()
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	print("RUNE_LOOT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
