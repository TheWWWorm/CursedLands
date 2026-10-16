extends Node
## Compare the Mobile program with inactive water reflections removed against
## its original uniform-disabled path on a frozen production map.
## Repeated references detect animated or unsettled pixels.
var checks := 0
var failures := 0
var rows := []
var extra_options := {}
var wet_weather := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(seconds: float) -> void:
	var end := Time.get_ticks_usec()+int(seconds*1000000)
	while Time.get_ticks_usec() < end: await get_tree().process_frame

func difference(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var peak := 0; var changed := 0; var over := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		peak = maxi(peak,d); changed += int(d > 0); over += int(d > 2)
	return {"changed_pixels":changed,"pixels_over_2":over,"peak":peak}

func programs(enabled: bool) -> void:
	Gfx._specialize_mobile_water = enabled
	for entry: Array in Gfx._made:
		var shader: Shader = entry[0].get_ref()
		if is_instance_valid(shader): shader.code = Gfx.compose(entry[1],entry[2],entry[3])

func freeze(node: Node) -> void:
	# World explicitly uses PAUSABLE and some effects use ALWAYS, so disabling
	# only their Game parent does not stop their independent process groups.
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children(): freeze(child)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	if RenderingServer.get_current_rendering_method() != "mobile" or DisplayServer.get_name() == "headless":
		printerr("MOBILE_WATER_RENDER requires the Mobile renderer"); get_tree().quit(2); return
	seed(151015)
	GameData.options.merge(GfxPresets.values(GfxPresets.MEDIUM),true)
	GameData.options.merge(extra_options,true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0,"show_tutorial":0,"scroll_border":0,"village_start_view":0},true)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(1920,1080)
	Gfx._specialize_mobile_water = false
	var session := Session.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0)); session.state.world_time = 12.0
	await session.enter_zone("gz1g",1,false)
	session.set_physics_process(false); game.world.set_physics_process(false)
	game.world.vm.briefings._check = INF; game.rig.set_process(false)
	await frames(12.0)
	freeze(game); freeze(session)
	var time_scale_before := Engine.time_scale
	Engine.time_scale = 0.0 # Hold shader TIME too; frames() uses wall-clock time.
	game.hud.hide()
	if wet_weather: Gfx.set_surface_weather(0.8,0.9)
	var terrain := game.world.terrain
	for along: float in [0.0,80.0,160.0]:
		var at := Vector2(terrain.size_ei().x*.22+along,terrain.size_ei().y*.45)
		var focus := Vector3(at.x,terrain.height_at(at.x,at.y),-at.y)
		game.rig.global_position = focus; game.rig.camera.global_position = focus+Vector3(0,34,24)
		game.rig.camera.look_at(focus); game.rig.reset_physics_interpolation()
		terrain.color_cache.prepare(game.rig.camera)
		programs(false); await frames(12.0)
		var before := get_viewport().get_texture().get_image()
		programs(true); await frames(12.0)
		var after := get_viewport().get_texture().get_image()
		programs(false); await frames(3.0)
		var repeat := get_viewport().get_texture().get_image()
		var delta := difference(before,after); var control := difference(before,repeat)
		check(control.changed_pixels == 0,"frozen reference is stable at "+str(along))
		check(delta.pixels_over_2 == 0,"production pixels preserved at "+str(along))
		rows.append({"along":along,"candidate":delta,"reference_repeat":control})
		before.save_png("user://mobile-water-render-%d-reference.png" % int(along))
		after.save_png("user://mobile-water-render-%d-candidate.png" % int(along))
		repeat.save_png("user://mobile-water-render-%d-reference-repeat.png" % int(along))
		print("MOBILE_WATER_COMPARE ",along," ",JSON.stringify(rows.back()))
	Gfx._specialize_mobile_water = true
	Engine.time_scale = time_scale_before
	game.free(); session.free(); TexUpscale.shutdown()
	FileAccess.open("user://mobile-water-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("MOBILE_WATER_RENDER checks=",checks," failures=",failures)
	get_tree().quit(int(failures > 0))
