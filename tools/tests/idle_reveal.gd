extends Node
var s: Session
var g: Game
var rows := []
var checks := 0
var failures := 0
var cfg := {"save":"", "idle":60.0, "pause":60.0}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()
func seconds(n: float) -> void:
	await get_tree().create_timer(n,true,false,true).timeout
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func shot(label: String, cam: Camera3D, u: GameUnit) -> void:
	await RenderingServer.frame_post_draw
	var im := get_viewport().get_texture().get_image()
	im.save_png("user://"+label+".png")
	var count := 0
	var sum := Vector2.ZERO
	for y in range(200,im.get_height()-150):
		for x in range(250,im.get_width()-250):
			var c := im.get_pixel(x,y)
			if c.r > 0.7 and c.g < 0.2 and c.b < 0.2:
				count += 1
				sum += Vector2(x,y)
	var actual := sum/maxi(1,count)
	var expected := cam.unproject_position(EISpace.pos(u.pos.x,u.pos.y,s.world.ground_at(u.pos.x,u.pos.y)+0.4))
	var error := actual.distance_to(expected)
	var row := {"label":label,"count":count,"centroid":str(actual),"expected":str(expected),"error":error,"pos":str(u.pos),"drawn":str(u._drawn),"sleep":u._presentation_sleeping,"frame":u._frame_drawing}
	rows.append(row)
	print("IDLE_REVEAL ",JSON.stringify(row))
	checks += 1
	if count < 20 or error > 30:
		failures += 1
		printerr("FAIL ",label," rendered placement")
func run() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--config="): cfg.merge(JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--config="))),true)
	GameData.options.merge(GfxPresets.values(7),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"unit_fog":1},true)
	Engine.max_fps = 60
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(1280,720)
	s=Session.new();get_parent().add_child(s);g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	if String(cfg.save).is_empty(): await s.new_campaign(false)
	else:
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		var input := FileAccess.open(SaveInfo.path("idle"),FileAccess.WRITE)
		input.store_buffer(FileAccess.get_file_as_bytes(cfg.save))
		input.close()
		if not await s.load_game_shown("idle"):printerr("FAIL load");get_tree().quit(1);return
	var u:GameUnit = s.world.units[1890]
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color.RED;mat.no_depth_test=true
	for mesh:GeometryInstance3D in u._geoms:mesh.material_override=mat
	print("IDLE_START ",u.pos," visible=",u.visible," tree_interp=",get_tree().physics_interpolation)
	await seconds(float(cfg.idle))
	get_tree().paused=true
	print("IDLE_PAUSE ",u.pos," visible=",u.visible)
	await seconds(float(cfg.pause))
	get_tree().paused=false
	await frames(2)
	print("IDLE_END ",u.pos," visible=",u.visible," sleeping=",u._presentation_sleeping)
	g.get_node("UnitFog").set_process(false)
	var cam:=Camera3D.new();g.add_child(cam);cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=24
	var point:=EISpace.pos(u.pos.x,u.pos.y,s.world.ground_at(u.pos.x,u.pos.y))
	cam.position=point+Vector3(0,24,8);cam.look_at(point);cam.current=true
	if g.hud:g.hud.hide()
	u.fogged=false;u.show()
	await frames(2)
	await shot("reveal",cam,u)
	await frames(60)
	await shot("settled",cam,u)
	u.transform=u.transform
	await frames(2)
	await shot("root-refresh",cam,u)
	FileAccess.open("user://idle-reveal.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	await s.local_host.stop()
	print("IDLE_REVEAL_DONE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
