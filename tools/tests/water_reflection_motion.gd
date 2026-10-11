extends Node
var out := "user://water-reflections"
var rows := []
var failures := []
func frames(n:=4) -> void:
	for i in n: await get_tree().process_frame
func check(ok:bool, label:String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":0,"vsync":0,"confine_mouse":0,
		"gfx_water":1,"gfx_water_reflections":2,"autosave":0,"show_tutorial":0,"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="1280x720";GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720))
	Engine.max_fps=60;RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var s:=Session.new();add_child(s);s.set_physics_process(false)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	var zone:=s.campaign.zone_by_map("zone3obr")
	s._enter_zone(zone.id,1,false);s.state.world_time=19.5
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.rig.set_process(false);g.direct.set_process(false);g.hud.process_mode=Node.PROCESS_MODE_DISABLED;g.hud.hide()
	var camera:=Camera3D.new();g.add_child(camera);camera.fov=65;camera.near=0.08;camera.current=true
	for u:GameUnit in s.world.units.values():u.visible=false;u.set_process(false)
	await frames(50)
	g.set_process(false);s.world.terrain.set_process(false)
	var t:=s.world.terrain
	var reflector:=t._reflection
	check(is_instance_valid(reflector),"Mirror creates a scene reflection owner")
	if not is_instance_valid(reflector):get_tree().quit(1);return
	reflector.set_process(false)
	var poses:=[]
	for id in [4442,4621,3615]:
		var obj:Node3D=s.world.objects[id]
		var root:=obj.global_position
		var target:=root+Vector3.UP*1.8
		var candidates:=[]
		for i in 32:
			var angle:=i*TAU/32
			var p:=Vector2(root.x,-root.z)+Vector2(cos(angle),sin(angle))*14.0
			var level:=t.water_at(p.x,p.y)
			if is_finite(level) and t.height_at(p.x,p.y)<level-0.3:
				candidates.append(Vector3(p.x,level,-p.y))
		if candidates.is_empty():continue
		for idx in [0,candidates.size()/2,candidates.size()-1]:
			var base:Vector3=candidates[idx]
			for altitude in [1.1,3.5,7.0]:
				poses.append({"kind":"fir-trees","object":id,"position":base+Vector3.UP*altitude,"target":target,"height":altitude})
	var material:=t._water_mat
	for i in []:
		var pose:Dictionary=poses[i]
		camera.global_position=pose.position;camera.look_at(pose.target);camera.make_current()
		for mode in ["previous","planar"]:
			if mode=="previous":reflector._disable()
			else:reflector._process(0.2)
			await frames(4);await RenderingServer.frame_post_draw
			var path:=out.path_join("%02d-%s.png"%[i,mode])
			get_viewport().get_texture().get_image().save_png(path)
			rows.append({"pose":i,"mode":mode,"kind":pose.kind,"object":pose.object,"position":str(pose.position),"target":str(pose.target),"height":pose.height,"plane":reflector.plane,"active":material.get_shader_parameter("planar_enabled"),"path":path})
		if i==0:
			check(material.get_shader_parameter("planar_enabled")==true,"visible tree-bank water enables the geometry reflection")
			check(reflector.viewport.size==Vector2i(640,360),"reflection viewport stays at half resolution")
	var pose:Dictionary=poses[10]
	var target:Vector3=pose.target
	var base:Vector3=pose.position
	var safe:=true
	for i in 61:
		var a:=-0.65+i*1.3/60.0
		camera.global_position=base
		var direction:Vector3=(target-base).rotated(Vector3.UP,a)
		camera.look_at(base+direction+Vector3.UP*(cos(a*4.0)*3.0-2.0))
		safe=safe and camera.global_position.y>t.height_at(base.x,-base.z)+0.3
		reflector._process(1.0/60.0)
		await frames(1);await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("motion-%03d.png"%i))
		rows.append({"motion_frame":i,"plane":reflector.plane,"active":material.get_shader_parameter("planar_enabled"),"camera_clear":safe})
	check(safe,"entire camera sweep stays above the riverbank terrain")
	GameData.options.gfx_water_reflections=0;t.apply_gfx();await frames(3)
	check(not is_instance_valid(t._reflection),"Off releases the extra reflection view")
	GameData.options.gfx_water_reflections=2;t.apply_gfx();await frames(3)
	check(is_instance_valid(t._reflection),"Mirror can be re-enabled without reloading the map")
	var active:=t._reflection
	t.hide();active._process(.2)
	check(active.viewport==null or active.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"hidden world stops the reflection pass")
	t.show()
	FileAccess.open(out.path_join("reflection.json"),FileAccess.WRITE).store_string(JSON.stringify({"zone":zone.id,"map":zone.mpr,"rows":rows,"failures":failures},"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(1 if not failures.is_empty() else 0)
