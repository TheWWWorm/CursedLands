extends Node
## Real Ingos lake: compare the former short reflection frustum with the
## main view's range, at eye level and with downward pitch.
var checks := 0
var failures := []
var rows := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"gfx_water":1,"gfx_water_reflections":2,
		"q_aa":0,"q_shadows":0,"vsync":0,"confine_mouse":0,"autosave":0,"show_tutorial":0,"unit_fog":0,
		"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="1280x720";GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720))
	Engine.max_fps=60;RenderingServer.set_render_loop_enabled(true)
	var s:=Session.new();add_child(s);s.state.ensure_hero(0,"Human Hero")
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	await s.enter_zone("gz11k",1,false)
	s.state.world_time=19.5
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.rig.set_process(false);g.direct.set_process(false);g.hud.hide();g.hud.process_mode=Node.PROCESS_MODE_DISABLED
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,720)
	var camera:=Camera3D.new();g.add_child(camera);camera.near=.05;camera.far=100;camera.fov=75;camera.current=true
	await frames(20)
	g._update_daylight(false);g.set_process(false)
	var t:=s.world.terrain
	var reflector:=t._reflection
	check(is_instance_valid(reflector),"Forward+ Mirror creates a scene view")
	if not is_instance_valid(reflector):get_tree().quit(1);return
	reflector.set_process(false)
	var visible_difference := false
	for yaw: float in [0.0,0.2]:
		for pitch:float in [0.0,-0.4,-0.7]:
			var anchor:=Vector2(122.5,88.5)
			camera.global_position=Vector3(anchor.x,t.height_at(anchor.x,anchor.y)+1.6,-anchor.y)
			camera.look_at(camera.global_position+Vector3(cos(yaw)*cos(pitch),sin(pitch),-sin(yaw)*cos(pitch)))
			reflector.request_refresh();reflector._process(.2)
			check(is_equal_approx(reflector.camera.far,camera.far),"reflection range matches main view at pitch %.1f"%pitch)
			check(t._water_mat.get_shader_parameter("planar_enabled"),"lake reflection stays active at pitch %.1f"%pitch)
			var before:Image
			for previous:bool in [true,false]:
				reflector._process(.2)
				if previous:reflector.camera.far=64.0
				await frames(4);await RenderingServer.frame_post_draw
				var tag:="lake-yaw%.1f-pitch%.1f-%s"%[yaw,pitch,"short" if previous else "fixed"]
				get_viewport().get_texture().get_image().save_png("user://"+tag+".png")
				var image:=reflector.viewport.get_texture().get_image()
				image.save_png("user://"+tag+"-reflection.png")
				if previous:before=image
				else:
					var restored:=0
					for y in image.get_height():
						for x in image.get_width():
							if image.get_pixel(x,y).a>.5 and before.get_pixel(x,y).a<.05:restored+=1
					rows.append({"yaw":yaw,"pitch":pitch,"restored_pixels":restored,"plane":reflector.plane,"camera":str(camera.global_position)})
					if pitch==0.0 and restored>100:visible_difference=true
	check(visible_difference,"eye-level Ingos lake recovers distant bank geometry beyond the former 64m cutoff")
	camera.far=260;reflector._process(.2)
	check(is_equal_approx(reflector.camera.far,260),"extended draw distance also reaches the mirror")
	check(reflector.viewport.size==Vector2i(1280,720),"larger geometry range keeps the bounded reflection budget")
	print("WATER_REFLECTION_DISTANCE ",JSON.stringify({"checks":checks,"failures":failures,"rows":rows}))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
