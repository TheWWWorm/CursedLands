extends "res://tools/tests/water_raytrace_artifact.gd"
## Overhead (modern style) camera over fresh LiA gz3h ground with 4-bounce PT.
## Zooming out must keep the viewed ground in the path-traced lighting model
## instead of moving it beyond an eye-centred 60-72 m range, and a camera that
## keeps moving after a region promotion must not wait for the previous
## region's bounded retirement before preparing the next one. Fixed daylight
## and idle actors separate both from time-of-day and animation changes.
var output_size:=Vector2i(1280,720)

var game: Game
var session: Session
var rt: Node
var yaw:=0.74

## The modern rig's zoom curve: 9 degrees below the horizon at 3 m, 72 at 72 m.
func modern_pitch(d: float) -> float:
	return deg_to_rad(lerpf(9.0,72.0,clampf(log(d/3.0)/log(72.0/3.0),0.0,1.0)))

func ground(x: float,z: float) -> Vector3:
	return Vector3(x,t.height_at(x,-z),z)

func pose(focus: Vector3,d: float) -> void:
	var pitch:=modern_pitch(d)
	var forward:=Vector3(-sin(yaw),0,-cos(yaw))
	game.rig.hold_view(focus-forward*cos(pitch)*d+Vector3.UP*sin(pitch)*d,focus)

func right() -> Vector3:
	return Vector3(cos(yaw),0,-sin(yaw))

## Linear mean colour of the same 12 x 12 m of ground at every zoom: terrain
## points around the focus, projected through the current camera.
func ground_mean(image: Image,focus: Vector3) -> Vector3:
	var size:=image.get_size();var c:=Vector3.ZERO;var n:=0
	var scale:=Vector2(size)/get_viewport().get_visible_rect().size
	for z in range(-6,7):
		for x in range(-6,7):
			var p:=ground(focus.x+x,focus.z+z)
			if camera.is_position_behind(p):continue
			var pixel:=Vector2i((camera.unproject_position(p)*scale).floor())
			if pixel.x<0 or pixel.y<0 or pixel.x>=size.x or pixel.y>=size.y:continue
			var colour:=image.get_pixelv(pixel).srgb_to_linear();c+=Vector3(colour.r,colour.g,colour.b);n+=1
	return c/maxi(n,1)

func chroma(c: Vector3) -> Vector3:
	return c/maxf(c.x+c.y+c.z,.00001)

func colour_change(label: String,reference: Vector3,current: Vector3) -> Dictionary:
	var row:={"case":label,"reference":str(reference),"current":str(current),
		"chroma_shift":chroma(current).distance_to(chroma(reference)),
		"luminance_ratio":(current.x+current.y+current.z)/maxf(reference.x+reference.y+reference.z,.00001)}
	rows.append(row);print("PT_TACTICAL_ROW ",JSON.stringify(row))
	return row

## Complete region, published for 24 frames, with no retirement in progress.
func settle(drain := true) -> bool:
	var stable:=0
	for i in 1200:
		await frames(1)
		var quiet: bool=not drain or (rt._retired_devices.is_empty() and rt._retired_scenes.is_empty())
		if rt.stats.get("active",false) and not rt.stats.get("rebuilding",false) and quiet:stable+=1
		else:stable=0
		if stable>=24:return true
	return false

func capture_focus(name: String,focus: Vector3) -> Vector3:
	await frames(30)
	var image:=await capture(name)
	return ground_mean(image,focus)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"q_aa":0,"q_shadows":2,"q_aniso":4,"vsync":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"gfx_terrain":1,"gfx_materials":1,"gfx_sky":1,"gfx_terrain_cliffs":1,"gfx_depth_of_field":0,
		"autosave":0,"show_tutorial":0,"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"pt_mode":0,"rt_shadows":0,"rt_gi":0,"pt_accumulation":0,"pt_sharc":0,"pt_restir":0,"pt_refraction":0,
		"q_rt_lighting":1,"pt_ray_reconstruction":0,"rtx_upscaling":0,
		"rtx_frame_generation":0,"fsr_upscaling":0,"fsr_frame_generation":0,"render_scale":4},true)
	GameData.resolution_size="%dx%d"%[output_size.x,output_size.y];GameData.options.resolution=GameData.resolutions().find(output_size)
	GameData._apply_window();Engine.max_fps=30;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	session=Session.new();add_child(session)
	game=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0));session.state.world_time=12.0
	session._enter_zone("gz3h",1,false);session.set_physics_process(false)
	session.world.vm.instances.clear();game.direct.set_process(false)
	game.hud.hide();game.hud.process_mode=Node.PROCESS_MODE_DISABLED
	camera=game.rig.camera;camera.fov=55
	for unit: GameUnit in session.world.units.values():
		unit.orders.clear();unit.order={};unit._perceive_next=INF;unit.ai_next=INF;unit.action="idle"
	t=session.world.terrain
	var focus:=ground(95.16,-170.16)
	pose(focus,36.0)
	# The reported setting: path tracing with four bounces.
	GameData.options.pt_mode=2;game._apply_options()
	await frames(20)
	var sized: bool=await preload("res://tools/tests/capture_window.gd").resize(self,output_size)
	check(sized and get_window().size==output_size,"capture uses the requested output size: "+str(get_window().size))
	rt=game.get_node("SceneRaytrace")
	check(await settle(),"overhead view reaches a complete four-bounce PT region")
	if not rt.stats.get("active",false):await finish();return
	# Walking and other low views keep their eye-centred region exactly.
	var anchored:=rt.has_method("coverage_anchor")
	check(anchored,"controller exposes the region anchor used by its quality range")
	if anchored:
		var low:=Transform3D(Basis.IDENTITY,focus+Vector3(0,7,0)).looking_at(focus+Vector3(30,0,0))
		check(rt.call("coverage_anchor",low,t)==low.origin,"a 7 m camera keeps the eye as its region anchor")
		var high:=camera.get_camera_transform()
		var anchor: Vector3=rt.call("coverage_anchor",high,t)
		check(anchor.distance_to(high.origin)<=48.01 and anchor.distance_to(focus)<40.0,
			"an overhead camera anchors its region above the viewed ground (%.1f m from eye, %.1f m from focus)"%[anchor.distance_to(high.origin),anchor.distance_to(focus)])

	# Zoom: the same ground must keep its traced colour and brightness.
	var generation: int=rt._snapshot_generation
	var near:=await capture_focus("zoom-36m",focus)
	var shifts:={}
	for d: float in [56.0,72.0]:
		await get_tree().process_frame
		pose(focus,d)
		check(await settle(),"zoomed view %d m settles"%int(d))
		var row:=colour_change("zoom-%dm"%int(d),near,await capture_focus("zoom-%dm"%int(d),focus))
		shifts[d]=row
		check(row.chroma_shift<.02 and absf(row.luminance_ratio-1.0)<.1,
			"zooming out to %d m keeps the focus ground's PT colour (chroma %.4f, luminance x%.3f)"%[int(d),row.chroma_shift,row.luminance_ratio])
	check(rt._snapshot_generation==generation,"zooming the overhead camera keeps the same PT region (%d -> %d)"%[generation,rt._snapshot_generation])
	# The same zoom as continuous camera motion, 1.2 m per frame like a held
	# zoom key: no predicted region is aimed along the moving eye's path.
	pose(focus,36.0)
	check(await settle(),"overhead view settles before a continuous zoom")
	generation=rt._snapshot_generation
	for i in 31:
		await get_tree().process_frame
		pose(focus,lerpf(36.0,72.0,i/30.0))
		await RenderingServer.frame_post_draw
	var smooth:=colour_change("continuous-zoom-72m",near,await capture_focus("continuous-zoom-72m",focus))
	check(smooth.chroma_shift<.02 and absf(smooth.luminance_ratio-1.0)<.1 and rt._snapshot_generation==generation \
		and rt._gather==null and rt._pending_scene==null,
		"a continuous zoom out keeps the focus ground's PT colour and region (chroma %.4f, luminance x%.3f, region %d -> %d)"%[smooth.chroma_shift,smooth.luminance_ratio,generation,rt._snapshot_generation])

	# Keep moving after a promotion: the next region must not wait for the
	# previous region's bounded retirement (about a hundred frames).
	pose(focus,40.0)
	check(await settle(),"40 m overhead view settles before travel")
	var first:=focus+right()*40.0;first=ground(first.x,first.z)
	# Beyond the previous region's 72 m quality range.
	var second:=first+right()*90.0;second=ground(second.x,second.z)
	await get_tree().process_frame
	pose(first,40.0)
	generation=rt._snapshot_generation
	var promoted:=false
	for i in 600:
		await frames(1)
		if rt._snapshot_generation>generation:promoted=true;break
	check(promoted,"moving 40 m publishes a replacement region")
	var retiring: int=rt._retired_devices.size()
	check(retiring>=1,"the previous region is still retiring after promotion (%d)"%retiring)
	await get_tree().process_frame
	pose(second,40.0)
	generation=rt._snapshot_generation
	var began:=-1;var published:=-1;var retiring_at_begin:=0
	var during: Image
	for i in 100:
		await RenderingServer.frame_post_draw
		if began<0 and (rt._gather!=null or rt._pending_device!=null):began=i;retiring_at_begin=rt._retired_devices.size()
		if published<0 and rt._snapshot_generation>generation:published=i
		if i==99:during=get_viewport().get_texture().get_image()
		await get_tree().process_frame
	during.save_png(out.path_join("travel-frame-100.png"))
	rows.append({"case":"travel","began":began,"retiring_at_begin":retiring_at_begin,"published":published})
	print("PT_TACTICAL_ROW ",JSON.stringify(rows.back()))
	check(began>=0 and began<=5,"the next region begins while its predecessor retires (frame %d, %d retiring)"%[began,retiring_at_begin])
	check(published>=0,"the next region is published within 100 frames (frame %d)"%published)
	var moving:=ground_mean(during,second)
	check(await settle(),"travelled view settles")
	var settled:=await capture_focus("travel-settled",second)
	var travel:=colour_change("travel-100-frames",settled,moving)
	check(travel.chroma_shift<.02 and absf(travel.luminance_ratio-1.0)<.1,
		"100 frames after moving 90 m, the view already shows its settled PT colour (chroma %.4f, luminance x%.3f)"%[travel.chroma_shift,travel.luminance_ratio])
	await finish()

func finish() -> void:
	FileAccess.open(out.path_join("tactical-camera.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"rows":rows,"stats":rt.stats.duplicate(true) if rt!=null else {}},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("PT_TACTICAL_CAMERA ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
