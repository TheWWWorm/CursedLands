extends "res://tools/tests/path_trace_camera_routes.gd"
## Actual tactical/shoulder/eye cameras and first-person figure visibility.
## Drive camera APIs without capturing the test cursor or issuing player input.
func run() -> void:
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1]
	var rt: Node=game.get_node("SceneRaytrace")
	var leader: GameUnit=game.direct.leader()
	check(leader!=null,"campaign has a selected player for camera switching")
	if leader==null:get_tree().quit(1);return
	var diagnostic_camera:=camera
	camera=game.rig.camera;camera.make_current();diagnostic_camera.queue_free()
	var tactical:=game.rig.pose()
	game.direct._set_view_mode(1)
	check(await ready_scene(rt),"tactical camera starts with a complete PT scene")
	for repeat in 3:
		for mode in [2,3,1]:
			game.direct._set_view_mode(mode)
			if mode==1:
				game.direct._update_view_model(null);game.rig.set_pose(tactical)
			else:game.direct.tilt=-0.12;game.direct.apply_camera()
			for i in 40:
				if mode!=1:
					game.direct.heading+=0.012;game.direct.apply_camera(1.0/30.0)
				await frames(1);observe(rt,"view-%d-round-%d"%[mode,repeat])
			await shot("view-%d-round-%d"%[mode,repeat])
	var inactive:=samples.filter(func(row: Dictionary):return not row.active or not row.global_active).size()
	check(inactive==0,"PT stays active through actual camera modes and turns: "+str(inactive))
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"development cursor stays free through all views")
	FileAccess.open(out.path_join("camera-modes.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"inactive_frames":inactive,"samples":samples,"stats":rt.stats},"\t"))
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
