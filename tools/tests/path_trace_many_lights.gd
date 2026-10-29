extends "res://tools/tests/path_trace_device.gd"
## Compare sampled local illumination to the sum of exact <=7-light GPU
## renders. The reference uses the same materials, visibility and source sizes.
const Controller = preload("res://src/game/fx/scene_raytrace.gd")
var lights: Array[Vector4]=[]
var colours: Array[Color]=[]
var selected: Array[int]=[]
var history_limit:=256.0
var controller: Node
var owner_game: Game

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows)
	data.encode_float(145*4,history_limit)
	for i in mini(selected.size(),7):
		var at:=selected[i]
		for c in 4:
			data.encode_float((88+i*4+c)*4,lights[at][c])
			data.encode_float((116+i*4+c)*4,colours[at][c])
	if data.size()>=2816:
		data.encode_float(188*4,selected.size());data.encode_float(191*4,1)
		for i in selected.size():
			var at:=selected[i]
			for c in 4:
				data.encode_float((192+i*4+c)*4,lights[at][c])
				data.encode_float((448+i*4+c)*4,colours[at][c])
	return data

func measure(count: int) -> void:
	var reference:=Color(0,0,0,0)
	for first in range(0,count,7):
		selected.assign(range(first,mini(first+7,count)))
		await render_many(8);reference+=mean(device.output)
	selected.assign(range(count));await render_many(48)
	var sampled:=mean(device.output)
	var error:=0.0
	for c in 3:error=maxf(error,absf(sampled[c]-reference[c])/maxf(reference[c],0.001))
	check(error<0.03,"%d lights preserve exact summed illumination within 3%%: %.4f"%[count,error])
	observations.append({"lights":count,"reference":str(reference),"sampled":str(sampled),"relative_error":error})
	device.output.get_image().save_exr(out.path_join("lights-%d.exr"%count))

func collection() -> void:
	owner_game=Game.new();owner_game._sky_cave=true
	controller=Controller.new(owner_game);add_child(controller);controller.set_process(false)
	controller._path_mode=true;controller._center=Vector3.ZERO;controller._mode="lights-audit"
	var nodes: Array[OmniLight3D]=[]
	for i in 70:
		var light:=OmniLight3D.new();light.add_to_group(Gfx.POINT_LIGHT_GROUP);add_child(light)
		light.position=Vector3((i%8)*0.1,2,(i/8)*0.1);light.omni_range=6;light.light_energy=0.1
		nodes.append(light)
	controller._collect_lights(camera.position)
	check(controller._lights.size()==64,"crowded regions retain 64 local lights")
	var flash:=nodes[69];flash.light_energy=4;flash.light_color=Color(0.1,0.2,1)
	controller._collect_lights(camera.position)
	check(controller._lights.any(func(w: WeakRef)->bool:return w.get_ref()==flash),"a new bright spell survives the over-budget selection")
	for i in range(16,70):nodes[i].hide()
	controller._collect_lights(camera.position)
	var order: Array=controller._lights.map(func(w: WeakRef)->int:return w.get_ref().get_instance_id())
	controller._collect_lights(camera.position+Vector3(0.1,0,0))
	check(order==controller._lights.map(func(w: WeakRef)->int:return w.get_ref().get_instance_id()),"camera movement preserves source order inside the budget")
	GameData.options.pt_accumulation=0
	controller._frame(camera,size,1);controller._frame(camera,size,1)
	nodes[15].light_energy*=1.03
	var data: PackedByteArray=controller._frame(camera,size,1)
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"gentle fire flutter beyond slot seven retains short history")
	nodes[15].light_color=Color.BLUE;data=controller._frame(camera,size,1)
	check(data.decode_float(82*4)==0,"spell colour changes beyond slot seven reject stale history")
	controller._frame(camera,size,1);nodes[15].position.x+=0.01;data=controller._frame(camera,size,1)
	check(data.decode_float(82*4)==1 and data.decode_float(145*4)==3,"drifting effects beyond slot seven keep the short local history")
	nodes[15].position.x+=1.0;data=controller._frame(camera,size,1)
	check(data.decode_float(82*4)==0,"jumping effects beyond slot seven reject stale history")
	controller._frame(camera,size,1);nodes[15].light_energy=0;controller._collect_lights(camera.position)
	data=controller._frame(camera,size,1)
	check(controller._lights.size()==15 and data.decode_float(82*4)==0,"extinguished effects leave no retained illumination")
	controller._path_mode=false;controller._collect_lights(camera.position)
	check(controller._lights.size()==7,"conventional scene RT retains its seven visibility channels")
	for light in nodes:light.queue_free()
	controller.queue_free();await frames(4);owner_game.free()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4;camera.position=Vector3(0,6,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=1
	await collection()
	check(PathDevice.supported(),"qualified many-light GPU")
	if PathDevice.supported():
		quad(mesh_data,[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)],Vector3.UP,Vector3.ZERO)
		geometries=[{"offset":0,"count":6,"standard":true,"opaque":true}]
		placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
		check(await build_fixture(),"build many-light transport scene")
		for i in 64:
			var angle:=i*TAU/64
			lights.append(Vector4(cos(angle)*1.5,2.0+i%3*0.2,sin(angle)*1.5,6))
			colours.append(Color(0.04+0.01*(i%3),0.03+0.02*(i%5),0.05+0.01*(i%7),0.04))
		for count in [7,8,16,64]:await measure(count)
		for i in 8:colours[i]=Color(0.01,0,0,0.04)
		colours[7]=Color(0,0,2,0.04);selected.assign(range(8));await render_many(8)
		var flash:=mean(device.output)
		check(flash.b>0.5 and flash.b>flash.r*10,"the eighth spell illuminates the receiver immediately")
		colours[7]=Color(0,0,0,0.04);await render_many(1)
		check(mean(device.output).b<0.00001,"extinguishing the eighth spell removes its blue lighting")
		history_limit=8
		for i in 7:colours[i]=Color(0.01,0.005,0.004,0.04)
		selected.assign(range(7));await render_many(24);var before:=mean(device.output)
		colours[7]=Color(0,0,2,0.04);selected.assign(range(8));await render_many(24);var during:=mean(device.output)
		selected.assign(range(7));await render_many(1);var after:=mean(device.output)
		check(device.nrd_active and during.b>before.b+0.5,"NRD reconstructs the added spell among persistent warm lights")
		check(absf(after.b-before.b)<0.005,"NRD reset removes an expired spell while other coloured lights remain")
		observations.append({"nrd_before":str(before),"nrd_during":str(during),"nrd_after":str(after)})
		history_limit=256
		check(await build_fixture(true),"build glossy light response scene")
		selected.assign([0]);lights[0]=Vector4(0,2,0,6);colours[0]=Color(1,1,1,0.04)
		await render_many(8);var glossy:=mean(device.shadow0)
		colours[0].a=-0.04;await render_many(8);var assist:=mean(device.shadow0)
		check(glossy.r>0.01 and assist.r<0.00001,"diffuse-only character assist does not create metallic highlights")
		observations.append({"glossy":str(glossy),"diffuse_only":str(assist)})
		RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	FileAccess.open(out.path_join("path-many-lights.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	camera.queue_free();await frames();finish()
