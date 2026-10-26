extends "res://tools/tests/path_trace_cover_receivers.gd"
## Real production compute plus visible production grass / stone / mushroom
## receivers. Old packages without the helper retain their actual raw receiver
## path and fail the temporal colour checks, rather than failing to load.
const HELPER_PATH="res://src/game/fx/path_trace_ground_irradiance.gd"
const SCREEN:=Vector2i(640,360)
const GRID:=Vector2i(128,72)
var rd: RenderingDevice
var helper: RefCounted
var raw: Array[RID]=[]
var wrappers: Array[Texture2DRD]=[]
var cooked: Image
var raw_result: Image
var sun_result: Image
var cooked_sun: Image
var dispatched_ok:=false
var helper_available:=false
var direct_available:=false
var histories:=[]
var contract_rows:=[]
var noise_tick:=0
signal completed

func rgba_image(colour: Color,extent:=GRID) -> Image:
	var image:=Image.create(extent.x,extent.y,false,Image.FORMAT_RGBAH);image.fill(colour);return image

func make_texture(image: Image) -> RID:
	var format:=RDTextureFormat.new();format.width=image.get_width();format.height=image.get_height()
	format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return rd.texture_create(format,RDTextureView.new(),[image.get_data()])

func setup_compute() -> void:
	rd=RenderingServer.get_rendering_device()
	if rd!=null:
		for i in 7:
			raw.append(make_texture(rgba_image(Color(0,0,0,0))))
			var wrapper:=Texture2DRD.new();wrapper.texture_rd_rid=raw[-1];wrappers.append(wrapper)
		if helper_available:helper.prepare(rd,GRID)
	completed.emit.call_deferred()

func packet(history:=true,limit:=8.0) -> PackedByteArray:
	var values:=PackedFloat32Array();values.resize(146);values[82]=float(history);values[145]=limit
	return values.to_byte_array()

func dispatch(light: Image,guide: Image,sun: Image,projection: Projection,transform: Transform3D,history:=true,reset:=false,limit:=8.0) -> void:
	dispatched_ok=true
	for row in [[raw[0],light],[raw[1],guide],[raw[6],sun]]:
		dispatched_ok=rd.texture_update(row[0],0,row[1].get_data())==OK and dispatched_ok
	if helper_available:dispatched_ok=helper.render(raw,packet(history,limit),projection,transform,reset) and dispatched_ok
	var extent:=Vector2i(light.get_width(),light.get_height())
	var result: RID=helper.output.texture_rd_rid if helper_available else raw[0]
	cooked=Image.create_from_data(extent.x,extent.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(result,0))
	raw_result=Image.create_from_data(extent.x,extent.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(raw[0],0))
	sun_result=Image.create_from_data(extent.x,extent.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(raw[6],0))
	var sun_rid: RID=helper.sun_output.texture_rd_rid if direct_available else raw[6]
	cooked_sun=Image.create_from_data(extent.x,extent.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(sun_rid,0))
	completed.emit.call_deferred()

func plane_guides(projection: Projection,transform: Transform3D,height:=0.0,extent:=GRID,normal:=Vector3.UP,geometric:=Vector3.UP) -> Image:
	var image:=rgba_image(Color(0,0,0,0),extent)
	var inverse:=projection.inverse();var view:=transform.affine_inverse()
	var ortho:=absf(projection[3][3]-1.0)<.00001
	for y in extent.y:
		for x in extent.x:
			var uv:=(Vector2(x,y)+Vector2(.5,.5))/Vector2(extent)
			var v:=inverse*Vector4(uv.x*2-1,1-uv.y*2,-1,1);v/=v.w
			var origin: Vector3=transform*Vector3(v.x,v.y,0) if ortho else transform.origin
			var ray: Vector3=-transform.basis.z if ortho else transform.basis*Vector3(v.x,v.y,v.z).normalized()
			var t: float=geometric.dot(Vector3(0,height,0)-origin)/geometric.dot(ray)
			if t>0:
				var depth:=-(view*(origin+ray*t)).z
				image.set_pixel(x,y,Color(normal.x,normal.y,normal.z,depth))
	return image

func noisy_light(sun: Color,tick_value: int,extent:=GRID) -> Image:
	var image:=rgba_image(Color(0,0,0,1),extent)
	# Independent path-like binary samples: deterministic, spatially varying,
	# nonnegative, with a stable expected irradiance. No frame-wide brightness
	# modulation that a legitimate temporal filter would have to preserve.
	for y in extent.y:
		for x in extent.x:
			var value: int=((x+1)*73856093)^((y+1)*19349663)^((tick_value+1)*83492791)
			value=(value^(value>>13))*1274126177;value=value^(value>>16)
			var gain:=2.0 if (value&1)!=0 else 0.0
			image.set_pixel(x,y,Color(sun.r+.12*gain,sun.g+.18*gain,sun.b+.09*gain,1))
	return image

func noisy_direct(tick_value: int) -> Image:
	var image:=noisy_light(Color(0,0,0,0),tick_value)
	for y in GRID.y:
		for x in GRID.x:
			# Binary fractions keep sun+ambient and its subtraction exact in
			# RGBA16F. This control must not mistake an8-bit presentation step
			# caused by decimal half-float rounding for lost native attenuation.
			image.set_pixel(x,y,Color(.25,.5,.125,0) if image.get_pixel(x,y).r>0 else Color(0,0,0,0))
	return image

func stats(values: Array) -> Dictionary:
	var mean:=0.0
	for value: float in values:mean+=value
	mean/=maxi(values.size(),1)
	var variance:=0.0
	for value: float in values:variance+=(value-mean)*(value-mean)
	return {"mean":mean,"stddev":sqrt(variance/maxi(values.size(),1)),"cv":sqrt(variance/maxi(values.size(),1))/maxf(absf(mean),.0001),"samples":values.size()}

func luma(c: Color) -> float:return c.r*.2126+c.g*.7152+c.b*.0722

func centre(image: Image) -> Color:return image.get_pixel(image.get_width()/2,image.get_height()/2)

func perform(light: Image,guide: Image,sun: Image,history:=true,reset:=false,limit:=8.0,projection:=Projection(),transform:=Transform3D.IDENTITY) -> void:
	if projection==Projection():projection=camera.get_camera_projection();transform=camera.global_transform
	RenderingServer.call_on_render_thread(dispatch.bind(light,guide,sun,projection,transform,history,reset,limit));await completed

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	helper_available=ResourceLoader.exists(HELPER_PATH)
	if helper_available:helper=load(HELPER_PATH).new()
	direct_available=helper_available and helper.get_property_list().any(func(p: Dictionary):return p.name=="sun_output")
	check(not helper_available or helper.memory_bytes()==0,"ground helper allocates no images before RR prepares a view")
	GameData.options.merge({"rtx_upscaling":0,"fsr_upscaling":0,"q_aa":0,"render_scale":4,"gfx_cloud_shadows":0},true)
	GameData.resolution_size="640x360";GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(SCREEN)
	GameData._window_gen+=1;get_window().borderless=true;get_window().size=SCREEN
	get_tree().root.scaling_3d_scale=1.0;get_tree().root.use_taa=false
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK
	env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;add_child(env)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.1;camera.position=Vector3(0,1.2,2);camera.look_at(Vector3(0,.24,0));camera.current=true
	receiver_material=ShaderMaterial.new();receiver_material.shader=Shader.new()
	receiver_material.shader.code="shader_type spatial;\n#define EI_GRASS_LIGHT\nrender_mode unshaded,cull_disabled,fog_disabled;\nconst vec3 ei_ambient=vec3(0);\nvec3 ei_lin(vec3 c){return c;}\n"+Receiver.COMMON+"""
uniform bool coverage=false;
uniform bool grass_root=false;
uniform float native_visibility=1.0;
void vertex(){
    vec3 root=grass_root?vec3(0):vec3(UV2.x,UV.x,UV2.y);
    ei_rt_ground=(MODEL_MATRIX*vec4(root,1)).xyz;
}
void fragment(){
    vec3 gi;vec4 a,b;
    bool valid=ei_rt_ground_sample(ei_rt_view_projection,ei_rt_inverse_view_projection,gi,a,b);
    // Same direct subtraction/reapplication as the production native light
    // hook, with explicit attenuation so reconstruction cannot hide its loss.
    ALBEDO=coverage?vec3(1):(valid?gi-a.rgb+a.rgb*native_visibility:vec3(1,0,1));
}
"""
	await frames(12);get_window().size=SCREEN;await frames(4)
	check(get_viewport().get_visible_rect().size==Vector2(SCREEN),"visible receiver fixture uses calibrated native output")
	RenderingServer.call_on_render_thread(setup_compute);await completed
	check(rd!=null and raw.size()==7 and raw.all(func(rid: RID):return rid.is_valid()),"real compute inputs prepare on the current graphics API")
	if raw.size()!=7 or not raw.all(func(rid: RID):return rid.is_valid()):finish();return
	for row in [[&"ei_rt_gi",wrappers[0]],[&"ei_rt_guide",wrappers[1]],[&"ei_pt_direct_sun",wrappers[6]],
		[&"ei_rt_shadow0",wrappers[2]],[&"ei_rt_shadow1",wrappers[3]],
		[&"ei_pt_active",1.0],[&"ei_pt_rr_active",1.0],[&"ei_pt_grass_shadows",1.0]]:
		RenderingServer.global_shader_parameter_set(row[0],row[1])
	for family in ["grass","stone","mushroom"]:await temporal_receiver(family)
	for family in ["grass","stone","mushroom"]:await temporal_direct_receiver(family)
	await contracts()
	RenderingServer.call_on_render_thread(finish_compute);await completed
	for key in [&"ei_rt_state",&"ei_rt_center"]:RenderingServer.global_shader_parameter_set(key,Vector4.ZERO)
	for key in [&"ei_pt_active",&"ei_pt_rr_active"]:RenderingServer.global_shader_parameter_set(key,0.0)
	for key in [&"ei_rt_gi",&"ei_rt_guide",&"ei_rt_shadow0",&"ei_rt_shadow1",&"ei_pt_direct_sun"]:RenderingServer.global_shader_parameter_set(key,null)
	FileAccess.open(out.path_join("ground-irradiance.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"helper_available":helper_available,"direct_available":direct_available,"driver":RenderingServer.get_current_rendering_driver_name(),"native_sdk_required":false,
		"geometry":geometry_cases,"temporal":histories,"contracts":contract_rows,"extra_image_bytes_at_4k_performance":1920*1080*(40 if direct_available else 24),
		"scope":"Production compute and planted-root lighting on actual grass, stone and mushroom meshes. Controlled independent path samples, fixed real geometry. Native RR and moving live river controls are separate."},"\t"))
	camera.queue_free();env.queue_free();await frames(4);finish()

func temporal_receiver(family: String) -> void:
	var object:=make_case(family);add_child(object)
	camera.size=1.1 if family=="grass" else .65
	camera.look_at(Vector3(0,.24 if family=="grass" else .10,0))
	receiver_material.set_shader_parameter("grass_root",family=="grass")
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	for row in [[&"ei_rt_inverse_view_projection",vp.inverse()],[&"ei_rt_view_projection",vp],[&"ei_rt_view",view],
		[&"ei_rt_eye",camera.position],[&"ei_rt_center",Vector4.ZERO],[&"ei_rt_state",Vector4(1,1,1,72)]]:
		RenderingServer.global_shader_parameter_set(row[0],row[1])
	var guide:=plane_guides(camera.get_camera_projection(),camera.global_transform)
	var direct:=Color(.03,.04,.02,0);var sun:=rgba_image(direct)
	receiver_material.set_shader_parameter("coverage",true)
	await frames(4);await RenderingServer.frame_post_draw
	var mask:=get_viewport().get_texture().get_image();receiver_mask.clear()
	for y in SCREEN.y:
		for x in SCREEN.x:
			var c:=mask.get_pixel(x,y)
			if c.r>.95 and c.g>.95 and c.b>.95:receiver_mask.append(Vector2(x,y))
	check(receiver_mask.size()>300,family+" has a visible nonempty production-mesh colour mask")
	receiver_material.set_shader_parameter("coverage",false)
	var values:=[];var raw_values:=[];var output_values:=[];var ages:=[];var readbacks:=true;var rejected:=0
	var root_pixel:=Vector2i(camera.unproject_position(ROOT)/Vector2(SCREEN)*Vector2(GRID))
	var backing: RID=helper.output.texture_rd_rid if helper_available else raw[0]
	for i in 80:
		var light:=noisy_light(direct,noise_tick);noise_tick+=1
		await perform(light,guide,sun,true,i==0)
		readbacks=readbacks and dispatched_ok and raw_result.get_data()==light.get_data() and sun_result.get_data()==sun.get_data()
		await frames(1);await RenderingServer.frame_post_draw
		var image:=get_viewport().get_texture().get_image()
		if i>=24:
			var total:=0.0;var count:=0
			for at in range(0,receiver_mask.size(),maxi(receiver_mask.size()/2000,1)):
				var c:=image.get_pixelv(Vector2i(receiver_mask[at]));total+=luma(c);count+=1
				if c.r>.7 and c.b>.7 and c.g<.1:rejected+=1
			values.append(total/maxi(count,1));raw_values.append(luma(raw_result.get_pixelv(root_pixel))-luma(direct))
			output_values.append(luma(cooked.get_pixelv(root_pixel))-(0.0 if helper_available else luma(direct)))
			ages.append(cooked.get_pixelv(root_pixel).a)
		if i==40:image.save_png(out.path_join(family+"-reconstructed.png"))
	var beauty:=stats(values);var noisy:=stats(raw_values);var filtered:=stats(output_values)
	check(readbacks,family+" reconstruction leaves raw main-RR radiance and direct-sun inputs byte-identical")
	check(rejected==0,family+" retains compatible planted-root lighting on every visible sample")
	check(noisy.cv>.5,family+" negative input contains substantial independently sampled indirect noise")
	check(beauty.samples==56 and beauty.mean>.03 and beauty.cv<.04,
		family+" visible colour remains stable across path samples: "+str(beauty))
	check(filtered.cv<.10,family+" reconstructed root indirect reduces temporal variance: "+str(filtered))
	check((helper.output.texture_rd_rid if helper_available else raw[0])==backing,family+" keeps the same physical lighting output through all frames")
	if helper_available:
		RenderingServer.call_on_render_thread(invalidate_helper);await completed
		await frames(2);await RenderingServer.frame_post_draw
		var fallback:=get_viewport().get_texture().get_image()
		RenderingServer.global_shader_parameter_set(&"ei_pt_ground_active",0.0)
		await frames(2);await RenderingServer.frame_post_draw
		var ordinary:=get_viewport().get_texture().get_image();var peak:=0.0
		for at in range(0,receiver_mask.size(),maxi(receiver_mask.size()/2000,1)):
			var p:=Vector2i(receiver_mask[at]);peak=maxf(peak,absf(luma(fallback.get_pixelv(p))-luma(ordinary.get_pixelv(p))))
		check(peak<.002,family+" invalid helper mask falls back to the same raw receiver signal")
		RenderingServer.global_shader_parameter_set(&"ei_pt_ground_active",1.0)
	else:check(true,family+" unfixed receiver already uses the raw fallback signal")
	histories.append({"family":family,"beauty":beauty,"raw":noisy,"filtered":filtered,"values":values,"root_values":output_values,"raw_values":raw_values,"ages":ages,"pixels":receiver_mask.size()})
	object.queue_free();await frames(2)

func temporal_direct_receiver(family: String) -> void:
	var object:=make_case(family);add_child(object)
	camera.size=1.1 if family=="grass" else .65
	camera.look_at(Vector3(0,.24 if family=="grass" else .10,0))
	receiver_material.set_shader_parameter("grass_root",family=="grass")
	var view:=Projection(camera.global_transform.affine_inverse());var vp:=camera.get_camera_projection()*view
	for row in [[&"ei_rt_inverse_view_projection",vp.inverse()],[&"ei_rt_view_projection",vp],[&"ei_rt_view",view],
		[&"ei_rt_eye",camera.position],[&"ei_rt_center",Vector4.ZERO],[&"ei_rt_state",Vector4(1,1,1,72)]]:
		RenderingServer.global_shader_parameter_set(row[0],row[1])
	var guide:=plane_guides(camera.get_camera_projection(),camera.global_transform)
	var ambient:=Color(.03125,.015625,.0625,0)
	receiver_material.set_shader_parameter("coverage",true)
	await frames(4);await RenderingServer.frame_post_draw
	var mask:=get_viewport().get_texture().get_image();receiver_mask.clear()
	for y in SCREEN.y:
		for x in SCREEN.x:
			var c:=mask.get_pixel(x,y)
			if c.r>.95 and c.g>.95 and c.b>.95:receiver_mask.append(Vector2(x,y))
	check(receiver_mask.size()>300,family+" direct visibility uses a visible production-mesh colour mask")
	receiver_material.set_shader_parameter("coverage",false)
	var values:=[];var raw_values:=[];var output_values:=[];var ages:=[];var readbacks:=true;var indirect_error:=0.0
	var root_pixel:=Vector2i(camera.unproject_position(ROOT)/Vector2(SCREEN)*Vector2(GRID))
	var backing: RID=helper.sun_output.texture_rd_rid if direct_available else raw[6]
	for i in 80:
		var sun:=noisy_direct(noise_tick);noise_tick+=1
		var light: Image=sun.duplicate()
		for y in GRID.y:
			for x in GRID.x:
				var c:=light.get_pixel(x,y);light.set_pixel(x,y,Color(c.r+ambient.r,c.g+ambient.g,c.b+ambient.b,1))
		await perform(light,guide,sun,true,i==0)
		readbacks=readbacks and dispatched_ok and raw_result.get_data()==light.get_data() and sun_result.get_data()==sun.get_data()
		await frames(1);await RenderingServer.frame_post_draw
		var image:=get_viewport().get_texture().get_image()
		if i>=24:
			var total:=0.0;var count:=0
			for at in range(0,receiver_mask.size(),maxi(receiver_mask.size()/2000,1)):
				total+=luma(image.get_pixelv(Vector2i(receiver_mask[at])));count+=1
			values.append(total/maxi(count,1));raw_values.append(luma(sun_result.get_pixelv(root_pixel)))
			output_values.append(luma(cooked_sun.get_pixelv(root_pixel)));ages.append(cooked_sun.get_pixelv(root_pixel).a)
			var indirect:=cooked.get_pixelv(root_pixel)
			indirect_error=maxf(indirect_error,Vector3(indirect.r-ambient.r,indirect.g-ambient.g,indirect.b-ambient.b).length())
		if i==40:image.save_png(out.path_join(family+"-direct-reconstructed.png"))
	var beauty:=stats(values);var noisy:=stats(raw_values);var filtered:=stats(output_values)
	check(readbacks,family+" direct reconstruction leaves both raw main-RR AOVs byte-identical")
	check(noisy.cv>.5,family+" direct negative control contains independent visibility noise")
	check(beauty.samples==56 and beauty.mean>.03 and beauty.cv<.05,family+" visible colour remains stable across sun visibility samples: "+str(beauty))
	check(filtered.cv<.12,family+" reconstructed direct signal reduces temporal variance: "+str(filtered))
	check(not helper_available or indirect_error<.001,family+" noisy direct visibility never enters the independent indirect history")
	check((helper.sun_output.texture_rd_rid if direct_available else raw[6])==backing,family+" keeps the same direct output through all frames")
	# Native ATTENUATION=0 must remove exactly the reconstructed direct signal.
	# Compare to the raw path, where the same synthetic sunlight cancels exactly.
	receiver_material.set_shader_parameter("native_visibility",0.0)
	await frames(2);await RenderingServer.frame_post_draw
	var shadowed:=get_viewport().get_texture().get_image()
	RenderingServer.global_shader_parameter_set(&"ei_pt_ground_active",0.0)
	await frames(2);await RenderingServer.frame_post_draw
	var fallback:=get_viewport().get_texture().get_image();var peak:=0.0;var total:=0.0;var count:=0
	for at in range(0,receiver_mask.size(),maxi(receiver_mask.size()/2000,1)):
		var p:=Vector2i(receiver_mask[at]);peak=maxf(peak,absf(luma(shadowed.get_pixelv(p))-luma(fallback.get_pixelv(p))))
		total+=luma(shadowed.get_pixelv(p));count+=1
	check(count>0 and total/count>.03 and peak<.003,family+" native shadow removes matching direct light without erasing indirect")
	RenderingServer.global_shader_parameter_set(&"ei_pt_ground_active",1.0 if helper_available else 0.0)
	receiver_material.set_shader_parameter("native_visibility",1.0)
	histories.append({"family":family,"channel":"direct","beauty":beauty,"raw":noisy,"filtered":filtered,
		"values":values,"root_values":output_values,"raw_values":raw_values,"ages":ages,"pixels":receiver_mask.size(),
		"native_shadow_error":peak,"indirect_error":indirect_error})
	object.queue_free();await frames(2)

func contracts() -> void:
	var projection:=camera.get_camera_projection();var transform:=camera.global_transform
	var guide:=plane_guides(projection,transform);var direct:=Color(.1,.2,.3,0);var sun:=rgba_image(direct)
	var constant:=rgba_image(Color(.3,.5,.7,1))
	await perform(constant,guide,sun,true,true)
	var value:=centre(cooked)
	check(Vector3(value.r-.2,value.g-.3,value.b-.4).length()<.002,"helper reconstructs indirect alone without filtering or subtracting an unrelated sun signal")
	var direct_value:=centre(cooked_sun)
	check(Vector3(direct_value.r-direct.r,direct_value.g-direct.g,direct_value.b-direct.b).length()<.002,"direct channel retains exact RGB illumination independently of indirect")
	for i in 12:await perform(noisy_light(direct,noise_tick+i),guide,sun)
	noise_tick+=12
	var previous_rid: RID=helper.output.texture_rd_rid if helper_available else raw[0]
	var previous_sun: RID=helper.sun_output.texture_rd_rid if direct_available else raw[6]
	RenderingServer.call_on_render_thread(replace_sources);await completed
	await perform(noisy_light(direct,noise_tick),guide,sun);noise_tick+=1
	check(not helper_available or helper.output.texture_rd_rid==previous_rid,"compatible scene handoff keeps physical helper output")
	check(not helper_available or centre(cooked).a>8,"compatible scene handoff preserves validated indirect history")
	check(direct_available and helper.sun_output.texture_rd_rid==previous_sun and centre(cooked_sun).a>=7,"compatible scene handoff preserves direct output and validated short history")
	for offset: float in [-.35,.35]:
		var shifted:=projection;shifted[2].x+=offset/GRID.x;shifted[2].y-=offset/GRID.y
		# Orthographic jitter lives in translation, unlike perspective jitter.
		if absf(projection[3][3]-1)<.00001:shifted=projection;shifted[3].x+=offset/GRID.x;shifted[3].y-=offset/GRID.y
		var jittered:=plane_guides(shifted,transform)
		await perform(noisy_light(direct,noise_tick),jittered,sun,true,false,8.0,shifted,transform);noise_tick+=1
		check(not helper_available or centre(cooked).a>8,"actual jittered projection retains the same ground history "+str(offset))
	await perform(constant,guide,sun,false)
	check(not helper_available or (centre(cooked).a>1.0 and centre(cooked).a<=3.0),"local cache invalidation preserves matching detail history with a short response")
	check(not direct_available or (centre(cooked_sun).a>1.0 and centre(cooked_sun).a<=3.0),"local light invalidation caps direct response without erasing its valid history")
	for i in 6:await perform(noisy_light(direct,noise_tick+i),guide,sun)
	noise_tick+=6
	await perform(noisy_light(direct,noise_tick),guide,sun,true,false,3.0);noise_tick+=1
	check(not helper_available or centre(cooked).a<=3.0,"torch and weather response respects the controller's short history")
	await perform(constant,guide,sun,true,true)
	check(not helper_available or is_equal_approx(centre(cooked).a,1.0),"camera-cut reset rejects previous detail lighting")
	check(not direct_available or is_equal_approx(centre(cooked_sun).a,1.0),"camera-cut reset rejects previous direct visibility")
	for kind in ["height","normal","missing"]:
		for i in 5:await perform(noisy_light(direct,noise_tick+i),guide,sun)
		noise_tick+=5
		var changed:=plane_guides(projection,transform,.4) if kind=="height" else plane_guides(projection,transform,0,GRID,Vector3(0,.5,.866)) if kind=="normal" else rgba_image(Color(0,0,0,0))
		await perform(constant,changed,sun)
		value=centre(cooked)
		check(not helper_available or (value.a==0.0 if kind=="missing" else is_equal_approx(value.a,1.0)),"changed "+kind+" rejects incompatible per-pixel history")
		contract_rows.append({"case":kind,"sample":[value.r,value.g,value.b,value.a]})
	await perform(constant,guide,sun,true,true)
	await perform(sun,guide,sun)
	value=centre(cooked)
	check(Vector3(value.r,value.g,value.b).length()<.001,"fresh dark neighbourhood cannot retain old indirect after an occlusion change")
	await direct_contracts(guide,projection,transform)
	var wall:=plane_guides(projection,transform,0,GRID,Vector3.RIGHT)
	await perform(constant,wall,sun)
	check(not helper_available or centre(cooked).a==0.0,"non-ground geometry leaves an explicit invalid fallback mask")
	# A tilted geometric plane is covered by the live ground receiver tests;
	# this control changes the shading normal only, preserving depth geometry.
	var relief:=plane_guides(projection,transform,0,GRID,Vector3(.6,.8,0))
	await perform(constant,relief,sun,true,true)
	check(not helper_available or centre(cooked).a>=1.0,"valid upward relief remains a usable ground signal")
	for ortho: bool in [false,true]:
		var control_projection:=projection if ortho else Projection.create_perspective(55,float(GRID.x)/GRID.y,.05,100)
		for slope: float in [-.3,.3]:
			var plane:=Vector3(slope,1,.2).normalized();var shading:=plane.rotated(Vector3.RIGHT,.2)
			var tilted:=plane_guides(control_projection,transform,0,GRID,shading,plane)
			await perform(constant,tilted,sun,true,true,8.0,control_projection,transform)
			for i in 8:await perform(constant,tilted,sun,true,false,8.0,control_projection,transform)
			var moved:=transform;moved.origin.x+=.015
			var moved_guides:=plane_guides(control_projection,moved,0,GRID,shading,plane)
			await perform(constant,moved_guides,sun,true,false,8.0,control_projection,moved)
			value=centre(cooked)
			check(Vector3(value.r-.2,value.g-.3,value.b-.4).length()<.002,"tilted relief preserves ordinary ground irradiance: %s/%s"%[ortho,slope])
			check(not helper_available or value.a>5.0,"moving %s view reprojects tilted ground history: %s"%["orthographic" if ortho else "perspective",slope])
	if helper_available:
		RenderingServer.call_on_render_thread(reject_invalid_packets.bind(projection,transform));await completed
		check(dispatched_ok,"malformed or incomplete frame input clears the visible validity mask")
		RenderingServer.call_on_render_thread(resize_and_release.bind(projection,transform));await completed
		check(dispatched_ok,"resize releases old helper images, retains shared sources and repeated disposal is safe")
	else:
		check(true,"unfixed raw path has no helper validity mask to invalidate")
		check(true,"unfixed raw path has no helper allocations to retire")

func direct_contracts(guide: Image,projection: Projection,transform: Transform3D) -> void:
	var indirect:=Color(.03,.02,.04,1);var bright:=Color(.1,.2,.3,0)
	var sun:=rgba_image(bright);var light:=rgba_image(indirect+bright)
	await perform(light,guide,sun,true,true,8,projection,transform)
	for i in 12:await perform(light,guide,sun,true,false,8,projection,transform)
	check(not direct_available or (centre(cooked_sun).a<=8 and centre(cooked_sun).a>=7),"direct visibility has its own short history rather than the32-frame indirect age")
	await perform(rgba_image(indirect),guide,rgba_image(Color(0,0,0,0)),true,false,8,projection,transform)
	check(luma(centre(cooked_sun))<.001,"new fully occluding caster removes stale direct light in the same frame")
	await perform(light,guide,sun,true,false,8,projection,transform)
	var value:=centre(cooked_sun)
	check(Vector3(value.r-bright.r,value.g-bright.g,value.b-bright.b).length()<.002,"removed caster restores direct light without retaining its old shadow")
	# Move a hard shadow edge through an unchanged receiving plane. Samples
	# beyond the bounded2-pixel spatial footprint must follow current visibility.
	for edge in [GRID.x/3,GRID.x*2/3]:
		var moving:=rgba_image(Color(0,0,0,0));var total:=rgba_image(indirect)
		for y in GRID.y:
			for x in GRID.x:
				if x>=edge:moving.set_pixel(x,y,bright);total.set_pixel(x,y,indirect+bright)
		await perform(total,guide,moving,true,false,8,projection,transform)
		var dark:=cooked_sun.get_pixel(edge-4,GRID.y/2);var lit:=cooked_sun.get_pixel(edge+4,GRID.y/2)
		check(luma(dark)<.001 and Vector3(lit.r-bright.r,lit.g-bright.g,lit.b-bright.b).length()<.002,"moving caster keeps both current dark and lit sides at edge"+str(edge))
	var changed:=Color(.3,.02,.01,0)
	await perform(rgba_image(indirect+changed),guide,rgba_image(changed),true,true,3,projection,transform)
	value=centre(cooked_sun)
	check(Vector3(value.r-changed.r,value.g-changed.g,value.b-changed.b).length()<.002,"strict lighting cut replaces direct RGB without constant-chroma assumptions")
	contract_rows.append({"case":"direct_visibility","sample":[value.r,value.g,value.b,value.a],"direct_available":direct_available})

func replace_sources() -> void:
	for i in [0,1,6]:
		var old:=raw[i];raw[i]=make_texture(rgba_image(Color(0,0,0,0)));wrappers[i].texture_rd_rid=raw[i];rd.free_rid(old)
	completed.emit.call_deferred()

func invalidate_helper() -> void:
	helper.invalidate();completed.emit.call_deferred()

func reject_invalid_packets(projection: Projection,transform: Transform3D) -> void:
	dispatched_ok=true
	for incomplete in [false,true]:
		helper.render(raw,packet(),projection,transform,false)
		var inputs: Array[RID]=raw.slice(0,2) if incomplete else raw
		var accepted: bool=helper.render(inputs,packet() if incomplete else PackedByteArray(),projection,transform,false)
		var image:=Image.create_from_data(GRID.x,GRID.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(helper.output.texture_rd_rid,0))
		dispatched_ok=dispatched_ok and not accepted and centre(image).a==0.0
		if direct_available:
			var sun_image:=Image.create_from_data(GRID.x,GRID.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(helper.sun_output.texture_rd_rid,0))
			dispatched_ok=dispatched_ok and centre(sun_image).a==0.0
	completed.emit.call_deferred()

func resize_and_release(projection: Projection,transform: Transform3D) -> void:
	var old: Array[RID]=helper._images.duplicate();var extent:=Vector2i(19,13)
	var resized: bool=helper.prepare(rd,extent)
	var old_released:=old.all(func(rid: RID):return not rd.texture_is_valid(rid))
	dispatched_ok=resized and old_released
	var small: Array[RID]=[]
	for i in 7:small.append(make_texture(plane_guides(projection,transform,0,extent) if i==1 else rgba_image(Color(.2,.3,.4,1) if i==0 else Color(0,0,0,0),extent)))
	dispatched_ok=helper.render(small,packet(),projection,transform,true) and dispatched_ok
	var image:=Image.create_from_data(extent.x,extent.y,false,Image.FORMAT_RGBAH,rd.texture_get_data(helper.output.texture_rd_rid,0))
	for y in extent.y:
		for x in extent.x:
			var value:=image.get_pixel(x,y)
			dispatched_ok=dispatched_ok and is_finite(value.r+value.g+value.b+value.a) and value.a>=1.0
	dispatched_ok=dispatched_ok and helper.memory_bytes()==extent.x*extent.y*(40 if direct_available else 24)
	var owned: Array[RID]=helper._images.duplicate();helper.dispose();helper.dispose()
	var private_released:=owned.all(func(rid: RID):return not rd.texture_is_valid(rid))
	var shared_retained:=raw.all(func(rid: RID):return rd.texture_is_valid(rid))
	# Texture2DRD's null setter detaches its renderer resource and clears size,
	# but the engine retains the numerical RD handle in its getter. Verify the
	# real allocation and renderer size, rather than RID's nonzero bit pattern.
	var detached: bool=not rd.texture_is_valid(helper.output.texture_rd_rid) and helper.output.get_width()==0 and helper.output.get_height()==0
	if direct_available:detached=detached and not rd.texture_is_valid(helper.sun_output.texture_rd_rid) and helper.sun_output.get_width()==0 and helper.sun_output.get_height()==0
	dispatched_ok=dispatched_ok and private_released and shared_retained and helper.memory_bytes()==0 and detached
	contract_rows.append({"case":"lifecycle","resized":resized,"old_images_released":old_released,"private_images_released":private_released,
		"shared_images_retained":shared_retained,"wrapper_detached":detached,"remaining_bytes":helper.memory_bytes(),"cached_wrapper_handle":helper.output.texture_rd_rid.get_id(),"small_dispatch_finite":dispatched_ok})
	for rid in small:rd.free_rid(rid)
	completed.emit.call_deferred()

func finish_compute() -> void:
	if helper_available:helper.dispose()
	for wrapper in wrappers:wrapper.texture_rd_rid=RID()
	for rid in raw:
		if rd.texture_is_valid(rid):rd.free_rid(rid)
	raw.clear();completed.emit.call_deferred()

func finish() -> void:
	print("PATH_TRACE_GROUND_IRRADIANCE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
