extends "res://tools/tests/path_trace_emitters.gd"
## Compare actual native raw paths against independent lighting integrals.
## CPU averaging bypasses reconstruction, so blur cannot improve these scores.
const Quality = preload("res://tools/tests/path_trace_quality.gd")
var sun_radius:=0.0
var irrelevant_light:=false

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var bytes:=super.frame(history,gi,shadows)
	bytes.encode_float(71*4,sun_radius)
	if irrelevant_light:
		# A zero-energy lamp consumes samples in the old stateful RNG, but must
		# not change any BSDF decision or another light's new purpose sequence.
		bytes.encode_float(89*4,2.0);bytes.encode_float(91*4,10.0);bytes.encode_float(119*4,0.5)
	return bytes

func build_surface(metal: bool,roof:=false) -> bool:
	if device!=null:RenderingServer.call_on_render_thread(device.dispose);await frames(4)
	mesh_data=PackedFloat32Array()
	quad(mesh_data,[Vector3(-200,0,-200),Vector3(200,0,-200),Vector3(200,0,200),Vector3(-200,0,200)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true,"surface":Vector3(0.35,1,0.5) if metal else Vector3(1,0,0)}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7}]
	if roof:
		quad(mesh_data,[Vector3(-20,1,-20),Vector3(0,1,-20),Vector3(0,1,20),Vector3(-20,1,20)],Vector3.DOWN,Vector3.ZERO)
		geometries.append({"offset":6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":1,"transform":Transform3D.IDENTITY,"mask":2})
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var images: Array[Image]=[white]
	device=PathDevice.new()
	RenderingServer.call_on_render_thread(device.build.bind(mesh_data.to_byte_array(),images,geometries,placements))
	return await device.prepared

func constant_reference(value: float) -> PackedFloat64Array:
	var result:=PackedFloat64Array();result.resize(size.x*size.y);result.fill(value);return result

func shadow_reference() -> PackedFloat64Array:
	# Vertical disk sun, half-plane blocker at y=1. Integrate the visible disk
	# cross-section analytically in v and with midpoint quadrature in u. The
	# zero-F0 dielectric Fresnel remainder is <1e-8 for this angular radius.
	var result:=constant_reference(0)
	for x in size.x:
		var screen:=Vector2(x+0.5,size.y*0.5)/Vector2(size)*get_viewport().get_visible_rect().size
		var position:=camera.project_position(screen,6.0)
		var lower:=clampf(-position.x/sun_radius,-1,1)
		var value:=0.0
		for i in 2048:
			var u:=lower+(1.0-lower)*(i+0.5)/2048.0
			var v:=sun_radius*sqrt(maxf(1.0-u*u,0))/sqrt(1.0+sun_radius*sun_radius*u*u)
			value+=2.0/sun_radius*log(v+sqrt(1+v*v))
		value*=(1.0-lower)/(2048.0*PI)
		for y in size.y:result[y*size.x+x]=value
	return result

func error_metrics(values: PackedFloat64Array,expected: PackedFloat64Array,count: int) -> Dictionary:
	var sum:=0.0;var expected_sum:=0.0;var error_sum:=0.0;var error2:=0.0
	var errors:=PackedFloat64Array();errors.resize(values.size())
	var valid:=true
	for i in values.size():
		var value:=values[i]/count;var error:=value-expected[i]
		valid=valid and is_finite(value);sum+=value;expected_sum+=expected[i]
		error_sum+=error;error2+=error*error;errors[i]=error
	var bias:=error_sum/values.size();var variance:=maxf(error2/values.size()-bias*bias,0)
	var horizontal:=0.0;var vertical:=0.0
	for y in range(size.y-1):
		for x in range(size.x-1):
			var i:=y*size.x+x
			horizontal+=(errors[i]-bias)*(errors[i+1]-bias)
			vertical+=(errors[i]-bias)*(errors[i+size.x]-bias)
	var denominator:=maxf(variance*(size.x-1)*(size.y-1),1e-20)
	return {"frames":count,"samples_per_pixel":spp,"finite":valid,"mean":sum/values.size(),
		"reference_mean":expected_sum/values.size(),"relative_bias":sum/maxf(expected_sum,1e-20)-1.0,
		"mse":error2/values.size(),"variance":variance,
		"horizontal_correlation":horizontal/denominator,"vertical_correlation":vertical/denominator}

func sequence_test(label: String,expected: PackedFloat64Array,channel: int,start:=0,total:=64) -> void:
	tick=start
	var sums:=constant_reference(0);var values:=[]
	for i in total:
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(false)))
		await frames(1);RenderingServer.call_on_render_thread(read_raw.bind(channel));await captured
		for y in size.y:
			for x in size.x:sums[y*size.x+x]+=raw.get_pixel(x,y).r
		if i+1 not in [1,4,16,64]:continue
		var row:=error_metrics(sums,expected,i+1);values.append(row)
		check(row.finite and absf(row.relative_bias)<0.025,label+": finite raw lighting agrees with the reference at "+str(i+1)+" frames")
		if i+1==16:
			var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBF)
			for y in size.y:
				for x in size.x:
					var value:=sums[y*size.x+x]/16.0;image.set_pixel(x,y,Color(value,value,value))
			image.save_png(out.path_join(label+"-16.png"))
	report[label]=values
	check(values[-1].mse<values[0].mse*0.2,label+": accumulating raw paths reduces error")
	if not baseline:check(absf(values[-1].horizontal_correlation)<0.07 and absf(values[-1].vertical_correlation)<0.07,label+": no strong adjacent-pixel error correlation")

func repeatability() -> void:
	spp=4;tick=999999
	await capture("counter-limit",{},false,2);var saved:=raw.get_data()
	tick=999999;await capture("counter-repeat",{},false,2)
	check(saved==raw.get_data(),"identical pixel/frame/sample indices reproduce the same native paths")
	tick=0;await capture("counter-wrap",{},false,2)
	check(saved!=raw.get_data(),"frame-counter wrap advances to a different valid sample set")
	tick=13;await capture("purpose-base",{},false,2);var before:=raw
	irrelevant_light=true;tick=13;await capture("purpose-unused-light",{},false,2)
	var maximum:=0.0;var difference:=0.0;var changed:=0
	for y in size.y:
		for x in size.x:
			var delta:=absf(before.get_pixel(x,y).r-raw.get_pixel(x,y).r)
			maximum=maxf(maximum,delta);difference+=delta
			if delta>0:changed+=1
	report["purpose-difference"]={"maximum":maximum,"mean":difference/(size.x*size.y),"changed_pixels":changed}
	# Adding another visibility trace can change compiler arithmetic enough to
	# cross a half-float boundary. Permit rounding, not a different path pattern.
	if not baseline:check(maximum<=0.001 and difference/(size.x*size.y)<0.000001,"an unrelated zero-energy light preserves BSDF samples within half-float rounding")
	irrelevant_light=false

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg=="--sampling-baseline":baseline=true
	DirAccess.make_dir_recursive_absolute(out)
	if not baseline:check(FileAccess.file_exists("res://src/game/fx/shaders/PATH_SAMPLING_NOTICES.txt"),"sampling attribution and license are included in the exported package")
	check(PathDevice.supported(),"qualified native path sampling device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	size=Vector2i(256,144);bounces=1;sun_energy=0;sky_energy=1
	camera.size=8;camera.position=Vector3(0,8,64);camera.look_at(Vector3.ZERO)
	check(await build_surface(true),"build grazing metal sampling fixture")
	var quadrature:=Quality.new()
	var integral: Vector3=quadrature.reference(roundf(0.35*255)/255,Vector3.ONE,camera.global_basis.z.y);quadrature.free()
	for samples in [1,2,4]:
		spp=samples;await sequence_test("metal-%d-spp"%spp,constant_reference(integral.x),2)
	spp=1;await sequence_test("metal-offset",constant_reference(integral.x),2,137,16)
	await repeatability()
	sun_energy=1;sky_energy=0;sun_direction=Vector3.UP;sun_radius=0.25
	camera.size=0.6;camera.position=Vector3(0,6,0);camera.rotation=Vector3(-PI/2,0,0)
	check(await build_surface(false,true),"build analytical disk-sun penumbra")
	var shadow:=shadow_reference()
	for samples in [1,2,4]:
		spp=samples;await sequence_test("shadow-%d-spp"%spp,shadow,0)
	sun_energy=0;sun_radius=0;camera.size=0.0001
	check(await fixture(),"build small area-emitter sampling fixture")
	var emission:=constant_reference(reference()*light_emission.x)
	for samples in [1,2,4]:
		spp=samples;await sequence_test("emitter-%d-spp"%spp,emission,0)
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	FileAccess.open(out.path_join("path-sampling.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"baseline":baseline,"metrics":report},"\t"))
	camera.queue_free();finish()
