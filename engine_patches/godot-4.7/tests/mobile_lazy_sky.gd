extends Node
## Compare an opted-in background with the legacy radiance path while every
## supported Mobile consumer is enabled, disabled, and enabled again.
var checks:=0
var failures:=0
var rows:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:int)->void:
	for i in n:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
func fixture(optin:bool)->Dictionary:
	var view:=SubViewport.new();view.size=Vector2i(128,128);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.position=Vector3(0,0,3);camera.current=true
	var env:=Environment.new();env.background_mode=Environment.BG_SKY;env.ambient_light_color=Color(.1,.1,.1)
	env.sky=Sky.new();env.sky.radiance_size=Sky.RADIANCE_SIZE_256;env.sky.process_mode=Sky.PROCESS_MODE_REALTIME
	var mat:=ShaderMaterial.new();mat.shader=Shader.new();env.sky.sky_material=mat;camera.environment=env
	var sphere:=MeshInstance3D.new();sphere.mesh=SphereMesh.new();view.add_child(sphere)
	var metal:=StandardMaterial3D.new();metal.metallic=.7;metal.roughness=.2;sphere.material_override=metal
	return {"view":view,"env":env,"material":mat,"optin":optin}
func configure(f:Dictionary,consumer:String,colour:Vector3)->void:
	var env:Environment=f.env
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY if consumer=="ambient" else Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY if consumer=="reflection" else Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled=consumer=="aerial";env.fog_density=.2;env.fog_aerial_perspective=1.0 if consumer=="aerial" else 0.0
	var code:="shader_type sky;\n"
	if f.optin:code+="render_mode skip_unneeded_radiance;\n"
	code+="uniform vec3 hue;void sky(){COLOR=hue+vec3(TIME*0.0);"
	if consumer=="radiance":code+="if(!AT_CUBEMAP_PASS){COLOR=texture(RADIANCE,EYEDIR).rgb;}"
	code+="}"
	f.material.shader.code=code;f.material.set_shader_parameter("hue",colour)
func difference(a:Image,b:Image)->Dictionary:
	a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
	var aa:=a.get_data();var bb:=b.get_data();var peak:=0;var over:=0
	for i in aa.size():
		var d:=absi(aa[i]-bb[i]);peak=maxi(peak,d);over+=int(d>2)
	return {"peak":peak,"channels_over_2":over}
func _ready()->void:
	check(OS.has_feature("ei_mobile_lazy_sky_radiance"),"native capability present")
	if failures:get_tree().quit(1);return
	var reference:=fixture(false);var candidate:=fixture(true)
	var index:=0
	for consumer in ["none","ambient","none","reflection","none","aerial","none","radiance","none","reflection"]:
		var colour:=Vector3(.1+index*.035,.6-index*.025,.2+index*.02);index+=1
		configure(reference,consumer,colour);configure(candidate,consumer,colour)
		await frames(20)
		var a:Image=reference.view.get_texture().get_image();var b:Image=candidate.view.get_texture().get_image()
		var delta:=difference(a,b)
		check(delta.channels_over_2==0,"background and object preserve consumer "+consumer+" "+str(index))
		var row:={"consumer":consumer,"screen":delta}
		if consumer!="none":
			var ra:=RenderingServer.sky_bake_panorama(reference.env.sky.get_rid(),1.0,false,Vector2i(64,32))
			var rb:=RenderingServer.sky_bake_panorama(candidate.env.sky.get_rid(),1.0,false,Vector2i(64,32))
			check(ra!=null and rb!=null,"radiance available "+consumer)
			if ra and rb:
				var radiance_delta:=difference(ra,rb);row.radiance=radiance_delta
				check(radiance_delta.channels_over_2==0,"current radiance restored before consumer "+consumer)
		rows.append(row)
	# Share one opted-in Sky between a background-only and reflecting viewport.
	var other:=fixture(true);other.env.sky=candidate.env.sky
	other.env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	other.env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	configure(candidate,"none",Vector3(.4,.2,.6));configure(reference,"reflection",Vector3(.4,.2,.6))
	await frames(20)
	var shared:=difference(reference.view.get_texture().get_image(),other.view.get_texture().get_image())
	check(shared.channels_over_2==0,"a shared sky refreshes for its consuming viewport")
	rows.append({"shared_sky":shared})
	reference.view.free();candidate.view.free();other.view.free();TexUpscale.shutdown();UnitWounds.shutdown()
	FileAccess.open("user://mobile-lazy-sky.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("MOBILE_LAZY_SKY checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
