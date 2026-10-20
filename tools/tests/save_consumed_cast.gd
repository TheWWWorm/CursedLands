extends "save_depth.gd"
func summary_marker() -> String: return "SAVE_CONSUMED_CAST"
func probe_cast() -> void:
	var h:=hero();h.hp=h.max_hp*0.4;h.facing=0.0
	var item:="";var spell:=""
	for row:Dictionary in GameData.db.table("quick_items"):
		var name:=String(row.get("name","")).to_lower()
		var sp:=Items.potion_spell(name)
		if int(row.get("item_id",0))==8 and sp.begins_with("healing"):
			item=name;spell=sp;break
	check(not item.is_empty(),"original database supplies a healing potion")
	if item.is_empty():return
	var hp_before:=h.hp;var rec:Dictionary=h.get_meta("hero");rec.quick=[item]
	h.order={"type":"cast","spell":spell,"target":h,"point":h.pos,"item":item};h._do_cast(GameUnit.TICK)
	check(rec.quick.is_empty() and h.hp==hp_before,"normal potion cast consumes the item before healing")
	check(timers()!=null and timers().pending.size()==1,"consumed potion has a delayed effect")
	if not timers():return
	result.before={"hp":h.hp,"item":item,"spell":spell,"quick":rec.quick.duplicate(),"delay":timers().pending[0].left}
	check(s.save_game("deep-potion")==OK,"save after potion consumption succeeds")
	drain();check(h.hp>hp_before,"control: potion heals without reloading");result.control_hp=h.hp
	check(s.load_game("deep-potion"),"reload consumed potion cast");stop();h=hero();drain()
	result.after={"hp":h.hp,"quick":h.get_meta("hero").quick,"pending":timers().pending.size() if timers() else 0}
	check(h.get_meta("hero").quick.is_empty(),"consumed potion remains absent after load")
	check(h.hp>hp_before,"loaded consumed potion delivers its paid healing")
