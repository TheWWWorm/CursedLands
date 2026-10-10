extends Node
const Probe = preload("camera_depth_of_field_probe.gd")
var checks := 0
var failures := 0
var samples: Array = []
var viewport: SubViewport
var camera: Camera3D
var attrs: CameraAttributesPractical
var probe: Probe
var boards: Array[MeshInstance3D] = []
var targets: Array[MeshInstance3D] = []
const SIZE := Vector2i(1280,720)

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func frames(count := 5) -> void:
	for i in count: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func read_focus(label: String, owner: Probe = null) -> Dictionary:
	var source := owner if owner else probe
	RenderingServer.call_on_render_thread(source.read_buffers)
	var data: Dictionary = await source.sampled
	data.label = label
	samples.append(data)
	print("GPU_FOCUS ", JSON.stringify(data))
	return data

func expect_focus(data: Dictionary, wanted: float, label: String) -> void:
	check(data.allocated and data.focus.size() == 2 and absf(data.focus[0]-wanted) < maxf(.003, wanted*.001) and absf(data.focus[1]-wanted) < maxf(.003, wanted*.001), label)

func set_reference(enabled: bool, reset := false) -> void:
	attrs.dof_blur_far_enabled = enabled
	RenderingServer.call("camera_attributes_set_far_dof", attrs.get_rid(), enabled, 1.0, .3, reset)

func place(mesh: MeshInstance3D, depth: float) -> void:
	var rect: Rect2 = mesh.get_meta("rect")
	var extent := camera.size*.5 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else tan(deg_to_rad(camera.fov)*.5)*depth
	var aspect := float(viewport.size.x)/viewport.size.y
	mesh.mesh.size = Vector2(extent*2*aspect,extent*2)*rect.size
	mesh.position = Vector3((rect.get_center().x-.5)*extent*2*aspect,(.5-rect.get_center().y)*extent*2,-depth)
	mesh.set_meta("depth", depth)

func board(rect: Rect2, depth: float, a: Color, b: Color, stripes := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.set_meta("rect", rect)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, fog_disabled, cull_disabled; uniform vec3 a; uniform vec3 b; uniform bool stripes; void fragment(){ALBEDO = stripes && fract(UV.x*320.0)>.5 ? b:a;}"
	var mat := ShaderMaterial.new(); mat.shader = shader
	mat.set_shader_parameter("a",Vector3(a.r,a.g,a.b)); mat.set_shader_parameter("b",Vector3(b.r,b.g,b.b)); mat.set_shader_parameter("stripes",stripes)
	mesh.material_override = mat; viewport.add_child(mesh); boards.append(mesh); place(mesh,depth)
	return mesh

func setup() -> void:
	viewport = SubViewport.new(); viewport.size = SIZE; viewport.own_world_3d = true
	# These boards are instantaneous depth fixtures, not moving game actors.
	# The game enables physics interpolation globally; the standalone probe
	# does not. Keep the same authored depths in either hosting project.
	viewport.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	if "--msaa" in OS.get_cmdline_user_args(): viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; get_tree().root.add_child(viewport)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0,.5,.6)
	viewport.add_child(env)
	camera = Camera3D.new(); camera.fov = 55; camera.far = 1000; camera.near = .05; viewport.add_child(camera); camera.make_current()
	attrs = CameraAttributesPractical.new(); attrs.dof_blur_amount = .012 * .2 * SIZE.y / 64.0; camera.attributes = attrs
	probe = Probe.new(); var compositor := Compositor.new(); compositor.compositor_effects = [probe]; camera.compositor = compositor
	board(Rect2(.03,.24,.94,.35),160,Color(0,1,0),Color(0,0,1),true)
	board(Rect2(.03,.65,.94,.30),20,Color(.03,.03,.03),Color(.8,.8,.8),true)
	board(Rect2(.28,.20,.08,.52),12,Color(1,0,0),Color(1,0,0))
	for k in 9:
		var uv := Vector2(.5,.5) + Vector2(k%3-1,k/3-1)*.05
		targets.append(board(Rect2(uv-Vector2(.012,.012),Vector2(.024,.024)),20,Color(.4,.4,.4),Color(.4,.4,.4)))
	var ui := CanvasLayer.new(); viewport.add_child(ui)
	var panel := ColorRect.new(); panel.position = Vector2(20,20); panel.size = Vector2(440,90); ui.add_child(panel)
	var shader := Shader.new(); shader.code = "shader_type canvas_item; void fragment(){ COLOR=mod(floor(FRAGCOORD.x/2.0)+floor(FRAGCOORD.y/2.0),2.0)>.5 ? vec4(1,.1,1,1):vec4(1,1,.1,1); }"
	panel.material = ShaderMaterial.new(); panel.material.shader = shader

func picture(label: String) -> Image:
	await frames()
	var img := viewport.get_texture().get_image()
	check(img.save_png("user://"+label+".png")==OK,"capture "+label)
	return img

func difference(a: Image, b: Image, rect: Rect2i) -> Dictionary:
	var aa := a.get_region(rect).get_data(); var bb := b.get_region(rect).get_data()
	var changed := 0; var error := 0
	for i in aa.size():
		changed += int(aa[i] != bb[i]); error += absi(int(aa[i])-int(bb[i]))
	return {"changed":changed,"error":error}

func verify_image(before: Image, after: Image, label: String) -> void:
	for record in [[Rect2i(20,20,440,90),"Canvas UI"],[Rect2i(358,180,103,230),"foreground and silhouette"],[Rect2i(650,510,500,140),"in-focus field"],[Rect2i(640,30,500,70),"sky away from horizon"]]:
		check(difference(before,after,record[0]).changed == 0,label+" keeps "+record[1]+" exact")
	var far_delta := difference(before,after,Rect2i(700,220,400,90))
	print("FAR_DELTA ",label," ",JSON.stringify(far_delta))
	check(far_delta.changed > 100,label+" blurs far detail")
	var red_bleed := 0.0
	for x in range(461,480):
		for y in range(240,370): red_bleed=maxf(red_bleed,after.get_pixel(x,y).r-before.get_pixel(x,y).r)
	check(red_bleed == 0,label+" rejects foreground colour in far blur")

func run() -> void:
	check(OS.has_feature("ei_far_dof_reference") and RenderingServer.has_method("camera_attributes_set_far_dof"),"native explicit opt-in is present")
	if failures or DisplayServer.get_name() == "headless": get_tree().quit(1); return
	print("RENDERER ",RenderingServer.get_current_rendering_method())
	if "--hdr-probe" in OS.get_cmdline_user_args():
		await hdr_probe()
		return
	if "--scale-probe" in OS.get_cmdline_user_args():
		await scale_probe()
		return
	var high := "--high" in OS.get_cmdline_user_args()
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_MEDIUM if high else RenderingServer.DOF_BLUR_QUALITY_LOW,false)
	print("R1_GATHER_TAPS ",40 if high else 16)
	setup(); set_reference(false)
	var before := await picture("off")
	check(not (await read_focus("off")).allocated,"disabled lens allocates no targets")
	set_reference(true,true); await frames()
	expect_focus(await read_focus("first"),20,"GPU centre median starts at true rendered depth")
	var after := await picture("default")
	verify_image(before,after,"default strength")
	attrs.dof_blur_amount = .012 * 1.0 * SIZE.y / 64.0
	var strong := await picture("strong")
	verify_image(before,strong,"strong lens")
	var horizon := difference(before,strong,Rect2i(650,163,500,9))
	print("HORIZON ",JSON.stringify(horizon))
	check(horizon.changed > 0,"far terrain covers neighbouring sky at horizon")
	check(difference(before,strong,Rect2i(650,150,500,10)).changed == 0,"horizon influence is bounded to blur radius")
	place(targets[4],3); await frames()
	expect_focus(await read_focus("outlier"),20,"one foreground crossing does not pull focus")
	for k in 5: place(targets[k],80)
	var monotonic := true; var last := 20.0; var first_value := 0.0
	var response: Array = []
	for k in 15:
		await frames(2)
		var data := await read_focus("smoothing-%d"%k)
		response.append(data)
		var value: float = data.focus.max()
		if k==0: first_value=value
		monotonic=monotonic and value>=last-.01 and value<=80.1 and value>=19.99
		last=value
		await get_tree().create_timer(.025).timeout
	check(monotonic and first_value < 79.0 and last > first_value,"GPU focus approaches changed median smoothly without overshoot")
	var aa: Dictionary=response[2];var bb: Dictionary=response[-1]
	var measured_seconds: float = -(bb.time-aa.time)/log(log(80.0/bb.focus.max())/log(80.0/aa.focus.max()))
	print("FOCUS_TIME_CONSTANT ",measured_seconds)
	check(absf(measured_seconds-.3)<.04,"GPU logarithmic focus response matches 0.3 second time constant")
	await get_tree().create_timer(1.8).timeout; await frames()
	expect_focus(await read_focus("settled"),80,"GPU focus settles on majority depth")
	for mesh in targets: place(mesh,7)
	set_reference(true,true); await frames(3)
	expect_focus(await read_focus("cut"),7,"explicit camera cut discards old focus")
	for mesh in boards: mesh.visible=false
	set_reference(true,true); await frames(3)
	expect_focus(await read_focus("sky"),600,"clear sky uses bounded far focus")
	for mesh in targets: mesh.visible=true; place(mesh,.5)
	set_reference(true,true); await frames(3)
	expect_focus(await read_focus("near-clamp"),2,"near geometry uses bounded minimum focus")
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=20
	for mesh in targets: place(mesh,37)
	set_reference(true,true); await frames(3)
	expect_focus(await read_focus("orthogonal"),37,"orthographic reverse-Z depth is reconstructed correctly")
	viewport.size=Vector2i(1001,751)
	for mesh in targets: place(mesh,37)
	await frames(5)
	var resized := await read_focus("odd-resize")
	expect_focus(resized,37,"viewport resize resets focus to current geometry")
	check(resized.textures.work_a.slice(0,2)==[501,376],"odd viewport rounds work textures upward")
	check(resized.previous_valid==0,"viewport resize retires old native texture RIDs")
	viewport.size=Vector2i(1001,1441)
	for mesh in targets: place(mesh,37)
	await frames(5)
	var large := await read_focus("large-resize")
	check(large.textures.work_a.slice(0,2)==[334,481],"tall viewport uses bounded one-third work resolution")
	var second := SubViewport.new(); second.size=Vector2i(640,480); second.own_world_3d=true
	second.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	second.render_target_update_mode=SubViewport.UPDATE_ALWAYS;get_tree().root.add_child(second)
	var second_camera := Camera3D.new();second_camera.far=1000;second.add_child(second_camera);second_camera.make_current()
	var second_attrs := CameraAttributesPractical.new();second_attrs.dof_blur_far_enabled=true;second_attrs.dof_blur_amount=.05
	second_camera.attributes=second_attrs
	var second_probe := Probe.new();var second_compositor := Compositor.new();second_compositor.compositor_effects=[second_probe];second_camera.compositor=second_compositor
	var plane := MeshInstance3D.new();plane.mesh=QuadMesh.new();plane.mesh.size=Vector2(300,300);plane.position.z=-91;second.add_child(plane)
	RenderingServer.call("camera_attributes_set_far_dof",second_attrs.get_rid(),true,1.0,.3,true)
	await frames(5)
	expect_focus(await read_focus("second-view",second_probe),91,"second viewport has independent median focus")
	expect_focus(await read_focus("first-view-retained"),37,"second viewport does not overwrite first focus history")
	set_reference(false); await frames(3)
	var disabled := await read_focus("disabled")
	check(not disabled.allocated and disabled.previous_valid==0,"disabling releases focus and work texture RIDs")
	expect_focus(await read_focus("second-view-retained",second_probe),91,"disabling first lens leaves other viewport intact")
	var file := FileAccess.open("user://focus.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"\t")); file.close()
	camera.compositor=null; probe.buffers=null; viewport.queue_free()
	second_camera.compositor=null;second_probe.buffers=null;second.queue_free(); await frames(2)
	print("FAR_DOF_NATIVE %d checks %d failures"%[checks,failures]); get_tree().quit(0 if failures==0 else 1)

func scale_probe() -> void:
	setup();set_reference(true,true)
	viewport.scaling_3d_scale=.75
	await frames(8)
	var scaled := await read_focus("scaled-bilinear")
	expect_focus(scaled,20,"scaled colour/depth agree on centre focus")
	check(scaled.textures.work_a.slice(0,2)==[480,270],"spatial scaling uses internal colour resolution")
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_FSR2
		for mesh in targets:place(mesh,47)
		await frames(8)
		var upscaled := await read_focus("scaled-fsr2")
		expect_focus(upscaled,47,"temporal upscale samples the correct internal depth positions")
		check(upscaled.textures.work_a.slice(0,2)==[640,360],"temporal upscale uses output colour resolution")
	viewport.transparent_bg=true;await frames(5)
	var transparent := await read_focus("transparent")
	check(not transparent.allocated and transparent.previous_valid==0,"transparent viewport releases unsupported effect")
	viewport.transparent_bg=false
	for mesh in targets:place(mesh,67)
	await frames(5)
	expect_focus(await read_focus("opaque-again"),67,"return from transparent viewport snaps to current depth")
	set_reference(false);await frames(3)
	var disabled := await read_focus("scaled-disabled")
	check(not disabled.allocated and disabled.previous_valid==0,"scaled lens targets release on disable")
	var file := FileAccess.open("user://focus.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"\t"));file.close()
	camera.compositor=null;probe.buffers=null;viewport.queue_free();await frames(2)
	print("FAR_DOF_SCALED %d checks %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)

func hdr_probe() -> void:
	setup()
	# A flat HDR field viewed with low exposure would become dark if the
	# adapted pre-tonemap composite saturated RGB to one like R1's LDR output.
	var material := boards[0].material_override as ShaderMaterial
	material.set_shader_parameter("stripes",false)
	# Mobile's existing packed scene buffer represents radiance only up to 2.
	# Keep its test inside that range; Forward+ exercises values above one in
	# the actual floating-point texture sampled by the new compositor.
	var mobile := RenderingServer.get_current_rendering_method()=="mobile"
	material.set_shader_parameter("a",Vector3(1.25,1.5,1.75) if mobile else Vector3(8,12,16))
	for child in viewport.get_children():
		if child is WorldEnvironment: child.environment.tonemap_exposure=.2 if mobile else .02
	attrs.dof_blur_amount=.012*SIZE.y/64.0
	set_reference(false);var before:=await picture("hdr-off")
	set_reference(true,true);var after:=await picture("hdr-on")
	var a:=before.get_pixel(1000,250);var b:=after.get_pixel(1000,250)
	print("HDR_COLOUR before=",a," after=",b)
	check(a.r>.3 and a.g>.4 and a.b>.5 and a.r<a.g and a.g<a.b and a.b<.99,"exposure reveals bright linear HDR input without display clipping")
	check(absf(a.r-b.r)<=1.0/255 and absf(a.g-b.g)<=1.0/255 and absf(a.b-b.b)<=1.0/255,"native composite preserves HDR brightness before tonemapping")
	check(difference(before,after,Rect2i(20,20,440,90)).changed==0,"HDR lens leaves Canvas UI exact")
	set_reference(false);await frames(3)
	check(not (await read_focus("hdr-disabled")).allocated,"HDR lens releases its targets")
	camera.compositor=null;probe.buffers=null;viewport.queue_free();await frames(2)
	print("FAR_DOF_HDR %d checks %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
