extends Node
## Frozen native 4K first-person views with the production colour pages
## disabled/enabled/disabled. Image-quality evidence, not live FPS acceptance.
var session: Session
var game: Game

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	var zone := "gz17h"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="): zone = arg.trim_prefix("--zone=")
	var view := SubViewport.new(); view.size = Vector2i(3840,2160); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_parent().add_child(view); reparent(view)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"display_mode":0,"control_mode":3,"pad_enabled":0,"scroll_border":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	Engine.max_fps = 0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	session = Session.new(); add_child(session); session.set_physics_process(false)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero"); session.state.world_time = 12
	await session.enter_zone(zone,1,false)
	session.world.set_physics_process(false); session.world.vm.instances.clear()
	var hero: GameUnit = session.world.party_units()[0]
	hero.blocked = false; game.selected.assign([hero]); game.rig.release()
	await frames(24)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(320,320)
	game.rig.set_process(false); game.direct.set_process(false); game.direct.pointer = false
	game.rig._window_focused = true
	var aim: Vector2 = session.world.terrain.size_ei()*0.5 - hero.pos
	game.direct.heading = atan2(aim.y,aim.x); game.direct.tilt = -0.12
	game.direct.apply_camera()
	Gfx.apply_quality(view)
	await frames(60)
	var cache := session.world.terrain.color_cache
	if not is_instance_valid(cache):
		push_error("No eligible production colour cache for "+zone);get_tree().quit(1);return
	Engine.time_scale=0.0
	var paused := []
	for node: Node in get_tree().root.find_children("*","",true,false):
		if node==self:continue
		paused.append([node,node.process_mode]);node.process_mode=Node.PROCESS_MODE_DISABLED
	process_mode=Node.PROCESS_MODE_ALWAYS
	var start_heading := game.direct.heading
	var rows := []
	var poses := [Vector2(0,-.12),Vector2(PI/2,-.12),Vector2(PI,-.12),Vector2(-PI/2,-.12),Vector2(0,-.6)]
	for pose in poses.size():
		game.direct.heading=start_heading+poses[pose].x;game.direct.tilt=poses[pose].y;game.direct.apply_camera()
		for enabled in [false,true,false]:
			cache.clear()
			if enabled:cache.refresh();cache.prepare(game.rig.camera)
			await frames(48)
			await RenderingServer.frame_post_draw
			var path := "user://suslanger-color-%d-%d.png"%[pose,rows.size()]
			view.get_texture().get_image().save_png(path)
			rows.append({"zone":zone,"pose":pose,"enabled":enabled,"path":path,"resident":cache._resident.size(),"bytes":cache._bytes,"camera":str(game.rig.camera.global_transform),"heading":game.direct.heading,"tilt":game.direct.tilt})
			print("SUSLANGER_COLOR_CAPTURE ",JSON.stringify(rows.back()))
	FileAccess.open("user://suslanger-color-quality.json",FileAccess.WRITE).store_string(JSON.stringify({"size":str(view.size),"rows":rows},"\t"))
	for row: Array in paused:
		if is_instance_valid(row[0]):row[0].process_mode=row[1]
	Engine.time_scale=1.0
	game.free();session.free();await frames(4);TexUpscale.shutdown();get_tree().quit()
