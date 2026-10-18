extends "../tests/particle_shader_options.gd"
## Alternating frozen fire/smoke A/B. Compare GPU cost and exact pixels with
## the transparent-atlas early discard removed, using the same running engine.
func _ready() -> void:
	await frames(24)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(320,320)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"gfx_hd_textures":0,"gfx_soft_particles":1,"gfx_bloom":0,"gfx_lit_particles":0,"gfx_firelight":0},true)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var view:=SubViewport.new();view.size=Vector2i(2560,1440);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var cam:=Camera3D.new();view.add_child(cam);cam.position=Vector3(0,2,6);cam.look_at(Vector3(0,1,0));cam.current=true
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(0.04,0.09,0.15);cam.environment=env
	var fx:=ParticleFx.new();view.add_child(fx);fx.set_process(false)
	for i in 24:
		var effect:=ParticleFx.Effect.new();effect.e=FxTypes.create(fx,[0x2001,0x2003,0x2004][i%3]);effect.e.rng.seed=6519+i
		effect.e.d0=12;effect.e.d8=200;effect.e.cc=100;effect.e.ofs=Vector3((i%6-2.5)*0.6,(i/6-1.5)*0.3,0.3);fx.effects.append(effect)
	for tick in 60:fx._tick()
	fx._draw(0.5)
	var materials:=fx._mats.values();var shaders:=[];var old:=[]
	for m:ShaderMaterial in materials:
		shaders.append(m.shader);var s:=Shader.new();s.code=m.shader.code.replace("\tif (t.a * COLOR.a <= 0.0) { discard; }\n", "");old.append(s)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	var reference:Image
	var results:=[]
	for repetition in 3:
		for optimized in ([false,true] if repetition%2==0 else [true,false]):
			for i in materials.size():materials[i].shader=shaders[i] if optimized else old[i]
			await frames(30)
			var samples:=[]
			for i in 90:
				await frames(1);samples.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			samples.sort()
			results.append({"optimized":optimized,"pass":repetition,"gpu_median_ms":samples[45],"gpu_p95_ms":samples[85]})
			var picture:=view.get_texture().get_image();picture.convert(Image.FORMAT_RGBA8)
			if reference==null:reference=picture
			else:check(difference(reference,picture).channels_over_1==0,"frozen fire/smoke pixels match")
			print("PARTICLE_GPU ",JSON.stringify(results.back()))
	FileAccess.open("user://particle-gpu.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":results,"particles":fx.drawn,"viewport":str(view.size),"checks":checks,"failures":failures,"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	reference.save_png("user://particle-gpu.png")
	get_tree().quit(int(failures>0))
