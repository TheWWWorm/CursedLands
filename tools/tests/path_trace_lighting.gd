extends "res://tools/tests/water_raytrace_device.gd"
## Published runtime state, real HDR display output and original fire records.
const Controller = preload("res://src/game/fx/scene_raytrace.gd")
var observations := {}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out);Gfx.ensure_globals()
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"gfx_firelight":1,"pt_mode":2,"pt_accumulation":0},true)
	var env:=Environment.new();Gfx.setup_original_env(env)
	var game:=Game.new();game._env=env;game._sky_cave=true
	var owner:=Controller.new(game);add_child(owner);owner.set_process(false)
	Gfx.apply_env(env)
	check(env.tonemap_mode==Environment.TONE_MAPPER_LINEAR and env.tonemap_exposure==1,
		"requested PT retains original exposure until an output is active")
	owner._path_mode=false;owner._set_gi_active(true)
	check(not Gfx.path_trace_active and env.tonemap_mode==Environment.TONE_MAPPER_LINEAR,
		"scene RT GI retains the original display transform")
	owner._set_gi_active(false)
	var fallback:=OS.get_cmdline_user_args().has("--fallback-only")
	if not fallback:
		owner._path_mode=true;owner._set_gi_active(true)
		check(Gfx.path_trace_active and env.tonemap_mode==Environment.TONE_MAPPER_AGX,
			"active PT publishes its HDR display profile")
		await display_ramp(owner,env)
	owner._release()
	check(not Gfx.path_trace_active and not Gfx.scene_rt_gi_active and env.tonemap_mode==Environment.TONE_MAPPER_LINEAR and env.tonemap_exposure==1,
		"release or pipeline failure restores original display and exposure")
	var camera:=Camera3D.new();add_child(camera)
	var light:=OmniLight3D.new();light.omni_range=6;add_child(light)
	var fire:={"kind":"fire","light":light,"energy":1.0,"pos":Vector3.ZERO}
	LocalLighting.prepare_particle(fire)
	owner._path_mode=true;owner._center=Vector3.ZERO;owner._lights.assign([weakref(light)])
	var data: PackedByteArray=owner._frame(camera,Vector2i(64,36),1)
	var colour:=data.slice(116*4,119*4)
	check(absf(data.decode_float(119*4)-0.24)<0.00001 and light.light_size==0,
		"original brazier gets a flame-sized PT emitter without mutating Godot light_size")
	owner._path_mode=false;data=owner._frame(camera,Vector2i(64,36),1)
	check(absf(data.decode_float(119*4)-0.04)<0.00001 and colour==data.slice(116*4,119*4),
		"scene RT retains its source radius and identical light energy")
	owner._path_mode=true;owner._frame(camera,Vector2i(64,36),1)
	light.set_meta(LocalLighting.PATH_SOURCE_RADIUS,0.16)
	data=owner._frame(camera,Vector2i(64,36),1)
	check(data.decode_float(82*4)==0,"authored source-size changes invalidate previous shadows")
	LocalLighting.apply_particle(fire,false);data=owner._frame(camera,Vector2i(64,36),1)
	check(not light.has_meta(LocalLighting.PATH_SOURCE_RADIUS) and absf(data.decode_float(119*4)-0.04)<0.00001,
		"disabling enhanced fire restores the original PT source")
	check(light.position==fire.original_position and light.light_energy==fire.original.light_energy,
		"disabling enhanced fire restores its original position and energy")
	var spell:=fire.duplicate();spell.kind="spell";spell.erase("original")
	LocalLighting.prepare_particle(spell)
	check(not light.has_meta(LocalLighting.PATH_SOURCE_RADIUS),"spell lights do not inherit a flame radius")
	FileAccess.open(out.path_join("path-lighting.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	owner.queue_free();light.queue_free();camera.queue_free();await frames();game.free();finish()

func display_ramp(owner: Node,env: Environment) -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,128);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var world_env:=WorldEnvironment.new();world_env.environment=env;viewport.add_child(world_env)
	env.fog_enabled=false;env.background_mode=Environment.BG_COLOR;env.background_color=Color.BLACK
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2;camera.position.z=2;viewport.add_child(camera);camera.current=true
	var plane:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2(8,2);plane.mesh=mesh
	var shader:=Shader.new();shader.code="""shader_type spatial;
render_mode unshaded, fog_disabled;
void fragment() {
	float levels[8] = float[8](0.0,0.02,0.18,0.5,1.0,2.0,4.0,8.0);
	ALBEDO=vec3(levels[clamp(int(UV.x*8.0),0,7)]);
}
"""
	var material:=ShaderMaterial.new();material.shader=shader;plane.material_override=material;viewport.add_child(plane)
	var layer:=CanvasLayer.new();viewport.add_child(layer)
	var swatch:=ColorRect.new();swatch.size=Vector2(16,16);swatch.color=Color(0.5,0.3,0.2);layer.add_child(swatch)
	var samples:=[];var ui:=[]
	for active in [false,true]:
		owner._set_gi_active(active);await frames(12);await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image();var values:=[]
		for i in 8:values.append(image.get_pixel(i*64+32,64).r)
		samples.append(values);ui.append(image.get_pixel(8,8));image.save_png(out.path_join("hdr-ramp-"+str(active)+".png"))
	check(samples[0][4]>=0.99 and samples[0][7]>=0.99,"linear control clips HDR reference patches")
	var separated:=true
	for i in range(4,8):separated=separated and samples[1][i]>samples[1][i-1]+0.004
	check(separated and samples[1][7]<0.995,"PT display separates bright patches through eight times reference white")
	check(samples[1][2]>samples[0][2]*0.9 and samples[1][2]<samples[0][2]*1.1 and samples[1][0]<0.005,
		"middle grey stays within ten percent of its original brightness and black remains black")
	check(ui[0]==ui[1] and absf(ui[1].r-0.5)<0.005,"display mapping leaves Canvas UI colors unchanged")
	observations["hdr_ramp"]={"linear":samples[0],"path_display":samples[1],"ui_linear":str(ui[0]),"ui_path":str(ui[1])}
	viewport.queue_free();await frames()
