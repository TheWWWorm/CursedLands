extends Node
## Rendered crystal silhouette, pulse and visibility checks on original grass.
## Run on Forward+, Mobile and Compatibility; --out=DIR retains captures.
var checks := 0
var failures := 0
var out := "user://wisp-visibility"
var view: SubViewport
var world: GameWorld
var serial := 1233

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(n := 4) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func configure(model: EIUnitModel, strength := 1.0, time := 0.0) -> void:
	for row: Array in model._morph_parts:
		var mesh: MeshInstance3D = row[0]
		for material: ShaderMaterial in [mesh.material_override, mesh.get_meta("unlit") if mesh.has_meta("unlit") else null]:
			if material:
				material.set_shader_parameter("wisp_strength", strength)
				material.set_shader_parameter("wisp_time", time)

func capture(name: String) -> Image:
	await frames()
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(out.path_join(name + ".png"))
	return image

func delta(a: PackedByteArray, b: PackedByteArray, i: int) -> int:
	return maxi(absi(a[i]-b[i]), maxi(absi(a[i+1]-b[i+1]), absi(a[i+2]-b[i+2])))

func difference(a: Image, b: Image, rect := Rect2i()) -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data()
	if rect.size == Vector2i.ZERO: rect = Rect2i(Vector2i.ZERO, a.get_size())
	rect = rect.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var changed := 0; var bright := 0; var energy := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var d := delta(aa, bb, (y*a.get_width()+x)*4)
			changed += int(d>2); bright += int(d>40); energy += d
	return {"changed":changed, "bright":bright, "energy":energy}

func outside_geometry(background: Image, solid: Image, enhanced: Image) -> int:
	var bg := background.get_data(); var mask := solid.get_data(); var lit := enhanced.get_data()
	var size := background.get_size()
	var escaped := 0
	for y in range(1, size.y-1):
		for x in range(1, size.x-1):
			if delta(bg, lit, (y*size.x+x)*4) <= 8: continue
			var covered := false
			# One raster edge pixel permits transparent/opaque pass rounding.
			for yy in range(y-1, y+2):
				for xx in range(x-1, x+2):
					if delta(bg, mask, (yy*size.x+xx)*4) > 20: covered = true
			if not covered: escaped += 1
	return escaped

func unit(id: String) -> GameUnit:
	serial += 1
	var u := GameUnit.new()
	check(u.setup(world, {"prototype":id, "nid":serial}), "loads " + id)
	world.add_child(u)
	u.pos = Vector2(132,88); u.resync_drawn()
	u.model.set_process(false)
	u.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	u.model.player.seek(0.0,true); u.model.flush_pending_pose()
	return u

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"q_aa":0,"gfx_hd_textures":0,"vsync":0}, true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	view = SubViewport.new(); view.size = Vector2i(1280,720); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var cam := Camera3D.new(); view.add_child(cam); cam.current = true; cam.fov = 50
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.15,.25,.35); env.environment.glow_enabled = false; view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	RenderingServer.global_shader_parameter_set("ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set("ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("ei_fog",Vector3(180,260,0))
	world = GameWorld.new(); view.add_child(world); world.process_mode = Node.PROCESS_MODE_DISABLED
	var terrain := EITerrain.load_map("zone1"); world.add_child(terrain)
	terrain.set_process(false); world.terrain = terrain
	check(terrain.mark_ground(132,88)==0, "original grass site")
	var u := unit("WillowispM1")
	var point := u.global_position + Vector3.UP
	cam.position = point+Vector3(.8,.5,-.3).normalized()*5; cam.look_at(point)
	var rows := []
	var families := []
	Gfx.set_light(Color(.5,.5,.5),Color(.75,.75,.75))
	u.hide()
	# Enumerate the rig, including every native level/skin and Trials form.
	for proto: Dictionary in GameData.db.table("monster_prototypes"):
		var race := GameData.db.find("race_models", proto.get("base_race",""))
		if String(race.get("mask","")).to_lower() != "unmowi": continue
		var id := String(proto.name)
		var member := unit(id); families.append(id)
		var meshes := member.model.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==5 and member.model._morph_parts.size()==5, id+" has only five original deforming crystals")
		check(meshes.all(func(mesh): return mesh.mesh is ArrayMesh), id+" has no circular billboard/shell")
		configure(member.model,1.0,0.0)
		var a := await capture(id+"-phase0")
		configure(member.model,1.0,1.4)
		var b := await capture(id+"-phase1")
		check(difference(a,b).bright>5, id+" visibly pulses on its original surfaces")
		member.hide()
	check(families.size()>=3, "native wisp family and all Trials forms covered")
	u.show()
	for night in [false,true]:
		Gfx.set_light(Color(.04,.05,.08) if night else Color(.5,.5,.5),Color(.08,.1,.15) if night else Color(.75,.75,.75))
		for distance: float in [5.0,16.0,28.0]:
			cam.position = point+Vector3(.8,.5,-.3).normalized()*distance; cam.look_at(point)
			var label := "%s-%02d"%["night" if night else "day",int(distance)]
			u.hide(); var background := await capture(label+"-background"); u.show()
			configure(u.model,0.0); var before := await capture(label+"-original")
			var original_rects := u.screen_rects(cam)
			configure(u.model); var after := await capture(label+"-crystals")
			check(u.screen_rects(cam)==original_rects, label+" retains original selection silhouette")
			var native := difference(background,before); var enhanced := difference(background,after)
			check(enhanced.energy > native.energy*1.3, label+" improves grass/darkness contrast without bloom")
			rows.append({"view":label, "original":native, "enhanced":enhanced})
	# Pixel support must remain on the actual faceted mesh, not a round aura.
	Gfx.set_light(Color(.5,.5,.5),Color(.75,.75,.75))
	cam.position = point+Vector3(.8,.5,-.3).normalized()*5; cam.look_at(point)
	u.hide(); var background := await capture("shape-background"); u.show()
	var materials := []
	var solid := StandardMaterial3D.new(); solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for row: Array in u.model._morph_parts:
		materials.append(row[0].material_override); row[0].material_override = solid
	var mask := await capture("shape-solid-native")
	for i in materials.size(): u.model._morph_parts[i][0].material_override = materials[i]
	var signals := []
	var rects := u.screen_rects(cam)
	for phase in [0.0,0.6,1.2,1.8,2.4,3.0]:
		configure(u.model,1.0,phase)
		var picture := await capture("pulse-"+str(phase))
		check(outside_geometry(background,mask,picture)==0, "pulse light stays within crystal geometry at "+str(phase))
		var energy := []
		for i in range(1,rects.size()): energy.append(difference(background,picture,rects[i]).energy)
		signals.append(energy)
	var peaks := {}
	for i in range(1,rects.size()):
		var samples := []
		for energy: Array in signals: samples.append(energy[i-1])
		check(samples.max()>samples.min()*1.15, "crystal "+str(i)+" has a visible individual pulse")
		peaks[samples.find(samples.max())] = true
	check(peaks.size()>=3, "crystals brighten at staggered times")
	configure(u.model)
	var visible := await capture("visible")
	var marks := OrderMarks.new()
	marks._lighten(u.model,true)
	u.model.set_invisible(true); var invisible := await capture("invisible-selected")
	check(difference(background,invisible).energy<difference(background,visible).energy*.8, "invisibility dims selected crystal surfaces too")
	u.model.set_invisible(false); marks._lighten(u.model,false); marks.free()
	check(difference(visible,await capture("visibility-restored")).changed==0, "selection/invisibility restore the same held pulse")
	var block := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3.ONE*3.5; block.mesh = box
	view.add_child(block); block.global_position = point+(cam.position-point).normalized()*2
	configure(u.model,0.0); var covered_before := await capture("occluded-original")
	configure(u.model); var covered_after := await capture("occluded-crystals")
	check(difference(covered_before,covered_after).changed==0, "walls fully occlude shining crystals")
	block.hide(); u.hide(); configure(u.model,0.0); var hidden_before := await capture("hidden-original")
	configure(u.model); var hidden_after := await capture("hidden-crystals")
	check(difference(hidden_before,hidden_after).changed==0, "hidden creatures cannot leak shine")
	u.show(); u.model.act("death",1,0.0)
	u.model.player.seek(u.model.player.current_animation_length,true); u.model.flush_pending_pose()
	var dead := await capture("death")
	configure(u.model,0.0)
	check(difference(dead,await capture("death-original")).changed==0, "finished death leaves only original fallen crystals without added shine")
	configure(u.model)
	u.model.act("idle",1,0.0); u.model.player.seek(0.0,true); u.model.flush_pending_pose()
	check(difference(visible,await capture("revived")).changed==0, "restored pose restores the crystal surfaces")
	# Exercise real shader TIME, not only the held capture phases.
	configure(u.model,1.0,-1.0); Engine.time_scale = 1.0
	var live_a := await capture("live-a")
	await get_tree().create_timer(0.7).timeout
	check(difference(live_a,await capture("live-b")).bright>5, "shader clock pulses without CPU material updates")
	Engine.time_scale = 0.0; configure(u.model)
	if not Portability.compatibility():
		env.environment.glow_enabled = true
		await frames(40) # Allow the transparent glow pipeline to compile.
		await capture("bloom-enabled")
		env.environment.glow_enabled = false
	u.hide()
	var preview := EIUnitModel.create({"prototype":"WillowispM1"},true); world.add_child(preview)
	preview.position = u.position; preview.set_process(false)
	preview.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	preview.player.seek(0.0,true); preview.flush_pending_pose(); configure(preview)
	check(preview.find_children("*","MeshInstance3D",true,false).size()==5, "preview retains five original crystals")
	var preview_before := await capture("preview-phase0")
	configure(preview,1.0,1.4)
	check(difference(preview_before,await capture("preview-phase1")).bright>5, "preview crystals pulse")
	EIUnitModel.refresh_preview_shaders(); configure(preview)
	check(difference(preview_before,await capture("preview-refreshed")).changed==0, "graphics refresh retains preview shine and texture")
	preview.hide(); u.show()
	# A short, close rendered sequence for review; the original pose is held
	# so each crystal's independent brightness is easy to judge.
	view.size = Vector2i(768,432)
	cam.position = point+Vector3(.8,.5,-.3).normalized()*2.8; cam.look_at(point)
	for i in 48:
		configure(u.model,1.0,float(i)/10.0)
		await capture("animation-%03d"%i)
	FileAccess.open(out.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),
		"family":families,"views":rows,"pulse_signals":signals},"\t"))
	view.free(); TexUpscale.shutdown(); await frames(3)
	print("WISP_VISIBILITY checks=",checks," failures=",failures," family=",families)
	get_tree().quit(1 if failures else 0)
