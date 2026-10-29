extends "res://tools/tests/path_trace_quality.gd"
## Exercise the real controller's light classification and consume its frame
## in the GPU reconstruction. Known histories expose stale-light leakage.
const Controller = preload("res://src/game/fx/scene_raytrace.gd")
var controller: Node
var game_stub: Game
var lamp: OmniLight3D

func next_frame(scene_changed:=false,dt:=1.0/60.0) -> PackedByteArray:
	return controller._frame(camera,size,1,scene_changed,dt)

func prime(progressive:=false) -> void:
	GameData.options.pt_accumulation=int(progressive)
	controller._strict_light_history=false;controller._path_signature=PackedByteArray();controller._history_key=""
	controller._accumulation_frames=0
	controller._lights.assign([weakref(lamp)])
	lamp.position=Vector3(0,1,2);lamp.light_color=Color(1,0.7,0.42)
	lamp.light_energy=1.0;lamp.omni_range=6;lamp.light_size=0.1;lamp.show()
	camera.position=Vector3(0,0,6);camera.rotation=Vector3.ZERO;camera.size=8
	Gfx.sun=Color.BLACK;Gfx.ambient=Color.BLACK;Gfx.fog_sky=Color.BLACK
	game_stub._sky_cave=true
	next_frame();next_frame()

func classify() -> void:
	prime();var data:=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==8,"unchanged responsive lighting retains eight-frame history")
	lamp.light_energy=1.03;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"gentle intensity rise uses three-frame history")
	lamp.light_energy=0.99;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"gentle intensity fall keeps bounded history")
	for i in 10:data=next_frame()
	check(data.decode_float(145*4)==8 and controller._accumulation_frames==8,"stable lighting recovers the normal history budget")
	for rate in [120,30,20]:
		prime();lamp.light_energy=1.03;data=next_frame(false,1.0/rate)
		var expected:=3.0 if rate==120 else (1.8 if rate==30 else 27.0/19.0)
		check(data.decode_float(82*4)==1 and absf(data.decode_float(145*4)-expected)<0.0001,"history time remains bounded at "+str(rate)+" Hz")
	for row: Array in [["light_energy",1.25],["light_energy",0.0],["light_color",Color(1,0.71,0.42)],
		["position",Vector3(0.7,1,2)],["omni_range",6.001],["light_size",0.101],["visible",false]]:
		prime();lamp.set(row[0],row[1]);data=next_frame()
		check(data.decode_float(82*4)==0,"immediate reset for "+str(row))
	# A carried torch moves a small fraction of its range per frame: its
	# receivers keep the short flutter history, a jump beyond that resets.
	prime();lamp.position=Vector3(0.001,1,2);data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"small source motion keeps the short local history")
	prime();lamp.position=Vector3(0.55,1,2);data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"motion up to a tenth of the range keeps the short local history")
	prime();lamp.position=Vector3(0.65,1,2);data=next_frame()
	check(data.decode_float(82*4)==0,"motion beyond a tenth of the range resets immediately")
	prime();lamp.position=Vector3(0.3,1,2);lamp.omni_range=6.001;data=next_frame()
	check(data.decode_float(82*4)==0,"a moving source with a changed range resets immediately")
	prime();lamp.light_energy=0.0;next_frame();lamp.light_energy=0.01;data=next_frame()
	check(data.decode_float(82*4)==0,"newly lit sources cannot reuse dark history")
	prime();Gfx.sun=Color(0.01,0.01,0.01);data=next_frame()
	check(data.decode_float(82*4)==0,"sun changes still invalidate history")
	prime();game_stub._sky_cave=false;Gfx.ambient=Color(0.01,0.01,0.01);data=next_frame()
	check(data.decode_float(82*4)==0,"environment changes still invalidate history")
	prime();lamp.light_energy=1.03;camera.size=8.01;data=next_frame()
	check(data.decode_float(82*4)==0,"projection changes reset even during gentle flutter")
	prime();lamp.light_energy=1.03;camera.position.x=0.01;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"small camera motion reprojects short flutter history")
	prime();lamp.light_energy=1.03;camera.position.x=3;data=next_frame()
	check(data.decode_float(82*4)==0,"camera cuts reset flutter history")
	prime(true);data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==256,"unchanged still-scene mode retains progressive accumulation")
	lamp.light_energy=1.0001;data=next_frame()
	check(data.decode_float(82*4)==0,"still-scene mode rejects even tiny light changes")
	prime(true);data=next_frame(true)
	check(data.decode_float(82*4)==0,"still-scene mode rejects changed geometry")
	prime();controller._strict_light_history=true;lamp.light_energy=1.03;data=next_frame()
	check(data.decode_float(82*4)==0,"diagnostic strict mode reproduces the previous reset")
	# Identical values on a different node still identify a different source.
	prime();var replacement:=lamp.duplicate() as OmniLight3D
	lamp.remove_from_group(Gfx.POINT_LIGHT_GROUP);add_child(replacement)
	controller._collect_lights(Vector3.ZERO);data=next_frame()
	check(data.decode_float(82*4)==0,"replacing a light node invalidates its history")
	replacement.remove_from_group(Gfx.POINT_LIGHT_GROUP);replacement.queue_free()
	lamp.add_to_group(Gfx.POINT_LIGHT_GROUP)
	prime();var extra: Array[OmniLight3D]=[]
	for i in 6:
		var light:=OmniLight3D.new();add_child(light);light.position=Vector3(i+1,1,2)
		light.light_energy=1.0;extra.append(light);controller._lights.append(weakref(light))
	next_frame();next_frame();extra[5].light_energy=1.03;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"the seventh local-light slot also retains short intensity history")
	extra[1].light_energy=0.98;extra[4].light_energy=1.02;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"several independent gentle intensity changes share the bounded history")
	extra[2].position.x+=0.001;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"one drifting source shares the multi-light flutter history")
	extra[2].position.x+=2.0;data=next_frame()
	check(data.decode_float(82*4)==0,"one jumping source invalidates a multi-light flutter frame")
	for light in extra:light.queue_free()
	daylight_history()

func prime_daylight(progressive:=false) -> void:
	prime(progressive)
	game_stub._sky_cave=false
	Gfx.sun=Color(1.0,0.95,0.7);Gfx.ambient=Color(0.5,0.6,0.7);Gfx.fog_sky=Color(0.3,0.5,0.8)
	Gfx._cloud_sun_direction=Vector3(0.1,0.6,0.8).normalized()
	next_frame();next_frame()

func daylight_history() -> void:
	prime_daylight()
	Gfx.sun.g+=0.00005;Gfx.sun.b+=0.00005
	Gfx.ambient.r+=0.00001;Gfx.fog_sky.b+=0.00001
	Gfx._cloud_sun_direction=Gfx._cloud_sun_direction.rotated(Vector3.UP,0.0001)
	var data:=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==8,"gradual daylight retains full responsive history")
	lamp.light_energy=1.03;Gfx.sun.b+=0.00005;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"daylight and torch flutter can reuse history together")
	for i in 10:data=next_frame()
	check(data.decode_float(145*4)==8 and controller._accumulation_frames==8,"unchanged daylight recovers full responsive history")
	for rate in [30,20]:
		prime_daylight();Gfx.sun.b+=0.00005;data=next_frame(false,1.0/rate)
		check(data.decode_float(82*4)==1 and data.decode_float(145*4)==8,"daylight drift preserves denoising at "+str(rate)+" Hz")
	prime_daylight();Gfx.sun.b+=0.01;data=next_frame()
	check(data.decode_float(82*4)==0,"larger sun colour changes reset immediately")
	prime_daylight();Gfx.ambient.r+=0.01;data=next_frame()
	check(data.decode_float(82*4)==0,"larger environment changes reset immediately")
	prime_daylight();Gfx._cloud_sun_direction=Gfx._cloud_sun_direction.rotated(Vector3.UP,0.01);data=next_frame()
	check(data.decode_float(82*4)==0,"a sun direction jump resets immediately")
	prime_daylight();Gfx.sun=Color.BLACK;data=next_frame()
	check(data.decode_float(82*4)==0,"extinguished sunlight cannot retain its previous radiance")
	prime_daylight();lamp.position.x+=0.001;Gfx.sun.b+=0.00005;data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"gradual daylight with a drifting local source keeps the short history")
	prime_daylight();lamp.position.x+=1.0;Gfx.sun.b+=0.00005;data=next_frame()
	check(data.decode_float(82*4)==0,"gradual daylight does not hide a jumping local source")
	prime_daylight();camera.size+=0.01;Gfx.sun.b+=0.00005;data=next_frame()
	check(data.decode_float(82*4)==0,"gradual daylight does not hide a projection change")
	prime_daylight(true);Gfx.sun.b+=0.00005;data=next_frame()
	check(data.decode_float(82*4)==0,"still-scene accumulation keeps exact daylight matching")
	prime_daylight();controller._strict_light_history=true;Gfx.sun.b+=0.00005;data=next_frame()
	check(data.decode_float(82*4)==0,"strict diagnostic mode rejects gradual daylight")
	var weather_sound:=GameSound.new();weather_sound.weather=Weather.new(null,null)
	game_stub.sound=weather_sound;weather_sound.weather._fade=20.0
	prime_daylight();Gfx.sun=(Gfx.sun.srgb_to_linear()*0.95).linear_to_srgb();data=next_frame()
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"precipitation fade retains short responsive history")
	prime_daylight();Gfx.sun=(Gfx.sun.srgb_to_linear()*0.5).linear_to_srgb();data=next_frame()
	check(data.decode_float(82*4)==0,"abrupt lighting jumps still reset during rain fade")
	prime_daylight(true);Gfx.sun=(Gfx.sun.srgb_to_linear()*0.999).linear_to_srgb();data=next_frame()
	check(data.decode_float(82*4)==0,"progressive accumulation never holds fading weather")
	game_stub.sound=null;weather_sound.free()

func inputs_for(dark:=false) -> Array[Image]:
	var inputs: Array[Image]=[]
	for i in 8:inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGBAH))
	for y in size.y:
		for x in size.x:
			var value:=0.6 if x%2==0 else 0.9
			inputs[0].set_pixel(x,y,Color(value,value,value,1) if not dark else Color(0,0,0,1))
			inputs[1].set_pixel(x,y,Color(0,0,1,6))
			inputs[2].set_pixel(x,y,Color(value*1.4,value*1.4,value*1.4,1) if not dark else Color(0,0,0,1))
			inputs[3].set_pixel(x,y,Color(0.6,0.6,0.6,1))
			inputs[4].set_pixel(x,y,Color(0.7,0.7,0.7,7))
			inputs[5].set_pixel(x,y,Color(0,0,1,6))
			inputs[6].set_pixel(x,y,Color(0.9,0.9,0.9,7))
			inputs[7].set_pixel(x,y,Color(0.6,0.6,0.6,1))
	return inputs

func gpu_history() -> void:
	prime();lamp.light_energy=1.03
	var limited:=next_frame();var current:=limited.duplicate();current.encode_float(82*4,0)
	var inputs:=inputs_for()
	RenderingServer.call_on_render_thread(reconstruct.bind(current,inputs));await filtered
	var d:=filtered_result.get_pixel(32,18).r;var s:=filtered_specular.get_pixel(32,18).r
	RenderingServer.call_on_render_thread(reconstruct.bind(limited,inputs));await filtered
	var new_d:=filtered_result.get_pixel(32,18);var new_s:=filtered_specular.get_pixel(32,18)
	check(absf(new_d.a-3)<0.01 and absf(new_s.a-3)<0.01,"GPU limits both diffuse and glossy history to three frames")
	check(absf(new_d.r-lerpf(d,0.7,2.0/3.0))<0.002,"GPU applies the short-history diffuse weight")
	check(absf(new_s.r-lerpf(s,0.9,2.0/3.0))<0.002,"GPU applies the short-history glossy weight")
	report["limited"]={"diffuse_age":new_d.a,"specular_age":new_s.a,"diffuse":new_d.r,"specular":new_s.r}
	prime();lamp.light_energy=1.03
	RenderingServer.call_on_render_thread(reconstruct.bind(next_frame(false,1.0/30.0),inputs));await filtered
	new_d=filtered_result.get_pixel(32,18);new_s=filtered_specular.get_pixel(32,18)
	check(absf(new_d.a-1.8)<0.002 and absf(new_s.a-1.8)<0.002,"GPU accepts fractional history ages at 30 Hz")
	check(absf(new_d.r-lerpf(d,0.7,4.0/9.0))<0.002 and absf(new_s.r-lerpf(s,0.9,4.0/9.0))<0.002,
		"slow frames give the current light a larger diffuse and glossy weight")
	report["30hz"]={"diffuse_age":new_d.a,"specular_age":new_s.a,"diffuse":new_d.r,"specular":new_s.r}
	lamp.light_energy=0.0;var extinguished:=next_frame()
	RenderingServer.call_on_render_thread(reconstruct.bind(extinguished,inputs_for(true)));await filtered
	new_d=filtered_result.get_pixel(32,18);new_s=filtered_specular.get_pixel(32,18)
	check(new_d.r==0 and new_s.r==0 and new_d.a==1 and new_s.a==1,"GPU discards all stale illumination on the extinguishing frame")
	report["extinguished"]={"diffuse_age":new_d.a,"specular_age":new_s.a,"diffuse":new_d.r,"specular":new_s.r}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	GameData.options.merge({"pt_mode":2,"pt_accumulation":0},true)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true
	game_stub=Game.new();controller=Controller.new(game_stub);add_child(controller);controller.set_process(false)
	controller._path_mode=true;controller._mode="light-history-test";controller._center=Vector3.ZERO
	lamp=OmniLight3D.new();lamp.add_to_group(Gfx.POINT_LIGHT_GROUP);add_child(lamp)
	size=Vector2i(64,36);classify()
	check(PathDevice.supported(),"qualified light-history GPU device")
	if PathDevice.supported():
		quad(mesh_data,[Vector3(-8,-8,0),Vector3(8,-8,0),Vector3(8,8,0),Vector3(-8,8,0)],Vector3.BACK,Vector3.ZERO)
		geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)}]
		placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
		check(await build_fixture(),"build GPU history fixture")
		if device._ready:await gpu_history()
		RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	FileAccess.open(out.path_join("path-light-history.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":report},"\t"))
	controller.queue_free();lamp.queue_free();camera.queue_free();await frames(4);game_stub.free();finish()
