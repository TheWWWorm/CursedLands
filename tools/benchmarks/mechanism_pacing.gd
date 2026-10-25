extends Node
## Isolate a rendered authored mechanism update from unrelated AI. One original
## script tick per displayed frame: measures stalls, not wall-time lift speed.
var rows := []
func _ready() -> void:
	if DisplayServer.get_name()=="headless":get_tree().quit(2);return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"autosave":0,"show_tutorial":0,
		"auto_graphics":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_voice":0,"volume_stream":0,
		"fps_limit":0,"vsync":0,"display_mode":0,"pt_mode":0,"rtx_upscaling":0,"rtx_frame_generation":0},true)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var zone := "gz1h"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):zone=arg.trim_prefix("--zone=")
	var s := Session.new();add_child(s)
	var g := Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false);s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone(zone,1,false)
	var w := s.world;w.set_process(false);w.set_physics_process(false)
	for cls in 8:w.nav.native_graph(w.nav.layer(cls))
	w.vm.instances.clear()
	var nid := 2240358 if zone=="gz1h" else 1032949
	var p: Vector3=w.objects[nid].global_position
	g.rig.set_process(false);g.rig.global_position=p
	g.rig.camera.global_position=p+Vector3(10,18,16);g.rig.camera.look_at(p)
	for i in 90:await get_tree().process_frame
	if zone=="gz1h":
		w.vm.spawn("Lift#11",[w.objects[nid]])
		w.lever_sys.set_state(338779,1,0)
	var last := Time.get_ticks_usec()
	for i in (180 if zone=="gz1h" else 32):
		var start := Time.get_ticks_usec()
		if zone=="gz1h":w.vm.tick(GameWorld.TICK)
		else:w.lever_sys.set_state(nid,1-i%2,0)
		w.lever_sys.tick();w.time+=GameWorld.TICK
		var update := Time.get_ticks_usec()-start
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		rows.append({"frame":i,"frame_ms":(now-last)/1000.0,"update_ms":update/1000.0,
			"height":float(w.objects[nid].get_meta("ei").position.z)})
		last=now
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://mechanism-"+zone+".png")
	FileAccess.open("user://mechanism-"+zone+".json",FileAccess.WRITE).store_string(JSON.stringify({"zone":zone,"rows":rows,
		"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"scope":"Original mechanism scripts/state updates; other world simulation held, one logic tick per render frame, eight navigation classes. Measures mechanism stalls, not real-time trip duration or full gameplay FPS."},"\t"))
	var times := rows.map(func(row):return float(row.update_ms));times.sort()
	print("MECHANISM_PACING ",zone," updates=",rows.size()," median_ms=",times[times.size()/2]," max_ms=",times.back())
	g.queue_free();s.queue_free()
	for i in 5:await get_tree().process_frame
	get_tree().quit()
