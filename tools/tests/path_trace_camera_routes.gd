extends "res://tools/tests/scene_raytrace_live.gd"
## Real campaign routes at the reported low/50%, two-bounce setting.
## Records every frame's activation state, including topology and camera cuts.
var map_name := "zone11"
var resolution := Vector2i(3840,2160)
var samples := []
var live_clock := false
var soft := true
var receiver_counts := {}
var coverage_only := false

func ready_scene(rt: Node) -> bool:
	# A newly active snapshot can immediately request a recenter after a cut.
	# Require a settled current region rather than a single transient frame.
	var stable:=0
	for i in 1800:
		await frames(1)
		if rt._failed:return false
		if rt.stats.get("active",false) and not rt.stats.get("rebuilding",false) \
			and not rt.stats.has("replacement_failure") and camera.global_position.distance_to(rt._center)<=16.0:
			stable+=1
		else:stable=0
		if stable>=20:return true
	return false

func setup_route() -> Array:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
		if arg.begins_with("--pt-map="): map_name=arg.trim_prefix("--pt-map=")
		if arg=="--pt-hd": resolution=Vector2i(1920,1080)
		if arg=="--pt-live-clock": live_clock=true
		if arg=="--pt-no-soft": soft=false
		if arg=="--pt-coverage-only": coverage_only=true
	DirAccess.make_dir_recursive_absolute(out)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"vsync":0,"fps_limit":1,"q_aa":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"gfx_terrain":1,"gfx_terrain_cliffs":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_soft_ground":int(soft),"gfx_sky":1,"autosave":0,"show_tutorial":0,"unit_fog":0,
		"net_upnp":0,"net_lan":0,"net_directory":0,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,
		"fsr_upscaling":0,"fsr_frame_generation":0},true)
	GameData.resolution_size="%dx%d"%[resolution.x,resolution.y]
	Engine.max_fps=30;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_window().borderless=true;get_window().size=resolution
	var session:=Session.new();add_child(session)
	var game:=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0));session.state.world_time=12
	var zone:=session.campaign.zone_by_map(map_name)
	check(not zone.is_empty(),"authored route exists: "+map_name)
	if zone.is_empty():return []
	await session.enter_zone(String(zone.id),1,false)
	session.set_physics_process(false);session.world.set_physics_process(false);session.world.vm.instances.clear()
	game.rig.set_process(false);game.direct.set_process(false);game.hud.hide()
	for unit: GameUnit in session.world.units.values():unit.set_process(false)
	t=game.world.terrain
	camera=Camera3D.new();game.add_child(camera);camera.current=true;camera.fov=65;camera.near=0.08
	var point:=Vector2(138,174) if map_name=="zone11" else Vector2(game.rig.camera.global_position.x,-game.rig.camera.global_position.z)
	var focus:=Vector3(point.x,t.height_at(point.x,point.y),-point.y)
	camera.global_position=focus+Vector3(9,7,14);camera.look_at(focus)
	game.set_process(false);game._update_daylight(false)
	await frames(20)
	get_window().size=resolution
	Engine.max_fps=30
	game.hud.process_mode=Node.PROCESS_MODE_DISABLED;game.hud.hide()
	return [session,game]

func observe(rt: Node,label: String) -> void:
	samples.append({"label":label,"frame":Engine.get_frames_drawn(),"active":rt.stats.get("active",false),
		"global_active":Gfx.path_trace_active,"rebuilding":rt.stats.get("rebuilding",false),
		"generation":rt.stats.get("snapshot_generation",0),"history":rt.stats.get("history_limit",0),
		"reused":rt.stats.get("history_reused",false),"camera":str(camera.global_transform)})

func save_buffers(rt: Node,label: String) -> void:
	await RenderingServer.frame_post_draw
	await shot(label)
	if rt.device!=null and rt.device.output_ready():
		rt.device.output.get_image().save_exr(out.path_join(label+"-diffuse.exr"))
		rt.device.guide.get_image().save_exr(out.path_join(label+"-guide.exr"))

func receiver_coverage() -> void:
	var saved:=[];var shaders:={}
	for sector: Node in t.get_children():
		if not sector is EITerrainSector:continue
		for mesh: MeshInstance3D in sector._parts:
			var original:=mesh.get_active_material(0) as ShaderMaterial
			if original==null:continue
			var material:=original.duplicate() as ShaderMaterial
			var key:=original.shader.get_instance_id()
			if not shaders.has(key):
				var shader:=Shader.new()
				shader.code=Gfx._function_tail(original.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","""
    ALBEDO=vec3(0.0);EMISSION=vec3(0.0);
    vec3 audit_world=(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
    vec3 audit_light;vec4 audit_a,audit_b;
    vec3 audit_normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
    bool audit_match=ei_rt_sample(audit_world,audit_normal,audit_light,audit_a,audit_b);
    if(length(audit_world-ei_rt_center.xyz)<55.0)
        ALBEDO=audit_match?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0);
""")
				shaders[key]=shader
			material.shader=shaders[key]
			saved.append([mesh,mesh.get_surface_override_material(0)])
			mesh.set_surface_override_material(0,material)
	await frames(8)
	var mask:=await capture("terrain-receivers")
	var accepted:=0;var rejected:=0
	for y in range(0,mask.get_height(),2):
		for x in range(0,mask.get_width(),2):
			var c:=mask.get_pixel(x,y)
			if c.g>0.6 and c.g>c.r+0.2 and c.g>c.b+0.2:accepted+=1
			elif c.r>0.6 and c.r>c.g+0.2 and c.r>c.b+0.2:rejected+=1
	receiver_counts={"accepted":accepted,"rejected":rejected,"fraction":float(accepted)/maxi(accepted+rejected,1)}
	for row: Array in saved:row[0].set_surface_override_material(0,row[1])
	await frames(4)
	print("TERRAIN_RECEIVERS ",receiver_counts)

func run() -> void:
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var session: Session=context[0];var game: Game=context[1]
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"route prepares actual path tracing")
	print("ROUTE_INITIAL ",rt.stats)
	check(rt.stats.get("size",[])==[resolution.x/2,resolution.y/2],"trace lattice is half the actual 4K/HD viewport")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var original:=camera.global_transform
	# Daylight advances independently of simulation; this reproduces the
	# normal clock without allowing NPC encounters to change the route.
	for i in 56:
		if live_clock:session.state.world_time+=1.0/30.0/60.0;game._update_daylight(false)
		await frames(1);observe(rt,"held")
		if i>=48:await save_buffers(rt,"held-%02d"%i)
	await receiver_coverage()
	if coverage_only:
		FileAccess.open(out.path_join("terrain-coverage.json"),FileAccess.WRITE).store_string(JSON.stringify(receiver_counts,"\t"))
		game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
		get_tree().quit(0 if failures.is_empty() else 1);return
	for i in 100:
		camera.global_transform=original
		camera.global_position+=original.basis.x*(sin(float(i)*0.04)*5.0)
		camera.rotate_y(sin(float(i)*0.06)*0.13)
		if live_clock:session.state.world_time+=1.0/30.0/60.0;game._update_daylight(false)
		await frames(1);observe(rt,"strafe-pan")
		if i in [0,25,50,75,99]:await save_buffers(rt,"moving-%03d"%i)
	# A real actor mesh replacement follows camera-mode/equipment changes.
	var actor: GameUnit
	for unit: GameUnit in game.world.units.values():
		if unit.model!=null and unit.global_position.distance_to(rt._center)<60:actor=unit;break
	if actor!=null:
		var part:=actor.model.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var previous:=part.mesh;part.mesh=previous.duplicate();rt._poll=0
		var generation: int=rt._snapshot_generation
		for i in 600:
			await frames(1);observe(rt,"topology")
			if rt._snapshot_generation>generation:break
		check(rt._snapshot_generation>generation,"changed actor geometry is replaced")
		part.mesh=previous
	else:check(false,"route has a nearby actor for topology replacement")
	for i in 80:
		camera.global_transform=original;camera.global_position+=Vector3(float(i)*0.3,0,0)
		await frames(1);observe(rt,"travel")
	await ready_scene(rt)
	camera.global_transform=original;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24
	for i in 24:await frames(1);observe(rt,"camera-switch")
	await save_buffers(rt,"orthographic")
	var inactive:=samples.filter(func(row: Dictionary):return not row.active or not row.global_active).size()
	check(inactive==0,"PT stays active throughout all movement and topology frames: "+str(inactive))
	FileAccess.open(out.path_join("path-camera-routes.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"map":map_name,"soft_ground":soft,"live_clock":live_clock,
		"resolution":[resolution.x,resolution.y],"inactive_frames":inactive,"samples":samples,"stats":rt.stats,
		"terrain_receivers":receiver_counts},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_CAMERA_ROUTES ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
