extends "res://tools/tests/path_trace_glossy.gd"
## Reconstruct known stochastic signals through the real compute pipeline.
## Means are analytical; no production clamp or variance formula is the oracle.
var variance_baseline:=false

func measured(image: Image) -> Dictionary:
	var red:=0.0;var green:=0.0;var blue:=0.0;var squares:=0.0;var valid:=true
	var pixels:=image.get_width()*image.get_height()
	for y in image.get_height():
		for x in image.get_width():
			var c:=image.get_pixel(x,y)
			valid=valid and is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)
			red+=c.r;green+=c.g;blue+=c.b;squares+=c.r*c.r
	return {"mean":[red/pixels,green/pixels,blue/pixels],"red_variance":maxf(squares/pixels-pow(red/pixels,2),0),"finite":valid}

func input_images() -> Array[Image]:
	var inputs: Array[Image]=[]
	for i in 8:inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGBAH))
	inputs.append(Image.create(size.x,size.y,false,Image.FORMAT_RGH))
	inputs[1].fill(Color(0,0,1,6));inputs[5].fill(Color(0,0,1,6))
	inputs[3].fill(Color(0.6,0.6,0.6,63));inputs[7].fill(Color(0.6,0.6,0.6,63))
	return inputs

func noisy_shadow(inputs: Array[Image]) -> void:
	inputs[0].fill(Color(0,0,0,1));inputs[2].fill(Color(0,0,0,1))
	var values:=[]
	for i in 16:
		await advance(inputs,true)
		values.append([measured(filtered_result).mean[0],measured(filtered_specular).mean[0]])
	report["noisy_shadow_tail"]=values
	check(values[-1][0]<0.15 and values[-1][1]<0.15,"a noisy signal settles below fifteen percent after sixteen dark frames")
	if not variance_baseline:check(values[5][0]<0.06 and values[5][1]<0.06,"persistent darkness accelerates noisy history below six percent within six frames")

func advance(inputs: Array[Image],history: bool) -> void:
	var bytes:=frame(history)
	RenderingServer.call_on_render_thread(reconstruct.bind(bytes,inputs));await filtered
	inputs[4]=filtered_result;inputs[6]=filtered_specular
	if filtered_noise!=null:inputs[8]=filtered_noise

func stochastic_case(label: String,probability: float,hit: Color) -> Array[Image]:
	var inputs:=input_images()
	var rng:=RandomNumberGenerator.new();rng.seed=20261022
	var raw_mean:=0.0;var diffuse_mean:=0.0;var glossy_mean:=0.0;var frames_measured:=0
	var raw_variance:=0.0;var diffuse_variance:=0.0;var glossy_variance:=0.0
	for i in 40:
		for y in size.y:
			for x in size.x:
				var value:=hit if rng.randf()<probability else Color(0,0,0,1)
				inputs[0].set_pixel(x,y,value);inputs[2].set_pixel(x,y,value)
		await advance(inputs,i>0)
		if i<32:continue
		var raw:=measured(inputs[0]);var d:=measured(filtered_result);var s:=measured(filtered_specular)
		raw_mean+=raw.mean[0];diffuse_mean+=d.mean[0];glossy_mean+=s.mean[0]
		raw_variance+=raw.red_variance;diffuse_variance+=d.red_variance;glossy_variance+=s.red_variance;frames_measured+=1
	var expected:=hit.r*probability
	var d:=measured(filtered_result);var s:=measured(filtered_specular)
	var sigma_max:=0.0;var finite_noise:=true
	if filtered_noise!=null:
		for y in size.y:
			for x in size.x:
				var c:=filtered_noise.get_pixel(x,y)
				sigma_max=maxf(sigma_max,maxf(c.r,c.g));finite_noise=finite_noise and is_finite(c.r) and is_finite(c.g)
	var row:={"expected_red":expected,"raw_mean":raw_mean/frames_measured,
		"diffuse_mean":diffuse_mean/frames_measured,"glossy_mean":glossy_mean/frames_measured,
		"raw_variance":raw_variance/frames_measured,"diffuse_variance":diffuse_variance/frames_measured,
		"glossy_variance":glossy_variance/frames_measured,"maximum_sigma":sigma_max,
		"last_diffuse_rgb":d.mean,"last_glossy_rgb":s.mean,
		"diffuse_relative_bias":diffuse_mean/(frames_measured*expected)-1,
		"glossy_relative_bias":glossy_mean/(frames_measured*expected)-1}
	report[label]=row
	check(d.finite and s.finite and finite_noise,"finite lighting and noise history for "+label)
	check(absf(row.raw_mean/expected-1)<0.015,"stochastic fixture agrees with analytical mean for "+label)
	if not variance_baseline:
		check(absf(row.diffuse_relative_bias)<0.02 and absf(row.glossy_relative_bias)<0.02,"filtered diffuse and glossy means stay within two percent for "+label)
		if probability<1:
			check(row.diffuse_variance<row.raw_variance*0.15 and row.glossy_variance<row.raw_variance*0.2,"variance reduction retains useful accumulation for "+label)
		else:check(sigma_max==0.0,"constant HDR signal has exactly zero estimated noise")
		if label=="hdr_events":check(sigma_max>1000 and sigma_max<30000,"HDR standard deviation survives values whose square exceeds FP16")
	if not variance_baseline and hit.g>0 and hit.g!=hit.r:
		check(absf(s.mean[1]/s.mean[0]-hit.g/hit.r)<0.002 and absf(d.mean[2]/d.mean[0]-hit.b/hit.r)<0.002,"variance protection preserves colour ratios for "+label)
	if label=="rare_dark":
		inputs[0].save_png(out.path_join("rare-dark-raw.png"));filtered_specular.save_png(out.path_join("rare-dark-filtered.png"))
	return inputs

func transitions() -> void:
	var inputs:=input_images();inputs[0].fill(Color(1,1,1,1));inputs[2].fill(Color(1,1,1,1))
	for i in 8:await advance(inputs,i>0)
	inputs[0].fill(Color(0,0,0,1));inputs[2].fill(Color(0,0,0,1));await advance(inputs,true)
	check(measured(filtered_result).mean[0]<0.012 and measured(filtered_specular).mean[0]<0.012,"a coherent noise-free shadow change still clears in one frame")
	# A reset must ignore even a very large previous noise estimate.
	inputs[4].fill(Color(1000,1000,1000,8));inputs[6].fill(Color(1000,1000,1000,8));inputs[8].fill(Color(10000,10000,0,0))
	await advance(inputs,false)
	check(measured(filtered_result).mean[0]==0 and measured(filtered_specular).mean[0]==0,"history reset discards old illumination")
	if not variance_baseline:check(measured(filtered_noise).mean[0]==0 and measured(filtered_noise).mean[1]==0,"history reset discards old variance")
	# Geometry rejection remains independent of the colour envelope width.
	inputs[4].fill(Color(1000,1000,1000,8));inputs[6].fill(Color(1000,1000,1000,8));inputs[8].fill(Color(10000,10000,0,0))
	inputs[5].fill(Color(0,0,1,8));await advance(inputs,true)
	check(measured(filtered_result).mean[0]==0 and measured(filtered_specular).mean[0]==0,"large noise cannot admit a different depth layer")
	inputs[1].fill(Color(0,0,1,0));await advance(inputs,true)
	if not variance_baseline:check(measured(filtered_noise).mean[0]==0 and measured(filtered_noise).mean[1]==0,"missing primary surface clears the noise output")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
		if arg=="--variance-baseline":variance_baseline=true
	DirAccess.make_dir_recursive_absolute(out)
	check(PathDevice.supported(),"qualified variance reconstruction device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	sun_energy=0;sky_energy=0;bounces=1;size=Vector2i(160,90)
	await native_materials()
	await stochastic_case("rare_dark",0.9,Color(1,1,1,1))
	var noisy:=await stochastic_case("rare_bright_colour",0.1,Color(10,2,0.5,1))
	await noisy_shadow(noisy)
	await stochastic_case("hdr_events",0.1,Color(40000,8000,2000,1))
	await stochastic_case("constant_hdr",1.0,Color(32000,8000,4000,1))
	await transitions()
	if not variance_baseline:
		check(device._filter_auxiliary.size()==2,"path reconstruction owns two compact variance images")
		var previous_noise: RID=device._filter_auxiliary[0]
		size=Vector2i(96,54);await advance(input_images(),false)
		check(filtered_noise.get_size()==size and device._filter_auxiliary[0]!=previous_noise,"resize replaces variance images with the lighting targets")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	if not variance_baseline:check(device._filter_auxiliary.is_empty(),"teardown releases variance history")
	FileAccess.open(out.path_join("path-variance.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"baseline":variance_baseline,"metrics":report},"\t"))
	camera.queue_free();finish()
