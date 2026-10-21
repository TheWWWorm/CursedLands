extends "save_depth.gd"
func summary_marker() -> String: return "PICKUP_MESSAGES"

func probe_cast() -> void:
	game.hud._field_on=true;game.hud._esc_open=false;game.hud._dialog.hide();game.hud._inventory.hide();game.hud._journal.hide();game.hud._side_quests.hide();game.hud._travel.hide()
	var item:=Items.material_unit("steel")
	game.hud._log.clear();s.notify_got(0,[item,item,item])
	var text:=game.hud._log.get_parsed_text().strip_edges()
	check(text.count("\n")==0 and "x3" in text and Items.log_name(item) in text,"three identical pickups form one localized x3 line")
	game.hud._log.clear();s.notify_got(0,[item+"[2]",item])
	check("x3" in game.hud._log.get_parsed_text(),"explicit stack and individual pickup counts combine")
	game.hud._log.clear();s.notify_got(0,[item,Items.material_unit("bronze"),item],7)
	text=game.hud._log.get_parsed_text().strip_edges()
	check(text.count("\n")==2 and "x2" in text,"different material and money keep separate lines")
	game.hud._log.clear();s.notify_got(0,[item,item],0,true)
	check(GameData.text("string combat_crippled").strip_edges() in game.hud._log.get_parsed_text() and "x2" in game.hud._log.get_parsed_text(),"broken-item notice retains its translated label")
	var corpse:GameUnit=candidates()[0]
	corpse.dead=true;corpse.set_meta("looted",false);corpse.set_meta("loot",[item+"[3]"])
	game.hud._log.clear();s.take_loot(hero(),corpse)
	check("x3" in game.hud._log.get_parsed_text(),"real corpse-loot event retains the native stack count")
	var thin := Items.material_unit("thin")
	var eight := [thin,thin,thin,thin,thin,thin,thin,thin]
	game.hud._log.clear();s.notify_got(0,eight)
	var own := game.hud._log.get_parsed_text().strip_edges()
	var pickup := GameData.text("string combat_picked_up").strip_edges()
	var description := own.trim_prefix(pickup+" ")
	check(own.count(Items.log_name(thin))==1 and "x8" in own,"finder sees one thin-leather x8 description")
	var event := {"t":"loot_copy","to":s.my_index,"who":"Worm","items":eight,"money":0}
	game.hud._log.clear();s._on_event(event)
	text=game.hud._log.get_parsed_text().strip_edges()
	check(text==RemakeText.t("%s found %s — you get a copy too.") % ["Worm",description],"shared recipient sees the same grouped description as the finder")
	check(text.count(Items.log_name(thin))==1 and "x8" in text,"shared notice prints the thin-leather name only once")
	event.items=[thin+"[6]",thin,thin];event.who=""
	game.hud._log.clear();s._on_event(event)
	check(game.hud._log.get_parsed_text().strip_edges()==RemakeText.t("The party got %s — you get a copy too.") % description,"party reward combines explicit stacks with individual copies")
	event.items=[thin,Items.material_unit("bronze"),thin];event.who="Worm";event.money=7
	game.hud._log.clear();s._on_event(event)
	text=game.hud._log.get_parsed_text().strip_edges()
	check(text.count(Items.log_name(thin))==1 and text.count(Items.log_name(Items.material_unit("bronze")))==1 and "x2" in text and "7" in text,"mixed shared reward retains distinct names, counts and money")
	event.items=[];event.money=19
	game.hud._log.clear();s._on_event(event)
	check("19" in game.hud._log.get_parsed_text() and not "x" in game.hud._log.get_parsed_text(),"money-only shared reward retains its localized format")
	event.to=s.my_index+1;event.items=eight
	game.hud._log.clear();s._on_event(event)
	check(game.hud._log.get_parsed_text().is_empty(),"another recipient's copy event remains hidden")
	var gear := "gipat medium plate.thin"
	var worn := Items.with_wear(gear,1.0)
	game.hud._log.clear();s.notify_got(0,[gear,worn])
	own=game.hud._log.get_parsed_text().strip_edges()
	event.to=s.my_index;event.items=[gear,worn];event.money=0
	game.hud._log.clear();s._on_event(event)
	text=game.hud._log.get_parsed_text().strip_edges()
	check(worn!=gear and own.count("\n")==1 and text.count(Items.log_name(gear))==2 and not "x2" in text,"different equipment states keep separate descriptions on both peers")
