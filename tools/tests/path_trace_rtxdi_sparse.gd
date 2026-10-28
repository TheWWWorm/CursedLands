extends "res://tools/tests/path_trace_rtxdi.gd"
## Managed Quality keeps the exact <=7-light estimator without allocating
## per-pixel reservoirs. Compare actual raw light, including changing blockers,
## then cross the light-count and emissive-geometry boundaries on one device.
var legacy_lights:=false
var sparse_rows:=[]

func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data:=super.frame(history,gi,shadows)
	if legacy_lights:data.encode_float(191*4,0)
	return data

func rgb(colour: Color) -> Array:
	return [colour.r,colour.g,colour.b]

func rgb_error(value: Color,reference: Color) -> float:
	var error:=0.0
	for channel in 3:error=maxf(error,absf(value[channel]-reference[channel])/maxf(reference[channel],0.001))
	return error

func sparse_capture(label: String,changes: Dictionary={},history:=false) -> Image:
	await step(changes,history);await read_raw()
	var value:=raw_mean()
	sparse_rows.append({"case":label,"mean":rgb(value),"lights":selected.size(),
		"emitters":device.emitters.count,"rtxdi":device._rtxdi_mode,
		"reservoir_bytes":device.rtxdi.bytes,"deep_paths":device._deep_paths})
	raw_image.save_exr(out.path_join(label+".exr"))
	return raw_image.duplicate()

func reservoir_free() -> bool:
	return not device._rtxdi_mode and not device.rtxdi.active and device.rtxdi.bytes==0 \
		and not device.rtxdi._reservoirs.is_valid() and not device.rtxdi._surfaces.is_valid()

func average_raw(count: int,changes: Dictionary={}) -> Color:
	var value:=Color(0,0,0,0)
	for i in count:
		await step(changes if i==0 else {},i>0);await read_raw();value+=raw_mean()/float(count)
	return value

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	check(not OS.get_cmdline_user_args().has("--ei-pt-tuning"),"fixture exercises the managed sparse-light policy")
	check(PathDevice.supported(),"qualified sparse-light native PT device")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4
	camera.position=Vector3(0,0.7,0.001);camera.look_at(Vector3.ZERO)
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=4;history_limit=8
	quad(mesh_data,[Vector3(-5,0,-5),Vector3(5,0,-5),Vector3(5,0,5),Vector3(-5,0,5)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-5,1,-5),Vector3(5,1,-5),Vector3(5,1,5),Vector3(-5,1,5)],Vector3.DOWN,Vector3.ZERO)
	for x in [-1.5,1.5]:
		for z in [-1.5,1.5]:
			quad(mesh_data,[Vector3(x-0.5,2,z-0.5),Vector3(x+0.5,2,z-0.5),
				Vector3(x+0.5,2,z+0.5),Vector3(x-0.5,2,z+0.5)],Vector3.DOWN,Vector3(8,0,0))
	geometries=[{"offset":0,"count":6,"standard":true,"opaque":true},
		{"offset":6,"count":6,"standard":true,"opaque":true},
		{"offset":12,"count":24,"standard":true,"opaque":true}]
	placements=[{"geometry":0,"transform":Transform3D.IDENTITY,"mask":7},
		{"geometry":1,"transform":Transform3D.IDENTITY,"mask":0},
		{"geometry":2,"transform":Transform3D.IDENTITY,"mask":0}]
	check(await build_fixture(),"build sparse lights, a shadow-only blocker, and eight hidden emissive triangles")
	if not device._ready:finish();return
	for i in 8:
		var angle:=i*TAU/8.0
		lights.append(Vector4(cos(angle),2.0+0.1*(i%3),sin(angle),6))
		colours.append(Color(0.2+0.03*(i%3),0.1+0.02*(i%5),0.15+0.01*(i%7),0))
	var seven_reference: Image
	for count in [0,1,7]:
		selected.assign(range(count));tick=0
		var reference:=await sparse_capture("exact-%d"%count,{"rtxdi":false,"ray_reconstruction":true})
		tick=0
		var sparse:=await sparse_capture("managed-%d"%count,{"rtxdi":true})
		check(reservoir_free(),"%d local lights need no reservoir allocation or RTXDI dispatch"%count)
		check(sparse.get_data()==reference.get_data(),"%d local lights preserve exact raw RGB illumination"%count)
		check(device._deep_paths and device.ray_reconstruction and not device.nrd_active and device._size==size,
			"%d-light fast path retains four bounces, native RR inputs and the render grid"%count)
		var energy:=raw_mean()
		check(energy.r==0 and energy.g==0 and energy.b==0 if count==0 else minf(energy.r,minf(energy.g,energy.b))>0.05,
			"%d-light fixture has the expected finite coloured energy"%count)
		if count==7:seven_reference=reference
	var handles:=device.published_targets().duplicate()
	# The eighth light must activate the reservoir estimator. Obtain its
	# independent reference by summing two exact small-light renders.
	var eight_reference:=Color(0,0,0,0)
	for group in [range(7),[7]]:
		selected.assign(group);await sparse_capture("eight-reference-"+str(group[0]),{"rtxdi":false})
		eight_reference+=raw_mean()
	selected.assign(range(8))
	var eight:=await average_raw(32,{"rtxdi":true})
	check(device._rtxdi_mode and device.rtxdi.active and device.rtxdi.bytes>0,"the eighth light activates actual RTXDI resources")
	check(rgb_error(eight,eight_reference)<0.05,"eight-light reservoir output preserves independently summed RGB energy")
	check(device._deep_paths and device.ray_reconstruction,"many-light transition preserves four-bounce raw reconstruction")
	await sparse_capture("eight-blocked",{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":2}]})
	check(raw_mean().r<0.00001 and raw_mean().g<0.00001 and raw_mean().b<0.00001,"new blockers occlude the many-light estimator immediately")
	await sparse_capture("eight-unblocked",{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]})
	check(raw_mean().r>eight_reference.r*0.8,"removing the blocker restores many-light illumination")
	selected.assign(range(7));tick=0
	var restored:=await sparse_capture("seven-restored")
	check(reservoir_free(),"returning to seven lights releases the optional reservoir storage")
	check(restored.get_data()==seven_reference.get_data(),"returning to seven lights restores exact current illumination without reservoir history")
	check(device.published_targets()==handles,"estimator transitions preserve public lighting texture handles")
	await sparse_capture("seven-blocked",{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":2}]})
	check(raw_mean().r<0.00001 and raw_mean().g<0.00001 and raw_mean().b<0.00001,"the exact sparse estimator retains real shadow occlusion")
	tick=0
	var clear:=await sparse_capture("seven-unblocked",{"instances":[{"index":1,"transform":Transform3D.IDENTITY,"mask":0}]})
	check(clear.get_data()==seven_reference.get_data(),"removing a sparse-light blocker restores exact current RGB")
	check(device.rtxdi_enabled and not device.rtxdi_failed,"adaptive selection retains the requested feature and healthy fallback state")
	legacy_lights=true;tick=0
	var legacy_reference:=await sparse_capture("legacy-reference",{"rtxdi":false})
	tick=0
	var legacy:=await sparse_capture("legacy-managed",{"rtxdi":true})
	check(reservoir_free(),"the legacy seven-slot light table also bypasses reservoirs")
	check(legacy.get_data()==legacy_reference.get_data(),"legacy table dispatch preserves exact raw illumination")
	legacy_lights=false
	# A finite emitter radius still uses the original ray samples, not a
	# point-light approximation hidden inside the performance fast path.
	selected.assign([0]);colours[0].a=0.15;tick=0
	var area_reference:=await sparse_capture("area-reference",{"rtxdi":false})
	tick=0
	var area:=await sparse_capture("area-managed",{"rtxdi":true})
	check(reservoir_free() and area.get_data()==area_reference.get_data(),"sparse area lights keep the exact existing finite-radius samples")
	selected.clear()
	var prepared_variants: int=device._variants.size()
	await sparse_capture("emitter-appears",{"instances":[{"index":2,"transform":Transform3D.IDENTITY,"mask":7}]})
	check(device.emitters.count==8 and raw_mean().r>0.02,"new emissive geometry contributes on its first visible frame")
	await sparse_capture("emitter-reservoir")
	check(device._rtxdi_mode and device.rtxdi.active,"registered emitters activate RTXDI with zero local lights")
	check(device._variants.size()==prepared_variants,"emitter eligibility changes reuse prewarmed pipeline variants")
	var emission_reference:=await average_raw(32,{"rtxdi":false})
	var emission_di:=await average_raw(32,{"rtxdi":true})
	sparse_rows.append({"case":"emitter-comparison","reference":rgb(emission_reference),"managed":rgb(emission_di)})
	check(emission_di.r>0.02 and rgb_error(emission_di,emission_reference)<0.1,"emissive transition retains reference transport energy")
	await sparse_capture("emitter-removed",{"instances":[{"index":2,"transform":Transform3D.IDENTITY,"mask":0}]})
	check(raw_mean().r<0.00001 and raw_mean().g<0.00001,"removed emission cannot survive in old reservoir lighting")
	await sparse_capture("empty-restored")
	check(reservoir_free(),"empty scene returns to the allocation-free exact light path")
	check(device._deep_paths and device.ray_reconstruction and device._size==size,"all light transitions preserve the chosen four-bounce workload")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(not device.rtxdi.active and device._history.is_empty(),"sparse and reservoir resources tear down cleanly")
	FileAccess.open(out.path_join("rtxdi-sparse.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":sparse_rows},"\t"))
	camera.queue_free();finish()
