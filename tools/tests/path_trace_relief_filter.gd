extends "res://tools/tests/path_trace_spatial.gd"
## Flat geometry with high-frequency material detail: normals must not invent
## depth boundaries, and painted albedo must not reject demodulated history.
func input_images() -> Array[Image]:
	var inputs:=super.input_images()
	for y in size.y:
		for x in size.x:
			var n:=Vector3(sin(float(x)*1.7)*0.45,cos(float(y)*1.3)*0.45,1.0).normalized()
			inputs[1].set_pixel(x,y,Color(n.x,n.y,n.z,6))
			inputs[5].set_pixel(x,y,Color(n.x,n.y,n.z,6))
			var albedo:=0.1 if (x+y)%2==0 else 0.9
			inputs[3].set_pixel(x,y,Color(albedo,albedo,albedo,63))
			inputs[7].set_pixel(x,y,Color(1-albedo,1-albedo,1-albedo,63))
	return inputs

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	camera=Camera3D.new();add_child(camera);camera.current=true
	sun_energy=0;sky_energy=0;bounces=1;size=Vector2i(160,90)
	await native_materials()
	var inputs:=input_images();var rng:=RandomNumberGenerator.new();rng.seed=54321
	var variance:=0.0;var average:=0.0;var age:=0.0
	for i in 32:
		for y in size.y:
			for x in size.x:
				inputs[0].set_pixel(x,y,Color(4,4,4,1) if rng.randf()<0.25 else Color(0,0,0,1))
		await advance(inputs,i>0)
		if i>=24:
			age+=filtered_result.get_pixel(size.x/2,size.y/2).a
			RenderingServer.call_on_render_thread(presented.bind(frame(i>0)));await filtered
			var m:=measured(filtered_result);variance+=m.red_variance;average+=m.mean[0]
	report["relief"]={"variance":variance/8,"mean":average/8,"age":age/8}
	check(age/8>7.5,"diffuse history survives painted material detail")
	check(variance/8<0.05,"textured relief diffuse variance stays below 0.05")
	check(absf(average/8-1.0)<0.035,"textured relief retains the known unit illumination")
	check(history_untouched,"relief spatial pass never enters temporal history")
	FileAccess.open(out.path_join("path-relief-filter.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":report},"\t"))
	RenderingServer.call_on_render_thread(device.dispose);await frames(8);camera.queue_free();finish()
