extends "arena_expansion_ui.gd"
func _ready()->void:
	await frames(12);GameData.arena_mode=0
	screen=ArenaPveScreen.new();add_child(screen);await frames(6)
	screen._seed_input.text="7191";screen._begin();screen.run.auto_save=false
	check(not screen.run is ArenaTournamentRun,"fixture uses Trials of the Allods")
	await move(Vector2(500,350))
	check((screen.field.get_global_transform_with_canvas()*screen.field.pointer_position()).distance_to(Vector2(500,350))<0.01,"event pointer retains exact viewport coordinates")
	var old_position:=screen.field.position
	screen.field.position+=Vector2(13,7)
	check((screen.field.get_global_transform_with_canvas()*screen.field.pointer_position()).distance_to(Vector2(500,350))<0.01,"stationary pointer follows changed UI transform without an OS poll")
	screen.field.position=old_position
	var initial:=screen.field.yaw
	var turn:=InputEventKey.new();turn.pressed=true;turn.physical_keycode=KEY_E
	screen._unhandled_key_input(turn)
	check(screen.field.yaw==initial,"keydown does not jump camera")
	await frames(12)
	check(screen.field.yaw!=initial,"E rotates challenge camera")
	var rotated:=screen.field.yaw
	screen._refresh();check(screen.field.yaw==rotated,"shop refresh retains camera angle")
	turn.pressed=false;screen._input(turn)
	screen.field.reset_camera()
	turn.physical_keycode=KEY_Q;turn.pressed=true;screen._unhandled_key_input(turn)
	await frames(12)
	check(screen.field.yaw>initial,"held Q continuously rotates back")
	turn.pressed=false;screen._input(turn);screen.field.reset_camera()
	turn.pressed=true
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_MIDDLE;press.pressed=true
	screen.field._gui_input(press)
	var drag:=InputEventMouseMotion.new();drag.button_mask=MOUSE_BUTTON_MASK_MIDDLE;drag.relative=Vector2(40,0);drag.position=screen.field.size*.5
	screen.field._gui_input(drag)
	check(screen.field.yaw!=initial,"middle mouse drag rotates challenge camera")
	press.pressed=false;screen.field._gui_input(press)
	var cancellations := [0]
	screen.field.cancel_requested.connect(func():cancellations[0]+=1)
	press.button_index=MOUSE_BUTTON_RIGHT;press.pressed=true;screen.field._gui_input(press)
	check(cancellations[0]==0,"right press waits to distinguish click from drag")
	drag.button_mask=MOUSE_BUTTON_MASK_RIGHT;screen.field._gui_input(drag)
	rotated=screen.field.yaw
	press.pressed=false;screen.field._gui_input(press)
	check(cancellations[0]==0 and rotated!=initial,"right drag rotates without cancelling placement")
	press.pressed=true;screen.field._gui_input(press)
	press.pressed=false;screen.field._gui_input(press)
	check(cancellations[0]==1,"stationary right click still cancels placement")
	var angles := []
	for fps in [30,60,120]:
		screen.field.reset_camera()
		for i in fps: screen.field.advance_camera(1.0/fps,1.0)
		for i in fps: screen.field.advance_camera(1.0/fps,0.0)
		angles.append(screen.field.yaw)
	check(absf(angles[0]-angles[2])<0.03,"continuous rotation agrees at 30 and 120 FPS")
	# The screen receives scaled deltas; camera motion is measured in wall time.
	var speed_angles := []
	var drag_angles := []
	screen.set_process(false)
	for rate in [1.0,2.0]:
		Engine.time_scale=rate;screen.field.reset_camera()
		turn.physical_keycode=KEY_E;turn.pressed=true;screen._unhandled_key_input(turn)
		for i in 120: screen._process(rate/120.0)
		speed_angles.append(screen.field.yaw)
		turn.pressed=false;screen._input(turn);screen.field.reset_camera()
		press.button_index=MOUSE_BUTTON_RIGHT;press.pressed=true;screen.field._gui_input(press)
		drag.button_mask=MOUSE_BUTTON_MASK_RIGHT;screen.field._gui_input(drag)
		press.pressed=false;screen.field._gui_input(press)
		drag_angles.append(screen.field.yaw)
	check(is_equal_approx(speed_angles[0],speed_angles[1]),"held camera rotation has the same speed at 1x and 2x")
	check(is_equal_approx(drag_angles[0],drag_angles[1]),"right drag has the same sensitivity at 1x and 2x")
	Engine.time_scale=1.0;screen.set_process(true);turn.pressed=true
	screen.field.reset_camera()
	screen._show_menu();rotated=screen.field.yaw
	turn.physical_keycode=KEY_E;screen._unhandled_key_input(turn)
	check(screen.field.yaw==rotated,"menu suppresses camera rotation")
	await frames(4)
	check(screen.field.yaw==rotated,"menu stops held rotation and its release tail")
	screen._close_modal();turn.physical_keycode=KEY_HOME;screen._unhandled_key_input(turn)
	check(is_equal_approx(screen.field.yaw,initial) and screen.field.zoom==14.5,"Home restores starting view")
	for point_value in [Vector2(24,24),Vector2(32,32),Vector2(40,40)]:
		check(screen.field.ground_point(screen.field.screen_point(point_value)).distance_to(point_value)<0.2,"camera preserves ground picking")
	turn.physical_keycode=KEY_E;screen._unhandled_key_input(turn)
	screen._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(screen._camera_keys.is_empty() and screen.field._yaw_velocity==0,"focus loss clears held rotation")
	screen.queue_free();screen=null;await frames(4)
	print("ARENA_CAMERA ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
