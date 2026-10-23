extends "res://tools/tests/path_trace_performance.gd"
## Original cave/torch, driven by LocalLighting at a fixed 60 Hz. A single
## source is isolated so its known intensity gives an independent transport
## reference. The ordinary campaign geometry and material shaders stay live.
var rt: Node
var local_lighting: LocalLighting
var torch: Dictionary
var reference: Image
var reference_guide: Image
var sample_pixels: Array[Vector2i]=[]
var audit_size:=Vector2i(960,540)
var base_energy:=0.0
var fixed_dt:=1.0/60.0

func response_gain(values: Array) -> float:
	var energy:=0.0;var brightness:=0.0
	for row: Dictionary in values:energy+=row.energy_scale;brightness+=row.diffuse_mean
	energy/=values.size();brightness/=values.size()
	var covariance:=0.0;var variance:=0.0
	for row: Dictionary in values:
		covariance+=(row.energy_scale-energy)*(row.diffuse_mean-brightness)
		variance+=pow(row.energy_scale-energy,2)
	return covariance*energy/maxf(variance*brightness,0.000001)

func dispatch() -> void:
	var changes: Dictionary=rt._scene.updates()
	var started:=Time.get_ticks_usec()
	var data: PackedByteArray=rt._frame(camera,audit_size,1,not changes.instances.is_empty() or not changes.poses.is_empty(),fixed_dt)
	cpu_samples.append((Time.get_ticks_usec()-started)/1000.0)
	RenderingServer.call_on_render_thread(rt.device.render.bind(audit_size,data,changes,GameData.option("q_aniso")))
	await RenderingServer.frame_post_draw

func torch_case(strict: bool) -> Dictionary:
	GameData.options.pt_accumulation=0;rt._strict_light_history=strict
	rt._path_signature=PackedByteArray();rt._history_key="";rt._accumulation_frames=0;rt._frame_number=300
	local_lighting._time=0.0;cpu_samples.clear()
	var sums:=PackedFloat64Array();var squares:=PackedFloat64Array()
	sums.resize(sample_pixels.size()*3);squares.resize(sample_pixels.size()*3)
	var mse:=0.0;var power:=0.0;var ages:=[];var response:=[];var retained:=0;var count:=0
	var started:=Time.get_unix_time_from_system()
	for frame_index in 112:
		local_lighting._process(fixed_dt)
		await dispatch()
		if frame_index<16:continue
		var scale: float=torch.light.light_energy/base_energy
		var image: Image=rt.device.output.get_image();var brightness:=0.0;var age:=0.0
		for i in sample_pixels.size():
			var p:=sample_pixels[i];var c:=image.get_pixelv(p);var target:=reference.get_pixelv(p)
			for k in 3:
				var value: float=c[k]/scale;var at:=i*3+k
				sums[at]+=value;squares[at]+=value*value
				mse+=(value-target[k])*(value-target[k]);power+=target[k]*target[k]
			brightness+=(c.r+c.g+c.b)/3.0;age+=c.a
		ages.append(age/maxi(sample_pixels.size(),1));retained+=int(rt.stats.history_reused)
		response.append({"frame":frame_index,"energy_scale":scale,"diffuse_mean":brightness/maxi(sample_pixels.size(),1)})
		count+=1
		if OS.get_cmdline_user_args().has("--pt-video") or frame_index in [16,32,48,64,80,96,111]:
			await shot(("strict" if strict else "bounded")+"-%03d"%frame_index)
	var variance:=0.0
	for i in sums.size():variance+=maxf(squares[i]/count-pow(sums[i]/count,2),0.0)
	variance/=maxi(sums.size(),1)
	return {"strict":strict,"frames":count,"samples":sample_pixels.size(),"normalized_temporal_variance":variance,
		"relative_rmse":sqrt(mse/maxf(power,0.000001)),"history_age":summary(ages),"retained_frames":retained,
		"controller_cpu_ms":summary(cpu_samples.duplicate()),"response":response,"brightness_gain":response_gain(response),
		"start_unix":started,"end_unix":Time.get_unix_time_from_system()}

func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pt-hz="):fixed_dt=1.0/maxf(float(arg.trim_prefix("--pt-hz=")),1.0)
	session._enter_zone("gz14k",1,false);t=session.world.terrain
	session.set_physics_process(false);session.world.set_process(false);session.world.set_physics_process(false)
	session.world.vm.instances.clear();game.set_process(false);game.set_process_input(false);game.set_process_unhandled_input(false)
	game._update_daylight(false);game.rig.set_process(false);game.direct.set_process(false)
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	for child in game.get_children():
		if child is FxRainSnow:child.process_mode=Node.PROCESS_MODE_DISABLED;child.hide()
	for unit: GameUnit in session.world.units.values():unit.hide();unit.set_process(false);unit.set_physics_process(false)
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"gfx_firelight":1,"gfx_lava_light":0,"character_light":0,
		"pt_mode":2,"pt_accumulation":0,"q_rt_lighting":1},true)
	local_lighting=game.get_node("LocalLighting");local_lighting.set_process(false);local_lighting.apply_options();local_lighting._process(0)
	var fx:=session.world.get_node("ParticleFx") as ParticleFx;fx.set_process(false)
	var torches:=[]
	for d: Dictionary in fx.lights:
		if d.get("kind","")=="fire":torches.append(d)
	check(not torches.is_empty(),"original cave contains a flame light")
	if torches.is_empty():get_tree().quit(1);return
	# The inventory identifies this freestanding stto11 brazier. A nearby
	# wall-mounted torch is largely hidden from the ordinary outside view.
	var selected:=Vector3(179.9853,0,-43.2999)
	torches.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return Vector2(a.light.global_position.x-selected.x,a.light.global_position.z-selected.z).length_squared()<Vector2(b.light.global_position.x-selected.x,b.light.global_position.z-selected.z).length_squared())
	torch=torches[0]
	for light: Node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):
		if light!=torch.light:light.hide()
	var center: Vector3=torch.light.global_position
	camera.global_position=center+Vector3(3.5,2,4.5);camera.look_at(center-Vector3.UP*0.7);camera.fov=55;camera.current=true
	# Populate the original flame before freezing particle motion, so the
	# matched views show its emitter as well as the light on nearby stone.
	for i in 60:fx._process(1.0/60.0)
	# This isolated-source calibration removes the legacy cave directional
	# fill. It does not change campaign lighting or any original source value.
	Gfx.sun=Color.BLACK;Gfx.ambient=Color.BLACK;game._sun.light_energy=0
	t.apply_gfx();Gfx.apply_env(game._env)
	rt=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"campaign cave prepares the path tracer")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	rt._collect_lights(camera.global_position)
	check(rt._lights.size()==1 and rt._lights[0].get_ref()==torch.light,"fixture isolates the original torch for transport measurements")
	rt.set_process(false);base_energy=float(torch.energy)*LocalLighting.FIRE_ENERGY
	torch.light.light_energy=base_energy
	GameData.options.pt_accumulation=1;rt._history_key="";rt._path_signature=PackedByteArray()
	for i in 192:await dispatch()
	reference=rt.device.output.get_image();reference_guide=rt.device.guide.get_image()
	for y in range(8,audit_size.y-8,8):
		for x in range(8,audit_size.x-8,8):
			var c:=reference.get_pixel(x,y);var g:=reference_guide.get_pixel(x,y)
			if g.a>0 and maxf(c.r,maxf(c.g,c.b))>0.002:sample_pixels.append(Vector2i(x,y))
	check(sample_pixels.size()>100,"torch illuminates enough visible original cave geometry")
	await shot("torch-reference");reference.save_exr(out.path_join("torch-reference-diffuse.exr"))
	if sample_pixels.is_empty():get_tree().quit(1);return
	var strict:=await torch_case(true);var bounded:=await torch_case(false)
	check(strict.retained_frames==0 and strict.history_age.median<1.01,"original gentle torch flutter reproduces continual strict resets")
	var expected_age:=minf(3.0,1.0/(1.0-pow(2.0/3.0,fixed_dt*60.0)))
	check(bounded.retained_frames>=94 and absf(bounded.history_age.median-expected_age)<0.03,"live torch retains the bounded GPU history")
	check(bounded.normalized_temporal_variance<strict.normalized_temporal_variance*0.8,"bounded history reduces torch illumination noise")
	check(bounded.relative_rmse<strict.relative_rmse,"bounded torch lighting is closer to the accumulated transport reference")
	check(bounded.brightness_gain>0.8 and bounded.brightness_gain<1.2,"the original flame's brightness variation remains visible")
	# Extinguish the actual source after retaining its illumination. The next
	# GPU frame must be dark, without waiting for the one-second light scan.
	torch.light.light_energy=0;await dispatch()
	var dark: Image=rt.device.output.get_image();var peak:=0.0
	for p in sample_pixels:
		var c:=dark.get_pixelv(p);peak=maxf(peak,maxf(c.r,maxf(c.g,c.b)))
	check(peak<0.00001 and not rt.stats.history_reused,"extinguishing the campaign torch clears its lighting immediately")
	await shot("torch-extinguished")
	FileAccess.open(out.path_join("path-torch-history.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,
		"failures":failures,"strict":strict,"bounded":bounded,"dark_peak":peak,"torch_position":str(center),
		"torch_radius":torch.light.omni_range,"base_energy":base_energy,"camera":str(camera.global_transform),
		"cave":game._sky_cave,"driver":RenderingServer.get_current_rendering_driver_name(),"device":RenderingServer.get_video_adapter_name(),
		"reference_frames":192,"fixed_dt":fixed_dt,"note":"Single original cave torch; other local lights and legacy directional fill disabled only in the fixture. No campaign lighting change. GPU readbacks make these sequences unsuitable for FPS comparisons."},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_TORCH_HISTORY ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
