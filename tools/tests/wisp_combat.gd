extends "wisp_visibility.gd"
## Native ambient volume, lifetime, lifecycle and combat attachments in all skins.

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"q_aa":0,"vsync":0}, true)
	Gfx.ensure_globals(); Engine.time_scale = 0; Engine.max_fps = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	view = SubViewport.new(); view.size = Vector2i(1280,720); view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var cam := Camera3D.new(); cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(cam); cam.current = true; cam.fov = 50
	var env := WorldEnvironment.new(); env.environment = Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.glow_enabled = false; view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-35,0); view.add_child(sun)
	RenderingServer.global_shader_parameter_set("ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set("ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("ei_fog",Vector3(180,260,0))
	Gfx.set_light(Color(.3,.3,.3),Color(.5,.5,.5))
	world = GameWorld.new(); view.add_child(world); world.process_mode = Node.PROCESS_MODE_DISABLED
	world.terrain = EITerrain.load_map("zone1"); world.add_child(world.terrain); world.terrain.set_process(false)
	var labels := []
	for proto: Dictionary in GameData.db.table("monster_prototypes"):
		if String(GameData.db.find("race_models",proto.base_race).get("mask","")) != "unmowi": continue
		var id := String(proto.name); labels.append(id)
		# Test both a preexisting registry (loading) and additions to an existing FX node.
		var fx: ParticleFx
		if labels.size()>1: fx = ParticleFx.of(world); fx.set_process(false)
		var u := unit(id); world.adopt_prepared_unit(u); configure(u.model)
		var point := u.global_position + Vector3.UP
		cam.position = point + Vector3(.8,.5,-.3).normalized()*5; cam.look_at(point)
		# Settle the new viewport/camera before driving hundreds of manual ticks.
		await frames()
		if fx==null: fx = ParticleFx.of(world); fx.set_process(false)
		fx._tick()
		check(fx.effects.size()==1 and fx.effects[0].e.type==0x204d,id+" automatically gains native ambient emitter")
		var ef := fx.effects[0]; var e := ef.e
		check(e.bone==0 and e.add==1 and e.texture=="stun" and is_equal_approx(e.s,.05),id+" native creator and atlas")
		check(e.parts.size()==1 and e.parts[0][3]==0.0 and int(e.parts[0][0x16])==0xffffff,id+" star starts transparent at zero size")
		fx._tick()
		check(e.parts[0][3]>0.0 and int(e.parts[0][0x16])==0xffffffff,id+" star becomes full-bright at first update")
		var first: Node3D = u.model.get_meta(EIFigureGeometry.PARTS)[0].get_ref()
		check(fx._bone(u,"bd")==first,id+" body prefix resolves first authored crystal")
		check(fx.bone_size(u,7)>0.0 and fx.bone_size(u,1)==0.0,id+" native blood geometry only for existing parts")
		var quadrants := {}; var positions := {}; var worst_radius := 0.0
		for i in 120:
			fx._tick()
			check(fx.effects.size()==1 and e.parts.size()<=22,id+" bounded steady emission "+str(i))
			var p: Array = e.parts.back(); var v := FxTypes.getp(p)-e.wp
			worst_radius = maxf(worst_radius,v.length()/fx.carrier_size(u).y)
			quadrants[Vector3i(int(v.x>0),int(v.y>0),int(v.z>0))] = true
			positions[FxTypes.getp(p)] = true
		check(worst_radius<=.80001 and worst_radius>.65,id+" fills original 0.8-radius sphere")
		check(quadrants.size()==8 and positions.size()>115,id+" fresh positions throughout all octants, no crystal clumps")
		fx._draw(1.0)
		fx.hide(); fx._draw(1.0)
		var bare := await capture(id+"-crystals-only")
		fx.show(); fx._draw(1.0)
		check(difference(bare,await capture(id+"-native-ambient")).bright>20,id+" ambient stars visible over grass without bloom")
		var star: Array = e.parts.back(); var old_star := FxTypes.getp(star)
		var old_centre := e.wp; u.position += Vector3(1,0,0); fx._tick()
		check(e.wp.distance_to(old_centre+Vector3(1,0,0))<.001,id+" new stars follow moving whole figure centre")
		check(FxTypes.getp(star)==old_star,id+" existing stars stay in world space")
		u.position -= Vector3(1,0,0); u.gait_run = true
		for i in 25: fx._tick()
		check(e.d0==4 and e.parts.size()<=28 and int(e.parts.back()[0x14])==5,id+" native running rate and lifetime")
		u.gait_run = false
		for i in 25: fx._tick()
		check(e.d0==1 and e.parts.size()<=22 and int(e.parts.back()[0x14])==20,id+" walking cadence restored")
		fx.finish_emitters(); fx._tick()
		check(not ef.deleted and bool(e.flags & FxEmitter.F_EMIT),id+" ambient survives battle settlement")
		u.fogged=true; u.visible=false; fx._draw(1.0)
		check(fx.drawn==0,id+" fog hides ambient particles")
		u.fogged=false; u.visible=true
		u.hide(); fx._draw(1.0); check(fx.drawn==0,id+" hidden unit hides stars"); u.show()
		if id=="WillowispM1":
			# Animate the actual native morph clip and native particle tick together.
			view.size=Vector2i(768,432)
			cam.position = point + Vector3(.8,.5,-.3).normalized()*3.4; cam.look_at(point)
			for i in 72:
				u.model.player.advance(ParticleFx.TICK); u.model.flush_pending_pose()
				configure(u.model,1.0,float(i)*ParticleFx.TICK)
				fx._tick(); fx._draw(1.0); await capture("ambient-%03d"%i)
			view.size=Vector2i(1280,720); configure(u.model)
			cam.position = point + Vector3(.8,.5,-.3).normalized()*5; cam.look_at(point)
		# Blood remains one native hit reaction. It does not impersonate ambient glow.
		fx.blood({"uid":u.uid,"part":1,"frac":0.4})
		check(fx.effects.filter(func(f): return f.e.type==0x2031).size()==1,id+" one native green body hit burst")
		for i in 65: fx._tick()
		check(fx.effects.size()==1,id+" hit burst expires while ambient persists")
		fx._draw(1.0); var idle := await capture(id+"-idle")
		fx.cast_fx({"uid":u.uid,"spell":"arrow","secs":0.66})
		for i in 7: fx._tick()
		fx._draw(1.0)
		check(difference(idle,await capture(id+"-casting")).bright>20,id+" original fire casting remains bright")
		var target := fx.unit_point(u,0)
		fx._missile("arrow",target,u,target,1.0,Spells.parse("arrow"))
		for i in 4: fx._tick()
		fx._draw(1.0)
		var impact := fx.effects.filter(func(f): return f.e.type==0x2041)
		check(impact.size()==1 and impact[0].e.wp.distance_to(fx.unit_point(u,7))<.001,id+" impact preserves native body attachment")
		await capture(id+"-combat")
		for i in 90: fx._tick()
		u.hide(); u.dead=true; fx._tick(); fx._draw(1.0)
		check(fx.drawn==0,id+" death cannot reveal a hidden ambient trail")
		check(ef.deleted and not bool(e.flags & FxEmitter.F_EMIT),id+" death stops ambient emission")
		for i in 24: fx._tick()
		check(fx.effects.is_empty(),id+" death drains and removes ambient particles")
		u.dead=false; u.show(); fx._tick()
		check(fx.effects.size()==1 and fx.effects[0].e.type==0x204d,id+" revived figure gets exactly one ambient emitter")
		world.erase_unit(u.uid); u.free()
		for i in 24: fx._tick()
		check(fx.effects.is_empty() and fx._creature_fx.is_empty(),id+" removal drains effect and releases registration")
		fx.free()
	FileAccess.open(out.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"family":labels,"renderer":RenderingServer.get_current_rendering_method()},"\t"))
	view.free(); TexUpscale.shutdown(); await frames(3)
	print("WISP_COMBAT checks=",checks," failures=",failures," family=",labels)
	get_tree().quit(1 if failures else 0)
