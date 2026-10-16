extends Node
## Exercise the real original-light shaders and the same light selection used
## by Game, comparing the native omission against their full light() path.
var checks:=0
var failures:=0
var rows:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(count:int)->void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
func delta(a:Image,b:Image)->Dictionary:
	var aa:=a.get_data();var bb:=b.get_data();var peak:=0;var over:=0
	for i in aa.size():
		var d:=absi(aa[i]-bb[i]);peak=maxi(peak,d);over+=int(d>2)
	return {"peak":peak,"channels_over_2":over}
func _ready()->void:
	check(Gfx.baked_pass_lights_supported(),"native Mobile capability")
	if failures:get_tree().quit(1);return
	GameData.options.merge(GfxPresets.values(1),true);Gfx.ensure_globals();Gfx.apply_surface_options()
	var view:=SubViewport.new();view.size=Vector2i(192,128);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var cam:=Camera3D.new();view.add_child(cam);cam.position=Vector3(0,0,4);cam.current=true
	var env:=Environment.new();Gfx.setup_original_env(env);env.background_mode=Environment.BG_COLOR;cam.environment=env
	var sun:=DirectionalLight3D.new();sun.light_specular=Gfx.SUN_MARK;view.add_child(sun)
	Gfx.set_light(Color(.2,.3,.25),Color(.5,.6,.55));Gfx.set_sun_direction(Vector3(0,0,1))
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color(.6,.4,.25))
	var texture:=ImageTexture.create_from_image(image)
	var retained:Array[ShaderMaterial]=[]
	for i in 2:
		var quad:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2(1.8,2.4);quad.mesh=mesh;view.add_child(quad);quad.position.x=-1.0+2.0*i
		var source:=EIFigure.OBJECT_SHADER
		if i==1:source=source.replace("shader_type spatial;","shader_type spatial;\n#define EI_TERRAIN_LIGHT")
		var material:=ShaderMaterial.new();material.shader=Gfx.make_shader(source,true,i==1);material.set_shader_parameter("albedo_tex",texture)
		quad.material_override=material;retained.append(material)
	var lights:Array[OmniLight3D]=[]
	for i in 6:
		var light:=OmniLight3D.new();view.add_child(light);light.add_to_group(Gfx.POINT_LIGHT_GROUP)
		light.position=Vector3(-3.0+i*1.25,.2,2.0);light.omni_range=4.0+i*.1;light.omni_attenuation=0
		light.light_color=Color(.2+i*.12,.9-i*.1,.2+i*.08);light.light_energy=.9
		if i%2==0:Gfx.mark_additive(light)
		lights.append(light)
	for state in ["start","focus-right","move","colour","hide","highlight","leaf","wet","restore","shadow","attenuation","projector","fade","negative","restore-special","free"]:
		var focus:=Vector3(4,0,0) if state!="start" else Vector3(-4,0,0)
		match state:
			"move":lights[2].position=Vector3(1,0,1)
			"colour":lights[1].light_color=Color(.8,.1,.3);lights[4].light_energy=.2
			"hide":lights[3].visible=false
			"highlight":GameData.options.gfx_materials=1
			"leaf":GameData.options.gfx_materials=0;GameData.options.gfx_foliage_light=1
			"wet":GameData.options.gfx_foliage_light=0;GameData.options.gfx_weather_surfaces=1
			"restore":GameData.options.gfx_weather_surfaces=0
			"shadow":lights[4].shadow_enabled=true
			"attenuation":lights[4].shadow_enabled=false;lights[4].omni_attenuation=1.0
			"projector":lights[4].omni_attenuation=0.0;lights[4].light_projector=texture
			"fade":lights[4].light_projector=null;lights[4].distance_fade_enabled=true
			"negative":lights[4].distance_fade_enabled=false;lights[4].light_negative=true
			"restore-special":lights[4].light_negative=false
			"free":lights[2].free()
		Gfx.apply_surface_options()
		Gfx.update_pass_lights(get_tree(),focus)
		check(Gfx._baked_pass_lights.is_empty(),"unknown sun restores native lights "+state)
		await frames(8)
		var before:=view.get_texture().get_image();before.convert(Image.FORMAT_RGBA8)
		Gfx.update_pass_lights(get_tree(),focus,sun)
		var expected:=0 if state in ["highlight","leaf","wet"] else 4
		if state in ["shadow","attenuation","projector","fade","negative"]:expected=3
		check(Gfx._baked_pass_lights.size()==expected,"selection/option ownership "+state)
		await frames(8)
		var after:=view.get_texture().get_image();after.convert(Image.FORMAT_RGBA8)
		var difference:=delta(before,after)
		check(difference.channels_over_2==0,"figure and terrain GPU lighting preserved "+state)
		rows.append({"state":state,"difference":difference,"flagged":Gfx._baked_pass_lights.size()})
		var ids:=Gfx._baked_pass_lights.keys();var pos:=Gfx._pass_positions.duplicate();var colours:=Gfx._pass_colours.duplicate()
		for i in 10:Gfx.update_pass_lights(get_tree(),focus,sun)
		check(ids==Gfx._baked_pass_lights.keys() and pos==Gfx._pass_positions and colours==Gfx._pass_colours,"unchanged frame retains cached selection and values "+state)
	Gfx.clear_baked_pass_lights();check(Gfx._baked_pass_lights.is_empty(),"teardown clears owned flags")
	view.free();TexUpscale.shutdown();UnitWounds.shutdown()
	FileAccess.open("user://baked-pass-lights.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("BAKED_PASS_LIGHTS checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
