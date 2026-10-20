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
