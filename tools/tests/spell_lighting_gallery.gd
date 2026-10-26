extends "path_trace_performance.gd"
## Visual audit of all installed casting, impact and status presentations.
## Use real actors, terrain and dispatchers; labels live in the evidence index.
func run() -> void:
	var context:=await setup();var session:Session=context[0];var game:Game=context[1]
	var traced:=OS.get_cmdline_user_args().has("--spell-pt")
	session._enter_zone("gz14k",1,false);t=session.world.terrain
	session.set_physics_process(false);session.world.set_process(false);session.world.set_physics_process(false);session.world.vm.instances.clear()
	game.set_process(false);game.rig.set_process(false);game.direct.set_process(false)
	for u:GameUnit in session.world.units.values():u.hide();u.set_process(false);u.set_physics_process(false)
	GameData.options.merge({"pt_mode":1 if traced else 0,"rt_shadows":0,"rt_gi":0,"gfx_firelight":1,"gfx_torch_glow":1,"character_light":0,"gfx_materials":1,"gfx_terrain":1,"gfx_water_reflections":0},true)
	Gfx.sun=Color.BLACK;Gfx.ambient=Color(0.08,0.08,0.08);game._sun.light_energy=0
	t.apply_gfx();Gfx.apply_env(game._env)
	var center:=Vector2(179.9853,43.2999)
	var a:=session.world.spawn_unit({"prototype":"Human Hero","position":Vector3(center.x+2,center.y,0)})
	var b:=session.world.spawn_unit({"prototype":"Human Hero","position":Vector3(center.x-1,center.y,0)})
	for u in [a,b]:u.set_process(false);u.set_physics_process(false)
	var target:=a.global_position.lerp(b.global_position,0.5)+Vector3.UP
	camera.global_position=target+Vector3(4,2.5,6);camera.look_at(target);camera.current=true;camera.fov=55
	await frames(30);GameData._window_gen+=1;get_window().min_size=Vector2i.ONE;get_window().borderless=true;get_window().size=Vector2i(1280,720);Engine.max_fps=30
	var rt:Node=game.get_node("SceneRaytrace")
	if traced:
		check(await ready_snapshot(rt),"all-spell gallery prepares actual PT")
		if not rt.stats.get("active",false):get_tree().quit(1);return
	var old_fx:=ParticleFx.of(session.world);old_fx.free()
	var entries:=[]
	for row:Dictionary in GameData.db.table("spell_prototypes"):
		var code:=String(row.code);var fx:=ParticleFx.of(session.world);fx.set_process(false)
		fx.cast_fx({"uid":a.uid,"spell":code,"secs":1.0})
		for i in 8:fx._tick()
		fx._draw(1);await frames(3);await shot(code+"-cast")
		if traced:
			check(rt._lights.any(func(w:WeakRef):return is_instance_valid(w.get_ref()) and w.get_ref().is_in_group("ei_spell_glow")),"PT discovers actual casting light "+code)
		fx.free();fx=ParticleFx.of(session.world);fx.set_process(false)
		var ev:={"spell":code,"a":a.uid,"tu":b.uid,"x":b.pos.x,"y":b.pos.y}
		fx.spell_cast(ev);fx.magic_fx({"uid":b.uid,"code":code,"secs":2.0,"s":1.0})
		var native:=SpellFx.spawn_event(session.world,ev)
		if native:native.set_process(false)
		var age:=3 if code in ["lightning","curse_magic","inv_lit","arrow","acid_ray","rick_magic","fireball"] else 12
		for i in age:fx._tick()
		if native:native.advance(age)
		fx._draw(1);await frames(3);await shot(code+"-effect")
		check(FileAccess.file_exists(out.path_join(code+"-cast.png")) and FileAccess.file_exists(out.path_join(code+"-effect.png")),"captured real cast and effect "+code)
		entries.append({"path_tracing":traced,"code":code,"name":row.name,"age":age,"cast":code+"-cast.png","effect":code+"-effect.png"})
		if native:native.free()
		fx.free();b.remove_meta("fx_magic")
	FileAccess.open(out.path_join("spell-gallery.json"),FileAccess.WRITE).store_string(JSON.stringify(entries,"\t"))
	game.queue_free();session.queue_free();await frames(12);TexUpscale.shutdown()
	print("SPELL_LIGHT_GALLERY ",checks," checks ",failures.size()," failures");get_tree().quit(1 if not failures.is_empty() else 0)
