extends "res://tools/tests/path_trace_variance.gd"
## Known stochastic lighting plus independent edge/history/bypass oracles.
var temporal_diffuse: Image
var temporal_specular: Image
var history_untouched := true

func presented(bytes: PackedByteArray) -> void:
	var rd:=device._rd
	device._copy_history()
	var before:=rd.texture_get_data(device._history[4],0)
	var ok: bool=device.filter_presented(bytes)
	filtered_result=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(device._history[0],0))
	filtered_specular=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(device._history[2],0))
	history_untouched=history_untouched and ok and before==rd.texture_get_data(device._history[4],0)
	filtered.emit.call_deferred()

func evaluate(probability: float,value: Color,label: String) -> void:
	var inputs:=input_images();var rng:=RandomNumberGenerator.new();rng.seed=81367
	var before_variance:=0.0;var after_variance:=0.0;var before_mean:=0.0;var after_mean:=0.0
	var before_spec:=0.0;var after_spec:=0.0
	for i in 24:
		for y in size.y:
			for x in size.x:
				var sample:=value if rng.randf()<probability else Color(0,0,0,1)
				inputs[0].set_pixel(x,y,sample);inputs[2].set_pixel(x,y,sample)
		await advance(inputs,i>0)
		temporal_diffuse=filtered_result;temporal_specular=filtered_specular
		RenderingServer.call_on_render_thread(presented.bind(frame(i>0)));await filtered
		if i>=16:
			var before:=measured(temporal_diffuse);var after:=measured(filtered_result)
			before_variance+=before.red_variance;after_variance+=after.red_variance
			before_mean+=before.mean[0];after_mean+=after.mean[0]
			before_spec+=measured(temporal_specular).red_variance;after_spec+=measured(filtered_specular).red_variance
	var expected:=value.r*probability
	report[label]={"temporal_variance":before_variance/8,"presented_variance":after_variance/8,
		"variance_ratio":after_variance/maxf(before_variance,1e-9),"mean":after_mean/8,
		"temporal_mean":before_mean/8,"expected":expected,"glossy_variance_ratio":after_spec/maxf(before_spec,1e-9)}
	check(after_variance<before_variance*0.7,label+": additional spatial pass reduces diffuse variance by at least 30 percent")
	check(after_spec<before_spec*0.7,label+": additional spatial pass reduces rough glossy variance by at least 30 percent")
	check(absf(after_mean/8/expected-1)<0.025,label+": radiance mean stays within 2.5 percent of the analytical reference")
	check(history_untouched,label+": wide spatial filtering never enters temporal history")

func boundaries() -> void:
	var inputs:=input_images()
	inputs[0].fill(Color(0,0,0,1));inputs[2].fill(Color(0,0,0,1))
	for y in size.y:
		for x in range(size.x/2,size.x):
			inputs[0].set_pixel(x,y,Color(4,2,1,1));inputs[2].set_pixel(x,y,Color(4,2,1,1))
			inputs[1].set_pixel(x,y,Color(0,0,1,8))
	await advance(inputs,false)
	RenderingServer.call_on_render_thread(presented.bind(frame(false)));await filtered
	check(filtered_result.get_pixel(size.x/2-1,size.y/2).r==0 and filtered_specular.get_pixel(size.x/2-1,size.y/2).r==0,
		"bright background never crosses the foreground depth edge")
	check(filtered_result.get_pixel(size.x/2,size.y/2).r>3.99,"matching background retains its radiance at the edge")
	# Still-scene mode bypasses this pass byte for byte.
	await advance(inputs,false);var before:=filtered_result.get_data()
	var bytes:=frame(false);bytes.encode_float(145*4,256)
	RenderingServer.call_on_render_thread(presented.bind(bytes));await filtered
	check(filtered_result.get_data()==before,"progressive convergence bypasses the spatial pass exactly")
	# A narrow glossy lobe keeps the existing angular reconstruction only.
	inputs=input_images();inputs[3].fill(Color(0.6,0.6,0.6,6));inputs[7].fill(Color(0.6,0.6,0.6,6))
	for y in size.y:
		for x in size.x:inputs[2].set_pixel(x,y,Color(float((x+y)%3),0,0,1))
	await advance(inputs,false);before=filtered_specular.get_data()
	RenderingServer.call_on_render_thread(presented.bind(frame(false)));await filtered
	check(filtered_specular.get_data()==before,"narrow glossy reflections bypass spatial spreading exactly")
	size=Vector2i(98,55);await advance(input_images(),false)
	RenderingServer.call_on_render_thread(presented.bind(frame(false)));await filtered
	check(filtered_result.get_size()==size,"resize and partial workgroups rebuild valid spatial targets")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	camera=Camera3D.new();add_child(camera);camera.current=true
	sun_energy=0;sky_energy=0;bounces=1;size=Vector2i(160,90)
	await native_materials()
	await evaluate(0.9,Color(1,1,1,1),"rare_dark")
	await evaluate(0.1,Color(10,2,0.5,1),"rare_bright")
	await boundaries()
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device._spatial_sets.is_empty() and device._spatial_images.is_empty(),"teardown releases every spatial target and descriptor")
	FileAccess.open(out.path_join("path-spatial.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	camera.queue_free();finish()
