extends "arena_equipment_ui.gd"
func _ready() -> void:
	if DisplayServer.get_name()=="headless":get_tree().quit(2);return
	OS.add_logger(errors);await frames(20)
	GameData._window_gen+=1;GameData.arena_mode=0
	get_tree().root.size=Vector2i(1280,800)
	screen=ArenaPveScreen.new();add_child(screen);await frames(15)
	screen._seed_input.text="7319";screen._begin();screen.run.auto_save=false
	var a:=screen.run._recruit(0,0,1);var b:=screen.run._recruit(1,0,1)
	a.deployed=false;b.deployed=false;screen.run.reserve_slots();screen._refresh();await frames(12)
	var aid:=int(a.uid);var bid:=int(b.uid)
	await click_control(reserve_button(aid))
	await click_control(screen._army_row.get_child(6))
	check(int(screen.run.unit(aid).bench_slot)==6,"one select then empty slot moves reserve")
	await click_control(reserve_button(aid));await click_control(reserve_button(bid))
	check(int(screen.run.unit(aid).bench_slot)==1 and int(screen.run.unit(bid).bench_slot)==6,"select then occupied slot swaps reserves")
	await start_drag(reserve_button(aid));await release_drag(screen._army_row.get_child(4).get_global_rect().get_center())
	check(int(screen.run.unit(aid).bench_slot)==4,"native drag into empty reserve slot")
	await start_drag(reserve_button(aid));await release_drag(reserve_button(bid).get_global_rect().get_center())
	check(int(screen.run.unit(aid).bench_slot)==6 and int(screen.run.unit(bid).bench_slot)==4,"native drag swaps occupied reserve slots")
	reserve_button(aid).grab_focus();await key(KEY_SPACE)
	screen._army_row.get_child(2).grab_focus();await key(KEY_SPACE)
	check(int(screen.run.unit(aid).bench_slot)==2,"keyboard moves reserve")
	var stale:={"arena_reserve":true,"uid":aid,"run":0,"screen":screen.get_instance_id()}
	check(not screen._can_drop_on_reserve(Vector2.ZERO,stale,reserve_button(bid)),"stale drag from another run rejected")
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang;screen._refresh();await frames(8)
		for slot in screen._army_row.get_children():bounded(slot,"localized reserve "+lang)
		await shot("reserve-moves-"+lang)
	check(errors.messages.is_empty(),"no runtime errors: "+JSON.stringify(errors.messages))
	print("ARENA_RESERVE_MOVES_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
