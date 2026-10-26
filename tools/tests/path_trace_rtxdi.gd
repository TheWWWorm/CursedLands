extends "res://tools/tests/path_trace_many_lights.gd"
## Compare actual RTXDI output with independently summed small-light renders,
## inspect real packed GPU reservoirs, and exercise history/visibility lifetime.
var raw_image: Image
var packed:=PackedByteArray()
var enable_sharc:=false
var control_data:=PackedByteArray()
var surface_data:=PackedByteArray()
signal inspected
func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows)
	data.encode_float(77*4,1)
	data.encode_float(190*4,float(enable_sharc))
	return data

func inspect(read_reservoirs:=false) -> void:
	raw_image=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBAH,device._rd.texture_get_data(device._raw[0],0))
	if read_reservoirs and device.rtxdi.active:
		packed=device._rd.buffer_get_data(device.rtxdi._reservoirs)
		control_data=device._rd.buffer_get_data(device.rtxdi._control)
		surface_data=device._rd.buffer_get_data(device.rtxdi._surfaces)
	inspected.emit.call_deferred()

func read_raw(reservoirs:=false) -> void:
	RenderingServer.call_on_render_thread(inspect.bind(reservoirs));await inspected

func raw_mean() -> Color:
	var total:=Color(0,0,0,0)
	for y in range(size.y/2-12,size.y/2+12):
		for x in range(size.x/2-12,size.x/2+12):total+=raw_image.get_pixel(x,y)
	return total/576.0

func luminance_error(reference: PackedFloat32Array) -> float:
	var error:=0.0
	for y in range(20,size.y-20):
		for x in range(20,size.x-20):
			var c:=raw_image.get_pixel(x,y)
			var delta:=c.r*.2126+c.g*.7152+c.b*.0722-reference[y*size.x+x]
			error+=delta*delta
	return error/float((size.x-40)*(size.y-40))

func step(changes: Dictionary={},history:=true) -> void:
	RenderingServer.call_on_render_thread(device.render.bind(size,frame(history),changes))
	await frames(2);await RenderingServer.frame_post_draw

func reservoir_summary() -> Dictionary:
	var row_pitch:=ceili(size.x/16.0)*256
	var pitch:=row_pitch*ceili(size.y/16.0)
	var array: int=1-int(device.rtxdi._index)
	var reused:=0;var maximum:=0;var valid:=0;var finite:=true
	for y in size.y:
		for x in size.x:
			var index:=array*pitch+(y/16)*row_pitch+(x/16)*256+(y%16)*16+x%16
			var at:=index*24
			var m:=packed.decode_u32(at+8)>>18;maximum=maxi(maximum,m)
			if m>16:reused+=1
			if (packed.decode_u32(at)&0x80000000)!=0:valid+=1
			finite=finite and is_finite(packed.decode_float(at+16)) and is_finite(packed.decode_float(at+20))
	return {"reused":reused,"maximum":maximum,"valid":valid,"finite":finite}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	check(PathDevice.supported(),"qualified RTXDI GPU")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4;camera.position=Vector3(0,.7,.001);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=1;history_limit=8
	quad(mesh_data,[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-5,1,-5),Vector3(5,1,-5),Vector3(5,1,5),Vector3(-5,1,5)],Vector3.UP,Vector3.ZERO)
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true},{"offset":6,"count":6,"standard":true,"opaque":true}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},{"geometry":1,"transform":Transform3D.IDENTITY,"mask":0}]
	check(await build_fixture(),"build direct-light reservoir fixture")
	if not device._ready:finish();return
	for i in 64:
		var angle:=i*TAU/64
		lights.append(Vector4(cos(angle)*1.5,2.0+i%3*.2,sin(angle)*1.5,6))
		colours.append(Color(.04+.01*(i%3),.03+.02*(i%5),.05+.01*(i%7),.04))
	var reference:=Color(0,0,0,0)
	var reference_pixels:=PackedFloat32Array();reference_pixels.resize(size.x*size.y)
	for first in range(0,64,7):
		selected.assign(range(first,mini(first+7,64)));await render_many(8);await read_raw();reference+=raw_mean()
		for y in size.y:
			for x in size.x:
				var c:=raw_image.get_pixel(x,y)
				reference_pixels[y*size.x+x]+=c.r*.2126+c.g*.7152+c.b*.0722
	selected.assign(range(64));await render_many(32,{"rtxdi":true})
	check(device._rtxdi_mode and device.rtxdi.active and not device.rtxdi_failed,"actual RTXDI pipeline is active")
	check(device.rtxdi.frames==32,"reservoir frame counter counts actual traces")
	await read_raw(true);var summary:=reservoir_summary();observations.append(summary)
	check(summary.reused>size.x*size.y/2,"actual packed reservoirs contain temporal/spatial reuse")
	check(summary.finite and summary.maximum<=1040,"reservoir weights remain finite with bounded history")
	var accumulated:=Color(0,0,0,0)
	for i in 24:await step();await read_raw();accumulated+=raw_mean()/24.0
	var error:=0.0
	for c in 3:error=maxf(error,absf(accumulated[c]-reference[c])/maxf(reference[c],.001))
	observations.append({"local_reference":str(reference),"restir":str(accumulated),"relative_error":error})
	check(error<.05,"RTXDI preserves exact summed 64-light energy within 5 percent: "+str(error))
	var reused_error:=0.0;var fresh_error:=0.0
	FileAccess.open(out.path_join("reference-luminance.f32"),FileAccess.WRITE).store_buffer(reference_pixels.to_byte_array())
	for i in 24:
		await step();await read_raw();reused_error+=luminance_error(reference_pixels)/24.0
	await read_raw(true);raw_image.save_exr(out.path_join("reused-raw.exr"))
	FileAccess.open(out.path_join("reservoirs.bin"),FileAccess.WRITE).store_buffer(packed)
	FileAccess.open(out.path_join("di-control.bin"),FileAccess.WRITE).store_buffer(control_data)
	FileAccess.open(out.path_join("di-surfaces.bin"),FileAccess.WRITE).store_buffer(surface_data)
	for i in 24:
		await step({},false);await read_raw();fresh_error+=luminance_error(reference_pixels)/24.0
	raw_image.save_exr(out.path_join("fresh-ris-raw.exr"))
	observations.append({"reused_luminance_mse":reused_error,"fresh_ris_luminance_mse":fresh_error,"mse_ratio":reused_error/maxf(fresh_error,.000001)})
	check(reused_error<fresh_error*.65,"spatiotemporal reuse reduces raw luminance error versus 16 fresh RIS samples")
	var handles:=device.published_targets().duplicate()
	await step({},false);await read_raw(true);summary=reservoir_summary()
	check(summary.maximum<=16,"camera/history reset discards old reservoirs")
	check(device.published_targets()==handles,"reservoir changes preserve public lighting handles")
	await step({"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":2}]});await read_raw()
	check(raw_mean().r<.00001 and raw_mean().g<.00001,"fresh visibility rejects a newly inserted shadow-only blocker")
	await step({"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]});await read_raw()
	check(raw_mean().r>reference.r*.8,"removing the blocker restores current visibility immediately")
	selected.clear();await step();await read_raw()
	check(raw_mean().r<.00001 and raw_mean().g<.00001,"removed local lights cannot survive in old reservoirs")
	selected.assign([63]);colours[63]=Color(0,0,2,.04)
	await step({},false);await read_raw()
	check(raw_mean().b>.5 and raw_mean().r<.00001,"changed light membership uses the new light immediately")
	for i in 12:await step()
	var old_buffers: Array[RID]=[device.rtxdi._reservoirs,device.rtxdi._surfaces]
	size=Vector2i(173,99);await step();await read_raw(true);summary=reservoir_summary()
	check(device.output.get_width()==173 and device.rtxdi._size==size and summary.maximum<=16,"odd resize rebuilds the block-linear reservoir extent and resets history")
	check(not old_buffers.has(device.rtxdi._reservoirs) and not old_buffers.has(device.rtxdi._surfaces),"resize replaces private reservoir storage")
	await render_many(12,{"rtxdi":false,"nrd_directional":true})
	check(not device._rtxdi_mode and not device.rtxdi.active and device.rtxdi.bytes==0,"Off releases the optional reservoir allocations")
	check(device.nrd_active and device.nrd.directional,"Off preserves directional NRD fallback")
	await render_many(8,{"rtxdi":true,"ray_reconstruction":true})
	check(device._rtxdi_mode and device.ray_reconstruction and not device.nrd_active,"RTXDI can feed unfiltered RR inputs")
	history_limit=256;await render_many(2)
	check(not device._rtxdi_mode and not device.rtxdi.active,"Still accumulation restores reference direct-light sampling")
	history_limit=8;enable_sharc=true;await render_many(8,{"ray_reconstruction":false})
	check(device._rtxdi_mode and device.sharc.active and device.sharc.frames>0,"RTXDI coexists with actual SHaRC update and query shaders")
	enable_sharc=false;await render_many(2)
	check(device._rtxdi_mode and not device.sharc.active,"disabling SHaRC retains RTXDI")
	# New emissive scene; compare against the independent existing MIS tracer.
	selected.clear();mesh_data=mesh_data.slice(0,6*16)
	quad(mesh_data,[Vector3(-5,2,-5),Vector3(5,2,-5),Vector3(5,2,5),Vector3(-5,2,5)],Vector3.DOWN,Vector3(2,0,0))
	placements[1].mask=7
	check(await build_fixture(),"build textured-emitter transport fixture")
	var emission_reference:=0.0
	for i in 48:await step({},i>0);await read_raw();emission_reference+=raw_mean().r/48.0
	await render_many(24,{"rtxdi":true});var emission_di:=0.0
	for i in 48:await step();await read_raw();emission_di+=raw_mean().r/48.0
	var emission_error:=absf(emission_di-emission_reference)/maxf(emission_reference,.001)
	observations.append({"emitter_reference":emission_reference,"emitter_rtxdi":emission_di,"relative_error":emission_error})
	check(emission_di>.1 and emission_error<.07,"ReSTIR emitter sampling avoids duplicate BSDF energy: "+str(emission_error))
	await read_raw(true);check(reservoir_summary().reused>100,"emissive triangle reservoirs reuse samples")
	var ceiling:=mesh_data.slice(6*16,12*16)
	for vertex in 6:ceiling[vertex*16+12]=0
	await step({"poses":[{"geometry":1,"data":ceiling.to_byte_array()}]});await read_raw()
	check(raw_mean().r<.00001,"emitter removal invalidates the light table and old reservoirs")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(not device.rtxdi.active and not device.rtxdi._reservoirs.is_valid() and not device.rtxdi._surfaces.is_valid() and not device.rtxdi._neighbors.is_valid() and not device.rtxdi._control.is_valid() and not device.rtxdi._previous_frame.is_valid() and device._history.is_empty(),"device teardown releases RTXDI and ordinary lighting resources")
	FileAccess.open(out.path_join("rtxdi-results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	camera.queue_free();finish()
