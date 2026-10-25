extends "arena_equipment_ui.gd"
## Real users move the mouse slightly between press and release. The old
## modal input handler released focus then, cancelling the first click.
func single_click(control:Control)->void:
	await frames(8)
	var p:=control.get_global_rect().get_center()
	await move(p)
	var press:=InputEventMouseButton.new();press.position=p;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
	Input.parse_input_event(press);await frames(2)
	var motion:=InputEventMouseMotion.new();motion.position=p+Vector2(1,1);motion.relative=Vector2(1,1);motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion);await frames(2)
	var release:=InputEventMouseButton.new();release.position=motion.position;release.button_index=MOUSE_BUTTON_LEFT
	Input.parse_input_event(release);await frames(8)
func _ready()->void:
	if DisplayServer.get_name()=="headless":get_tree().quit(2);return
	OS.add_logger(errors);await frames(20);GameData._window_gen+=1;GameData.arena_mode=0
	get_tree().root.size=Vector2i(1280,800)
	screen=ArenaPveScreen.new();add_child(screen);await frames(15)
	screen._seed_input.text="7319";screen._begin();screen.run.auto_save=false
	for i in 3:
		screen.run.offer_items_after([3,5,10][i]);screen.run._touch();await frames(10)
		check(screen._modal_layer.visible,"reward menu opened")
		var kind:=screen.run.item_offers[i]
		await single_click(screen._equipment_panel._offer_row.get_child(i))
		check(screen.run.items.any(func(item):return item.kind==kind) and not screen._modal_layer.visible,"first click accepts reward "+str(i))
		# Avoid hanging later cases on an intentionally failing old build.
		if screen._modal_layer.visible:screen._choose_item(i);await frames(8)
		screen._cancel_item()
		var uid:=int(screen.run.items.back().uid)
		await single_click(screen._item_tray.buttons[uid])
		check(screen._item_uid==uid,"first click selects owned item "+str(i))
		screen._cancel_item()
	check(errors.messages.is_empty(),"no runtime errors: "+JSON.stringify(errors.messages))
	print("ARENA_ITEM_FIRST_CLICK ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
