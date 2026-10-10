extends "clouds.gd"
## Compare the production integrator with its frozen pre-optimization program.
## Direct HDR samples avoid sky subpass filtering and preserve transmittance.
const Volume = preload("res://src/game/fx/cloud_volume.gd")
const Reference = preload("fixtures/cloud_volume_reference.gd")
const PROBE := """
uniform vec3 probe_origin;
uniform int probe_steps = 160;
uniform int probe_light_steps = 5;
uniform float probe_yaw = 0.0;
void fragment(){
 vec3 ray=normalize(vec3((UV.x-.5)*2.0,.014+UV.y*UV.y*2.0,1.0));
 ray.xz=mat2(vec2(cos(probe_yaw),sin(probe_yaw)),vec2(-sin(probe_yaw),cos(probe_yaw)))*ray.xz;
 COLOR=cv_march(probe_origin,ray,ei_sun_dir,vec3(.3),vec3(.9),probe_steps,probe_light_steps,.5);
}
"""

func program(common: String) -> Shader:
	var shader:=Shader.new()
	shader.code="shader_type canvas_item;\nrender_mode unshaded,blend_disabled;\nglobal uniform vec3 ei_sun_dir;\n"+Clouds.COMMON+common+PROBE
	return shader

func _ready() -> void:
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_clouds":3,"auto_graphics":0,"confine_mouse":0,"q_aa":0,"vsync":0,"fps_limit":0},true)
	Gfx.ensure_globals();Gfx.apply_surface_options();Engine.time_scale=0;Engine.max_fps=0;process_mode=Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Clouds.VolumeNoise.supported():
		check(false,"ray equivalence needs a supported volume renderer");get_tree().quit(1);return
	var view:=SubViewport.new();view.size=Vector2i(128,64);view.disable_3d=true;view.use_hdr_2d=true
	view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var material:=ShaderMaterial.new();var original:=program(Reference.COMMON);var candidate:=program(Volume.sky_source())
	material.shader=candidate
	var rect:=ColorRect.new();rect.size=Vector2(view.size);rect.material=material;view.add_child(rect)
	var cases:=[
		{"name":"gipat","allod":"Gipat","wet":0.0,"time":0.0},
		{"name":"ingos","allod":"Ingos","wet":0.0,"time":432.0},
		{"name":"suslanger","allod":"Suslanger","wet":0.0,"time":9999.0},
		{"name":"mixed","allod":"Ingos","wet":.52,"time":432.0},
		{"name":"storm","allod":"Gipat","wet":1.0,"time":432.0},
		{"name":"clearing","allod":"Ingos","wet":1.0,"time":432.0,"clear":60.0},
		{"name":"stratus","allod":"Gipat","wet":0.0,"time":97.0,"type":0.0},
		{"name":"nimbus","allod":"Gipat","wet":1.0,"time":97.0,"type":1.0},
		{"name":"type-below-half","allod":"Gipat","wet":0.0,"time":97.0,"type":.49999},
		{"name":"type-above-half","allod":"Gipat","wet":0.0,"time":97.0,"type":.50001},
		{"name":"negative-spread","allod":"Gipat","wet":1.0,"time":97.0,"spread":-.7},
	]
	check(Volume.COMMON==Reference.COMMON,"surface density and reflection program stays byte-identical")
	for quality:int in [1,2,3]:
		GameData.options.gfx_clouds=quality
		check(Clouds.sky_source(EISky.SHADER).contains("cv_ray_bounds()")==bool(quality==3),"bounds only enter High sky: "+str(quality))
		check(Clouds.sky_source(EISky.SHADER).contains("cv_density_cumulus(")==bool(quality==3),"fixed cumulus specialization only enters High sky: "+str(quality))
	GameData.options.gfx_clouds=3
	var seen_cloud:=false
	for config:Dictionary in cases:
		var field:=Clouds.new();var wind:=Vector4(.8,.6,.8,1)
		field.sample(0,"ray-bounds",config.allod,wind,config.wet,0,12,false)
		var frame:Dictionary=field.sample(config.time,"ray-bounds",config.allod,wind,config.wet,0,12,false).duplicate(true)
		if config.has("clear"):frame=field.sample(config.time+config.clear,"ray-bounds",config.allod,wind,0,0,12,false).duplicate(true)
		if config.has("type"):frame.volume.weather.z=config.type;frame.volume.weather.w=0.0
		if config.has("spread"):frame.volume.weather.w=config.spread
		Gfx.set_cloud_frame(view.get_instance_id(),frame)
		RenderingServer.global_shader_parameter_set(&"ei_sun_dir",SUN)
		for quality:int in [2,3]:
			material.set_shader_parameter("probe_steps",96 if quality==2 else 160)
			material.set_shader_parameter("probe_light_steps",3 if quality==2 else 5)
			for altitude:float in [-40.0,2469.0,2471.0,4919.0,5900.0]:
				material.set_shader_parameter("probe_origin",Vector3(-7200,altitude,12500))
				material.set_shader_parameter("probe_yaw",1.17 if quality==2 else -.63)
				material.shader=original;await frames(3);var a:=view.get_texture().get_image()
				material.shader=candidate;await frames(3);var b:=view.get_texture().get_image()
				var peak:=0.0;var changed:=0;var minimum_t:=1.0
				for y:int in a.get_height():
					for x:int in a.get_width():
						var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
						var delta:=maxf(maxf(absf(ca.r-cb.r),absf(ca.g-cb.g)),maxf(absf(ca.b-cb.b),absf(ca.a-cb.a)))
						peak=maxf(peak,delta);changed+=int(delta>0.0);minimum_t=minf(minimum_t,ca.a)
				seen_cloud=seen_cloud or minimum_t<.99
				check(peak==0.0,"exact HDR scatter and transmittance: %s q%d altitude %.1f"%[config.name,quality,altitude])
				rows.append({"weather":config.name,"quality":quality,"altitude":altitude,"pixels":view.size.x*view.size.y,"changed_pixels":changed,"peak":peak,"minimum_reference_transmittance":minimum_t,"format":a.get_format()})
	check(seen_cloud,"reference rays contain visible clouds")
	Gfx.clear_clouds();view.free();TexUpscale.shutdown();await frames(8)
	FileAccess.open("user://cloud-ray-bounds.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"scope":"Frozen 6957127 integrator versus production, HDR scattering and transmittance, including rays originating below/inside/above the cloud layer. No gameplay route or FPS claim."},"\t"))
	print("CLOUD_RAY_BOUNDS checks=",checks," failures=",failures);get_tree().quit(int(failures>0))
