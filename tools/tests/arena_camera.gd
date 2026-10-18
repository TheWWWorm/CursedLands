extends "arena_expansion_ui.gd"
func _ready()->void:
	await frames(12);GameData.arena_mode=0
	screen=ArenaPveScreen.new();add_child(screen);await frames(6)
	screen._seed_input.text="7191";screen._begin();screen.run.auto_save=false
	check(not screen.run is ArenaTournamentRun,"fixture uses Trials of the Allods")
	var initial:=screen.field.yaw
	var turn:=InputEventKey.new();turn.pressed=true;turn.physical_keycode=KEY_E
	screen._unhandled_key_input(turn)
	check(screen.field.yaw!=initial,"E rotates challenge camera")
	var rotated:=screen.field.yaw
	screen._refresh();check(screen.field.yaw==rotated,"shop refresh retains camera angle")
	turn.physical_keycode=KEY_Q;screen._unhandled_key_input(turn)
	check(is_equal_approx(screen.field.yaw,initial),"Q rotates back")
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true
	screen.field._gui_input(press)
	var drag:=InputEventMouseMotion.new();drag.button_mask=MOUSE_BUTTON_MASK_MIDDLE;drag.relative=Vector2(40,0);drag.position=screen.field.size*.5
	screen.field._gui_input(drag)
	check(screen.field.yaw!=initial,"middle mouse drag rotates challenge camera")
	press.pressed=false;screen.field._gui_input(press)
	screen._show_menu();rotated=screen.field.yaw
	turn.physical_keycode=KEY_E;screen._unhandled_key_input(turn)
	check(screen.field.yaw==rotated,"menu suppresses camera rotation")
	screen._close_modal();turn.physical_keycode=KEY_HOME;screen._unhandled_key_input(turn)
	check(is_equal_approx(screen.field.yaw,initial) and screen.field.zoom==14.5,"Home restores starting view")
	for point_value in [Vector2(24,24),Vector2(32,32),Vector2(40,40)]:
		check(screen.field.ground_point(screen.field.screen_point(point_value)).distance_to(point_value)<0.2,"camera preserves ground picking")
	screen.queue_free();screen=null;await frames(4)
	print("ARENA_CAMERA ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
