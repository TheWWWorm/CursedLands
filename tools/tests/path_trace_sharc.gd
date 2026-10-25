extends "res://tools/tests/path_trace_quality.gd"
## Actual GPU cache population/query, light invalidation, NRD, resize and
## optional-resource failure. Run unchanged with native Vulkan and Wine DX12.
var progressive := false
var cache_counts := PackedInt32Array()
signal inspected
class FailingSharc extends "res://src/game/fx/path_trace_sharc.gd":
	var allocations := 0
	func allocate(bytes: int) -> RID:
		allocations+=1
		return RID() if allocations==3 else super.allocate(bytes)
class FailingPrepare extends "res://src/game/fx/path_trace_sharc.gd":
	var attempts := 0
	func prepare(_frame: PackedByteArray,_size: Vector2i) -> bool:
		attempts+=1
		return false
func frame(history:=true,gi:=true,shadows:=true) -> PackedByteArray:
	var data := super.frame(history,gi,shadows)
	data.encode_float(145*4,256 if progressive else 8)
	data.encode_float(77*4,1)
	return data
func inspect() -> void:
	cache_counts=device.sharc.counters();inspected.emit.call_deferred()
func set_cache(enabled: bool,replacement: RefCounted=null) -> void:
	if replacement!=null:device.sharc.dispose();device.sharc=replacement;device.sharc_failed=false
	device.sharc_enabled=enabled;device.sharc.diagnostics=true
	inspected.emit.call_deferred()
func continuous(count: int,changes: Dictionary={}) -> void:
	for i in count:
		RenderingServer.call_on_render_thread(device.render.bind(size,frame(true),changes if i==0 else {}))
		await frames(2)
	await RenderingServer.frame_post_draw
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(GraphicsAttribution.credits_bbcode().contains(RemakeText.t(GraphicsAttribution.SHARC_CREDIT)),"bundled cache is credited while the option is Off")
	check(FileAccess.file_exists("res://src/game/fx/shaders/SHARC_NOTICES.txt"),"export includes the complete SHaRC license")
	check(PathDevice.supported() and PathDevice.Sharc.supported(),"SHaRC-capable hardware PT and fp16 storage")
	if not PathDevice.supported():finish();return
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3;camera.position=Vector3(0,1,0.001);camera.look_at(Vector3.ZERO);camera.current=true
	size=Vector2i(160,90);sun_energy=0;sky_energy=0;bounces=4
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)],Vector3.UP,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,2,-2),Vector3(2,2,-2),Vector3(2,2,2),Vector3(-2,2,2)],Vector3.DOWN,Vector3(2,0,0))
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(-2,2,-2),Vector3(-2,2,2),Vector3(-2,0,2)],Vector3.RIGHT,Vector3.ZERO)
	quad(mesh_data,[Vector3(2,0,-2),Vector3(2,2,-2),Vector3(2,2,2),Vector3(2,0,2)],Vector3.LEFT,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,0,-2),Vector3(-2,2,-2),Vector3(2,2,-2),Vector3(2,0,-2)],Vector3.BACK,Vector3.ZERO)
	quad(mesh_data,[Vector3(-2,0,2),Vector3(-2,2,2),Vector3(2,2,2),Vector3(2,0,2)],Vector3.FORWARD,Vector3.ZERO)
	for vertex in mesh_data.size()/16:
		for c in 3:mesh_data[vertex*16+8+c]=0.6
	for i in 6:
		geometries.append({"offset":i*6,"count":6,"standard":true,"opaque":true,"surface":Vector3(1,0,0)})
		placements.append({"geometry":i,"transform":Transform3D.IDENTITY,"mask":7})
	check(await build_fixture(),"build enclosed diffuse room with coloured emission")
	if not device._ready:finish();return
	await render_many(24)
	var reference := mean(device.output)
	check(not device.sharc.active and device.sharc._owned.is_empty(),"Off allocates no cache resources")
	device.output.get_image().save_png(out.path_join("reference.png"))
	RenderingServer.call_on_render_thread(set_cache.bind(true));await inspected
	await continuous(40)
	check(device.sharc.active and not device.sharc_failed and device._sharc_mode==1,"SHaRC update/resolve/query path is active")
	check(device.nrd_active,"SHaRC output uses the existing native NRD denoiser")
	RenderingServer.call_on_render_thread(inspect);await inspected
	check(cache_counts.size()==4 and cache_counts[0]>0,"sparse update rays populate the actual GPU cache")
	check(cache_counts.size()==4 and cache_counts[1]>0 and cache_counts[2]>0,"main paths terminate on successful GPU cache queries: "+str(cache_counts))
	check(device.sharc.frames==40 and device.sharc.resets==1,"stationary cache persists across frames")
	var cached := mean(device.output)
	check(cached.r>reference.r*0.8 and cached.r<reference.r*1.8 and cached.g<0.003 and cached.b<0.003,
		"cached transport preserves coloured light without double-counting: %s / %s"%[cached,reference])
	check(device.sharc._buffers.size()==4 and device.sharc.CAPACITY*44==46137344,"cache memory has a fixed 44 MiB bound")
	device.output.get_image().save_png(out.path_join("sharc.png"))
	var backing := device.output.texture_rd_rid
	await continuous(2)
	check(device.output.texture_rd_rid==backing,"SHaRC retains stable output handles")
	size=Vector2i(193,109);await continuous(3)
	check(device.output.get_width()==193 and device.sharc.active and device.nrd_active,"odd-sized resize keeps all three cache passes and NRD usable")
	var old_resets: int=device.sharc.resets
	await continuous(1,{"instances":[{"index":2,"transform":Transform3D(Basis.IDENTITY,Vector3(-1,0,0)),"mask":7}]})
	check(device.sharc.resets>old_resets,"moving a blocker invalidates cached light")
	old_resets=device.sharc.resets
	await continuous(1,{"instances":[{"index":2,"transform":Transform3D(Basis.IDENTITY,Vector3(-1,0,0)),"mask":7}]})
	check(device.sharc.resets==old_resets,"identical transforms do not repeatedly clear the cache")
	var ceiling := mesh_data.slice(6*16,12*16)
	for vertex in 6:ceiling[vertex*16+12]=0
	await continuous(1,{"poses":[{"geometry":1,"data":ceiling.to_byte_array()}]})
	check(mean(device.output).r<0.001,"extinguished emitter leaves no cached or denoised light")
	progressive=true;await continuous(3)
	check(not device.sharc.active and device.sharc._owned.is_empty() and device._sharc_mode==0,"Still scene releases cache and uses exact bounded PT")
	progressive=false;sky_energy=0.2;await continuous(4)
	check(device.sharc.active and device.nrd_active,"Responsive mode recreates a clean cache")
	RenderingServer.call_on_render_thread(set_cache.bind(false));await inspected
	await continuous(2)
	check(not device.sharc.active and device.output_ready() and not device.sharc_failed,"live Off returns to ordinary PT")
	var failing := FailingSharc.new()
	RenderingServer.call_on_render_thread(set_cache.bind(true,failing));await inspected
	await continuous(2)
	check(device.sharc_failed and device.output_ready() and device._sharc_mode==0,"partial cache allocation failure falls back to working PT")
	check(failing.allocations==3 and failing._owned.is_empty(),"partial failure frees resources and does not retry every frame")
	var failed_update := FailingPrepare.new()
	RenderingServer.call_on_render_thread(set_cache.bind(true,failed_update));await inspected
	await continuous(2)
	check(device.sharc_failed and device.output_ready() and device.nrd_active and device._sharc_mode==0,"failed cache update rebinds and presents an ordinary PT/NRD frame")
	check(failed_update.attempts==1 and failed_update._owned.is_empty(),"failed update frees the initialized cache and suppresses retries")
	RenderingServer.call_on_render_thread(device.dispose);await frames(8)
	check(device.sharc._owned.is_empty() and device._sharc_sbts.is_empty() and device._owned.is_empty(),"teardown releases cache, descriptors and separate shader tables")
	report={"checks":checks,"failures":failures,"counters":Array(cache_counts),"reference":str(reference),"cached":str(cached)}
	FileAccess.open(out.path_join("sharc.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	camera.queue_free();await frames();finish()
