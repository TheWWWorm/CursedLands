extends Node
## A subpass ALPHA value must survive screen and radiance sampling unchanged.
## Read back the actual sky radiance separately from the half/quarter screen
## target. Run on paired isolated runtimes.
var checks := 0
var failures := 0
var rows := []

class BufferProbe extends CompositorEffect:
	var guard:=Mutex.new()
	var buffers:Dictionary={}
	func _init() -> void:
		effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_type:int,data:RenderData) -> void:
		var scene:=data.get_render_scene_buffers() as RenderSceneBuffersRD
		var current:Dictionary={}
		for key in ["half_texture","quarter_texture"]:
			if scene.has_texture("sky_buffers",key):
				var format:=scene.get_texture_format("sky_buffers",key)
				current[key]={"format":format.format,"width":format.width,"height":format.height,
					"rid":scene.get_texture("sky_buffers",key)}
		guard.lock();buffers=current;guard.unlock()
	func snapshot() -> Dictionary:
		guard.lock();var copy:=buffers.duplicate(true);guard.unlock();return copy

static func inspect_rids(job:Dictionary) -> void:
	var rd:=RenderingServer.get_rendering_device();job.valid=[]
	for rid:RID in job.rids:job.valid.append(rd.texture_is_valid(rid))
	job.done.post()

func valid_rids(rids:Array) -> Array:
	var job:={"rids":rids,"valid":[],"done":Semaphore.new()}
	RenderingServer.call_on_render_thread(inspect_rids.bind(job));job.done.wait();return job.valid

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

func frames(count:int) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func shot(view:SubViewport,label:String) -> Image:
	await frames(24)
	var image:=view.get_texture().get_image();image.convert(Image.FORMAT_RGBA8)
	image.save_png("user://sky-alpha-"+label+".png")
	return image

func difference(a:Image,b:Image) -> Dictionary:
	var aa:=a.get_data();var bb:=b.get_data();var changed:=0;var over:=0;var peak:=0
	for i in range(0,aa.size(),4):
		var d:=maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed+=int(d>0);over+=int(d>2);peak=maxi(peak,d)
	return {"changed_pixels":changed,"pixels_over_2":over,"peak_delta":peak}

func program(env:Environment,source:String) -> void:
	var shader:=Shader.new();shader.code=source
	var material:=ShaderMaterial.new();material.shader=shader
	# A new typed material also marks the radiance cache dirty. Rewriting a
	# zero-uniform shader in place does not issue a uniform-set update.
	env.sky.sky_material=material

func radiance(env:Environment,label:String) -> Image:
	var image:=RenderingServer.sky_bake_panorama(env.sky.get_rid(),1.0,false,Vector2i(64,32))
	check(image!=null,"radiance texture exists "+label)
	if image==null:return Image.create(64,32,false,Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8);image.save_png("user://sky-alpha-radiance-"+label+".png")
	return image

func _ready() -> void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()=="gl_compatibility":
		printerr("SKY_ALPHA requires Forward+ or Mobile");get_tree().quit(1);return
	Engine.time_scale=0;Engine.max_fps=120;process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	await frames(3)
	var view:=SubViewport.new();view.size=Vector2i(128,128);view.own_world_3d=true
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.position=Vector3(0,0,3);camera.current=true
	var probe:=BufferProbe.new();camera.compositor=Compositor.new();camera.compositor.compositor_effects=[probe]
	var previous_rids:Array=[]
	var patched:=OS.has_feature("ei_sky_subpass_alpha")
	var env:=Environment.new();env.background_mode=Environment.BG_SKY
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.sky=Sky.new();env.sky.radiance_size=Sky.RADIANCE_SIZE_256;env.sky.process_mode=Sky.PROCESS_MODE_REALTIME
	var material:=ShaderMaterial.new();material.shader=Shader.new()
	material.shader.code="shader_type sky; void sky(){COLOR=vec3(0.0);}"
	env.sky.sky_material=material
	camera.environment=env
	var sphere:=MeshInstance3D.new();sphere.mesh=SphereMesh.new()
	var metal:=StandardMaterial3D.new();metal.metallic=1;metal.roughness=0
	sphere.material_override=metal;view.add_child(sphere)
	for alpha in [0.0,.25,.625,1.0]:
		program(env,"shader_type sky; void sky(){COLOR=vec3(%s);}"%alpha)
		var reference:=await shot(view,"reference-"+str(alpha))
		if patched:
			check(probe.snapshot().is_empty(),"ordinary sky keeps no half or quarter allocation")
			check(valid_rids(previous_rids).all(func(v):return not v),"switch to ordinary sky frees the previous subpass RID")
		check(reference.get_pixel(0,0).r>0.1 if alpha>0 else reference.get_pixel(0,0).r<0.01,"reference sky visibly renders its constant value "+str(alpha))
		var reference_radiance:=radiance(env,"reference-"+str(alpha))
		check(reference_radiance.get_pixel(32,16).r>0.05 if alpha>0 else reference_radiance.get_pixel(32,16).r<0.01,"reference radiance contains its constant value "+str(alpha))
		for quality in ["half","quarter"]:
			var flag:="AT_HALF_RES_PASS" if quality=="half" else "AT_QUARTER_RES_PASS"
			var colour:="HALF_RES_COLOR" if quality=="half" else "QUARTER_RES_COLOR"
			program(env,"shader_type sky; render_mode use_"+quality+"_res_pass; void sky(){if("+flag+"){COLOR=vec3(.13,.27,.51);ALPHA="+str(alpha)+";}else{COLOR=vec3("+colour+".a);}}")
			var actual:=await shot(view,quality+"-"+str(alpha))
			var buffers:=probe.snapshot();var key:String=quality+"_texture"
			check(buffers.has(key),"render-thread probe observes the "+quality+" buffer")
			if patched:
				check(buffers.size()==1,"quality switch keeps only its active subpass")
				check(valid_rids(previous_rids).all(func(v):return not v),"quality switch releases the former subpass RID")
				if buffers.has(key):
					var target:Dictionary=buffers[key];var size:=64 if quality=="half" else 32
					check(target.format==RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT and target.width==size and target.height==size,"ALPHA subpass uses only the bounded high precision target")
			previous_rids.clear()
			for buffer:Dictionary in buffers.values():previous_rids.append(buffer.rid)
			var delta:=difference(reference,actual)
			var radiance_delta:=difference(reference_radiance,radiance(env,quality+"-"+str(alpha)))
			check(delta.pixels_over_2==0,"screen "+quality+" alpha remains linear: "+str(alpha))
			check(radiance_delta.pixels_over_2==0,"radiance "+quality+" alpha remains linear: "+str(alpha))
			rows.append({"quality":quality,"alpha":alpha,"delta":delta,"radiance_delta":radiance_delta})
	# RGB-only subpasses retain the backend's original allocation and pixels.
	program(env,"shader_type sky; void sky(){COLOR=vec3(.25);}")
	var rgb_reference:=await shot(view,"rgb-reference")
	var rgb_radiance:=radiance(env,"rgb-reference")
	for quality in ["half","quarter"]:
		var flag:="AT_HALF_RES_PASS" if quality=="half" else "AT_QUARTER_RES_PASS"
		var colour:="HALF_RES_COLOR" if quality=="half" else "QUARTER_RES_COLOR"
		program(env,"shader_type sky; render_mode use_"+quality+"_res_pass; void sky(){if("+flag+"){COLOR=vec3(.25);}else{COLOR="+colour+".rgb;}}")
		var image:=await shot(view,"rgb-"+quality);var buffers:=probe.snapshot()
		var delta:=difference(rgb_reference,image);var reflected:=difference(rgb_radiance,radiance(env,"rgb-"+quality))
		check(delta.pixels_over_2==0 and reflected.pixels_over_2==0,"RGB-only "+quality+" preserves screen and radiance colour")
		var format:=RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32 if RenderingServer.get_current_rendering_method()=="mobile" else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		check(buffers.has(quality+"_texture") and buffers[quality+"_texture"].format==format,"RGB-only "+quality+" retains the original backend format")
		rows.append({"rgb_quality":quality,"delta":delta,"radiance_delta":reflected,"buffers":buffers})
		previous_rids.clear()
		for buffer:Dictionary in buffers.values():previous_rids.append(buffer.rid)
	view.free();await frames(4)
	check(valid_rids(previous_rids).all(func(v):return not v),"viewport teardown releases all observed subpass targets")
	TexUpscale.shutdown();UnitWounds.shutdown()
	FileAccess.open("user://sky-alpha.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"native_capability":OS.has_feature("ei_sky_subpass_alpha"),"rows":rows},"\t"))
	print("SKY_ALPHA checks=",checks," failures=",failures);get_tree().quit(1 if failures else 0)
