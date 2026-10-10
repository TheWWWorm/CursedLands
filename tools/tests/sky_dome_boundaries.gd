extends "clouds.gd"
## The original six frusta form one continuous dome. Interior ring rays must hit.
const Candidate=preload("res://src/game/sky.gd")
const Reference=preload("fixtures/sky_dome_reference.gd")
const RR:=[39.891,39.109,37.605,34.610,30.084,24.531,17.961]
const ZZ:=[0.0,6.958,13.914,20.871,27.827,33.746,38.617]
func program(source:String,mask:=true) -> Shader:
	var code:=source.replace("shader_type sky;","shader_type canvas_item;").replace("render_mode use_debanding;","render_mode unshaded,blend_disabled;")
	code=code.replace("AT_CUBEMAP_PASS","false").replace("EYEDIR","probe_ray")
	code=code.replace("void sky() {","uniform sampler2D rays : filter_nearest,repeat_disable;\nvoid fragment() {\n vec3 probe_ray=texelFetch(rays,ivec2(FRAGCOORD.xy),0).rgb;float probe_band=0.0;")
	code=code.replace("hit = true;","hit = true;probe_band=float(i+1)/8.0;")
	var output:="COLOR=vec4(float(hit),probe_band,0.0,1.0);" if mask else "COLOR=vec4(col,1.0);"
	code=code.replace("COLOR = to_linear(col);",output).replace("COLOR = col;",output)
	var shader:=Shader.new();shader.code=code;return shader

func colour_controls(view:SubViewport,material:ShaderMaterial) -> void:
	var directions:Array[Vector3]=[]
	for ring in 6:
		var slope:float=((ZZ[ring]+ZZ[ring+1])*.5-16.0)/((RR[ring]+RR[ring+1])*.5)
		for azimuth in 128:
			var angle:=float(azimuth)*TAU/128.0+.0031
			directions.append(Vector3(cos(angle),slope,sin(angle)).normalized())
	var rays:=Image.create(view.size.x,view.size.y,false,Image.FORMAT_RGBF);rays.fill(Color(0,1,0))
	for i in directions.size():rays.set_pixel(i%view.size.x,i/view.size.x,Color(directions[i].x,directions[i].y,directions[i].z))
	material.set_shader_parameter("rays",ImageTexture.create_from_image(rays))
	material.set_shader_parameter("tex",GameData.get_texture("sky00"))
	for config:Dictionary in [{"name":"plain","fancy":0.0,"cave":false},{"name":"fancy","fancy":1.0,"cave":false},{"name":"cave","fancy":0.0,"cave":true}]:
		material.set_shader_parameter("fancy",config.fancy)
		material.set_shader_parameter("ambient",Vector3.ZERO if config.cave else Vector3(.5,.53,.49))
		material.set_shader_parameter("sun_col",Vector3.ZERO if config.cave else Vector3.ONE)
		var a:Image;var b:Image
		material.shader=program(Reference.SHADER,false);await frames(12);a=view.get_texture().get_image();a.convert(Image.FORMAT_RGBA8)
		material.shader=program(Candidate.SHADER,false);await frames(12);b=view.get_texture().get_image();b.convert(Image.FORMAT_RGBA8)
		var changed:=0
		for i in directions.size():changed+=int(a.get_pixel(i%view.size.x,i/view.size.x)!=b.get_pixel(i%view.size.x,i/view.size.x))
		check(changed==0,"unchanged authored colours away from joins: "+config.name)
		rows.append({"case":"colour","configuration":config.name,"rays":directions.size(),"changed_pixels":changed})

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;Engine.time_scale=0;Gfx.ensure_globals()
	var dirs:Array[Vector3]=[]
	for ring in range(1,6):
		var slope:float=(ZZ[ring]-16.0)/RR[ring]
		for azimuth in 128:
			var angle:=float(azimuth)*TAU/128.0
			for n in range(-8,9):
				dirs.append(Vector3(cos(angle),slope+n*0.00000001,sin(angle)).normalized())
	var expected_hits:=dirs.size()
	for v:Vector3 in [Vector3.UP,Vector3.DOWN,Vector3(1,-1,0).normalized(),Vector3(1,3,0).normalized()]:dirs.append(v)
	var size:=Vector2i(512,ceili(dirs.size()/512.0));var rays:=Image.create(size.x,size.y,false,Image.FORMAT_RGBF);rays.fill(Color(0,1,0))
	for i in dirs.size():rays.set_pixel(i%size.x,i/size.x,Color(dirs[i].x,dirs[i].y,dirs[i].z))
	var view:=SubViewport.new();view.size=size;view.disable_3d=true;view.use_hdr_2d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var material:=ShaderMaterial.new();material.shader=program(Reference.SHADER);material.set_shader_parameter("rays",ImageTexture.create_from_image(rays))
	var rect:=ColorRect.new();rect.size=Vector2(size);rect.material=material;view.add_child(rect)
	var outputs:Array[Image]=[]
	for candidate:bool in [false,true,false]:
		material.shader=program(Candidate.SHADER if candidate else Reference.SHADER);await frames(12);outputs.append(view.get_texture().get_image())
	var misses:Array=[];var new_misses:=0;var unexpected:=0
	for i in dirs.size():
		var old:=outputs[0].get_pixel(i%size.x,i/size.x);var current:=outputs[1].get_pixel(i%size.x,i/size.x)
		if i<expected_hits:
			if old.r<.5:misses.append({"index":i,"ring":i/(128*17)+1,"ray":str(dirs[i]),"new_band":current.g*8})
			new_misses+=int(current.r<.5)
		else:unexpected+=int(current.r>.5)
	check(not misses.is_empty(),"boundary fixture reproduces original holes")
	check(new_misses==0,"all interior dome-boundary rays hit repaired profile")
	check(unexpected==0,"rays outside the dome remain clear")
	check(outputs[0].get_data()==outputs[2].get_data(),"restored original boundary mask exact")
	await colour_controls(view,material)
	var result:={"rows":rows,"checks":checks,"failures":failures,"interior_rays":expected_hits,"outside_rays":dirs.size()-expected_hits,"original_misses":misses,"candidate_misses":new_misses,"candidate_unexpected":unexpected,"viewport":[size.x,size.y],"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()}
	check(Candidate.SHADER!=Reference.SHADER,"frozen reference differs from production")
	result.checks=checks;result.failures=failures
	FileAccess.open("user://sky-dome-boundaries.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("DOME_EDGES checks=",checks," failures=",failures," old_misses=",misses.size())
	view.free();TexUpscale.shutdown();await frames(8);get_tree().quit(int(failures>0))
