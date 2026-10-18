extends Node
## Rendered contrast/occlusion checks on original grass, with bloom disabled.
## Run on Forward+, Mobile and Compatibility. Captures go to --out=DIR.
var checks := 0
var failures := 0
var out := "user://wisp-visibility"
var view: SubViewport
var u: GameUnit

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 4) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func glow(on: bool) -> void:
	for mesh in u.model._wisp_glows: mesh.visible = on

func capture(name: String) -> Image:
	await frames()
	var image := view.get_texture().get_image()
	image.save_png(out.path_join(name+".png"))
	return image

func difference(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data()
	var changed := 0; var bright := 0; var energy := 0
	for i in range(0,aa.size(),4):
		var delta := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed += int(delta>2); bright += int(delta>40); energy += delta
	return {"changed":changed,"bright":bright,"energy":energy}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out=a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1),true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"q_aa":0,"gfx_hd_textures":0,"vsync":0},true)
	Gfx.ensure_globals(); Engine.time_scale=0; Engine.max_fps=120
	process_mode=Node.PROCESS_MODE_ALWAYS; RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	view=SubViewport.new(); view.size=Vector2i(1280,720); view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var cam:=Camera3D.new(); view.add_child(cam); cam.current=true; cam.fov=50
	var env:=WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.15,.25,.35)
	env.environment.glow_enabled=false;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);view.add_child(sun)
	RenderingServer.global_shader_parameter_set("ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set("ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("ei_fog",Vector3(180,260,0))
	var w:=GameWorld.new();view.add_child(w);w.process_mode=Node.PROCESS_MODE_DISABLED
	var terrain:=EITerrain.load_map("zone1");w.add_child(terrain);terrain.set_process(false);w.terrain=terrain
	var at:=Vector2(132,88)
	check(terrain.mark_ground(at.x,at.y)==0,"original grass site")
	u=GameUnit.new();check(u.setup(w,{"prototype":"WillowispM1","nid":1234}),"original wisp loads")
	w.add_child(u);u.pos=at;u.resync_drawn();u.model.set_process(false)
	u.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(u.model._wisp_glows.size()==5,"five authored motes retain individual coronas")
	check(u.model._morph_parts.size()==5,"native wisp vertex animation retained")
	var point:=u.global_position+Vector3.UP
	cam.position=point+Vector3(.8,.5,-.3).normalized()*16;cam.look_at(point)
	glow(false);var original_rects:=u.screen_rects(cam)
	glow(true)
	check(not original_rects.is_empty() and u.screen_rects(cam)==original_rects,"decorative glow does not enlarge selection geometry")
	for mesh in u.model._wisp_glows:
		check(u.model.apply_view_shadow_option(mesh,true) and mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"shadow settings cannot turn a corona into a solid caster")
	for phase in [0.0,0.3,0.7]:
		u.model.player.seek(phase,true);u.model.flush_pending_pose()
		for row: Array in u.model._morph_parts:
			var mesh: MeshInstance3D=row[0]
			var corona: MeshInstance3D=mesh.get_meta("ei_wisp_glow")
			var bounds:=EIUnitModel.preview_bounds(mesh)
			check(corona.position.distance_to(bounds.get_center())<0.001,"corona follows vertex-morphed mote")
	u.model.player.seek(0.0,true);u.model.flush_pending_pose()
	var rows:=[]
	for night in [false,true]:
		Gfx.set_light(Color(.04,.05,.08) if night else Color(.5,.5,.5),Color(.08,.1,.15) if night else Color(.75,.75,.75))
		for distance:float in [5.0,16.0,28.0]:
			cam.position=point+Vector3(.8,.5,-.3).normalized()*distance;cam.look_at(point)
			var label:="%s-%02d"%["night" if night else "day",int(distance)]
			glow(false);var before:=await capture(label+"-before")
			glow(true);var after:=await capture(label+"-after")
			var d:=difference(before,after);rows.append({"view":label,"difference":d})
			check(d.bright>20,"self-lit cores resolve without bloom: "+label)
			if distance==16.0 and not night:
				u.model.set_invisible(true);var invisible:=await capture("invisible")
				check(difference(before,invisible).energy<d.energy,"invisibility also dims the coronas")
				u.model.set_invisible(false)
	cam.position=point+Vector3(.8,.5,-.3).normalized()*16;cam.look_at(point)
	var block:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3.ONE*3.5;block.mesh=box
	view.add_child(block);block.global_position=point+(cam.position-point).normalized()*3
	glow(false);var covered_before:=await capture("occluded-before")
	glow(true);var covered_after:=await capture("occluded-after")
	check(difference(covered_before,covered_after).changed==0,"opaque geometry fully occludes glow")
	block.free();u.hide();glow(false);var hidden_before:=await capture("hidden-before")
	glow(true);var hidden_after:=await capture("hidden-after")
	check(difference(hidden_before,hidden_after).changed==0,"hidden unit has no glow leak")
	u.show();u.model.act("death",1,0.0)
	u.model.player.seek(u.model.player.current_animation_length,true);u.model.flush_pending_pose()
	check(u.model._wisp_glows.all(func(mesh):return not mesh.visible),"finished death leaves no floating coronas")
	u.model.act("idle",1,0.0);u.model.player.seek(0.0,true);u.model.flush_pending_pose()
	check(u.model._wisp_glows.all(func(mesh):return mesh.visible),"restored living pose restores coronas")
	# Preview uses its own lighting/fog; the same texture/motion still has glow.
	u.hide();var preview:=EIUnitModel.create({"prototype":"WillowispM1"},true);w.add_child(preview)
	preview.position=u.position;preview.set_process(false)
	preview.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	preview.player.seek(0.0,true);preview.flush_pending_pose()
	check(preview._wisp_glows.size()==5,"preview retains all five coronas")
	await capture("preview")
	FileAccess.open(out.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"rows":rows},"\t"))
	view.free();TexUpscale.shutdown();await frames(3)
	print("WISP_VISIBILITY checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
