extends "res://tools/tests/path_trace_performance.gd"
## Actual healing particles beside an original cave brazier in PT.
## Keep the geometry poll deliberately away from expiry: the effect must be
## discovered on its first rendered frame among seven existing local lights.
signal inspected
var inspection: Dictionary={}
var inspections: Array=[]
func read_gpu(rt: Node) -> void:
	var device: RefCounted=rt.device
	var data: PackedByteArray=device._rd.buffer_get_data(device._frame)
	var image:=Image.create_from_data(device._size.x,device._size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[0],0))
	var blue:=0.0;var count:=0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):blue+=image.get_pixel(x,y).b;count+=1
	var packed:=[]
	for i in int(data.decode_float(188*4)) if data.size()>752 else 7:
		var at: int=(448+i*4)*4 if data.size()>752 else (116+i*4)*4
		packed.append([data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8)])
	inspection={"renders":device.completed_renders,"raw_blue":blue/maxi(count,1),"packed_colours":packed,"history":data.decode_float(82*4)}
	inspected.emit.call_deferred()

func inspect(rt: Node,label: String) -> void:
	RenderingServer.call_on_render_thread(read_gpu.bind(rt));await inspected
	inspection.label=label;inspection.filtered_blue=blue_mean(rt);inspections.append(inspection.duplicate(true))
	print("SPELL_INSPECTION ",JSON.stringify(inspection))

func blue_mean(rt: Node) -> float:
	var image: Image=rt.device.output.get_image();var sum:=0.0;var count:=0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):sum+=image.get_pixel(x,y).b;count+=1
	return sum/maxi(count,1)

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	session._enter_zone("gz14k",1,false);t=session.world.terrain
	session.set_physics_process(false);session.world.set_process(false);session.world.set_physics_process(false)
	session.world.vm.instances.clear();game.set_process(false);game.set_process_input(false);game.set_process_unhandled_input(false)
	game._update_daylight(false);game.rig.set_process(false);game.direct.set_process(false)
	get_window().borderless=true;get_window().size=Vector2i(1280,720);Engine.max_fps=30
	for child in game.get_children():
		if child is FxRainSnow:child.process_mode=Node.PROCESS_MODE_DISABLED;child.hide()
	for unit: GameUnit in session.world.units.values():unit.hide();unit.set_process(false);unit.set_physics_process(false)
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"gfx_firelight":1,"gfx_lava_light":0,"character_light":0,
		"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0},true)
	var local: LocalLighting=game.get_node("LocalLighting");local.set_process(false);local.apply_options();local._process(0)
	var fx:=session.world.get_node("ParticleFx") as ParticleFx;fx.set_process(false)
	var torches: Array=[]
	for d: Dictionary in fx.lights:
		if d.get("kind","")=="fire":torches.append(d)
	check(not torches.is_empty(),"original cave supplies the fire effect")
	if torches.is_empty():get_tree().quit(1);return
	var selected:=Vector3(179.9853,0,-43.2999)
	torches.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return Vector2(a.light.global_position.x-selected.x,a.light.global_position.z-selected.z).length_squared()<Vector2(b.light.global_position.x-selected.x,b.light.global_position.z-selected.z).length_squared())
	var torch: OmniLight3D=torches[0].light
	for light: Node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		if light!=torch:light.hide()
	var center:=torch.global_position
	camera.global_position=center+Vector3(3.5,2,4.5);camera.look_at(center-Vector3.UP*0.7);camera.fov=55;camera.current=true
	for i in 60:fx._process(1.0/60.0)
	for i in 6:
		var light:=OmniLight3D.new();light.add_to_group(Gfx.POINT_LIGHT_GROUP);game.add_child(light)
		light.global_position=center+Vector3(i*0.1,0.4,0);light.light_color=Color(1,0.1,0)
		light.light_energy=0.01;light.omni_range=8
	Gfx.sun=Color.BLACK;Gfx.ambient=Color.BLACK;game._sun.light_energy=0
	t.apply_gfx();Gfx.apply_env(game._env)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"cave and authored material shaders prepare PT")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	rt.set_process(false);rt._poll=0.95
	check(rt._lights.size()==7,"seven existing lights occupy the previous capacity")
	var healed:=session.world.spawn_unit({"prototype":"Human Hero","position":ParticleFx.ei(center+Vector3(0.8,-0.4,0.5))})
	healed.set_process(false);healed.set_physics_process(false)
	healed.global_position=center+Vector3(0.8,-0.4,0.5)
	await frames(2)
	# Put the actor in both references; only its actual healing sparks change.
	for i in 30:rt._process(1.0/30.0);await frames(1)
	var before:=blue_mean(rt);await shot("fire-before-spell");await inspect(rt,"before")
	fx.spell_cast({"spell":"healing","a":healed.uid,"tu":healed.uid,"x":healed.pos.x,"y":healed.pos.y})
	for i in 12:fx._tick()
	fx._draw(1.0)
	rt._process(1.0/60.0);await frames(2);await RenderingServer.frame_post_draw
	var discovered: bool=rt._lights.any(func(w: WeakRef)->bool:return is_instance_valid(w.get_ref()) and w.get_ref().is_in_group("ei_spell_glow"))
	check(discovered and rt._poll>0.8,"a short spell enters PT on the first frame before the geometry poll")
	var first:=blue_mean(rt);await inspect(rt,"first")
	check(first>before+0.0002,"the first healing particle frame adds traced blue illumination to the original scene")
	check(absf(inspection.filtered_blue-inspection.raw_blue)<maxf(0.003,inspection.raw_blue*0.15),"the first displayed spell frame follows current radiance without a slow colour ramp")
	await shot("fire-and-spell-first-frame")
	for i in 12:rt._process(1.0/60.0);await frames(1)
	await shot("fire-and-spell-settled");await inspect(rt,"settled")
	for i in 80:fx._tick()
	fx._draw(1.0);await frames(2)
	rt._process(1.0/60.0);await frames(2);await RenderingServer.frame_post_draw
	var extinguished:=blue_mean(rt);await inspect(rt,"expired")
	check(rt._lights.size()==7 and not rt.stats.history_reused,"spell expiry removes the light and its old history immediately")
	check(absf(extinguished-before)<maxf(0.003,before*0.10),"expired spell restores the original fire-lit scene")
	await shot("fire-after-spell")
	FileAccess.open(out.path_join("path-healing-glow.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"inspections":inspections,"blue_before":before,"blue_first_frame":first,"blue_after":extinguished,"torch":str(center),"stats":rt.stats,
		"note":"Original cave and flame with six dim probe lights and the production healing particle emitter. Geometry poll does not expire during the first spell frame."},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_HEALING_GLOW ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
