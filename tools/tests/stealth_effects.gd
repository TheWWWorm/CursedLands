extends Node
## Native spells, real observers and rendered female/prone model effects.
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=4) -> void:
	for i in n:await get_tree().process_frame
func forget(w:GameWorld,u:GameUnit) -> void:
	# Each phase explicitly constructs a new observation scene while ordinary
	# world ticks are frozen. Update teleported occupancy and let the original
	# 8–11 tick candidate cache expire; prior alarms do not belong to this phase.
	for key in ["noticed","perceived","seen_corpses","suspect"]:u.remove_meta(key)
	w.nav.track_unit(u)
	w.time+=12.0*GameUnit.TICK
func has_target(w:GameWorld,by:GameUnit,target:GameUnit) -> bool:
	return w.ai.player_perceive(by,true).has(target.get_instance_id())
func gameplay(s:Session,nalo:GameUnit) -> void:
	s.state.world_time=12.0
	var w:=s.world;var by:GameUnit
	for u:GameUnit in w.unit_rows():
		if w.is_enemy(u,nalo) and u.proto.get("base_race","")=="Human Male" and u.sense(2)==0.0:by=u;break
	check(by!=null,"authored hostile human observer is present")
	if by==null:return
	nalo.buffs.clear();nalo.refresh_max_hp();nalo.action="idle";nalo.stance=GameUnit.STANCE_CRAWL
	var radius:=float(by.stats.sight)*by.sight_factor()*nalo.vis_factor()
	var found:=false
	for direction in 32:
		var at:=nalo.pos+Vector2.from_angle(float(direction)*TAU/32)*radius*.75
		if not w.nav.cell_open(at,by.move_class()):continue
		by.pos=at;by.facing=(nalo.pos-at).angle()
		if w.ai.can_notice(by,nalo,float(by.stats.sight)) and by.pos.distance_to(nalo.pos)>float(by.proto.peripheral_skills)*1.2:
			found=true;break
	check(found,"real map supplies unobstructed sight between normal and reduced detection ranges")
	forget(w,by);check(has_target(w,by,nalo),"unbuffed prone actor is acquired by real hostile perception")
	var spell:="invisibility{d2;d2}"
	Spells.apply(w,nalo,spell,nalo,nalo.pos)
	check(is_equal_approx(nalo.detect(0),.5),"native base spell halves sight detectability; duration runes do not raise power")
	forget(w,by);check(not has_target(w,by,nalo),"base invisibility prevents acquisition at the same real distance")
	forget(w,by);by.order={};by.orders.clear();by.ai_next=0
	w.ai.think(by)
	check(by.order.get("target")!=nalo and by.orders.all(func(o:Dictionary):return o.get("target")!=nalo),"full fresh guard decision does not attack unseen actor")
	var kernel:RefCounted=ClassDB.instantiate("PerceptionKernel")
	check(kernel.new_visible([nalo],GameUnit,by,w,w.ai,PackedFloat64Array(),{},{},float(by.stats.sight)).is_empty(),"native optimized perception also excludes the buffed target")
	nalo.buffs.clear();nalo.refresh_max_hp();forget(w,by)
	check(has_target(w,by,nalo),"removing invisibility restores acquisition")
	Spells.apply(w,nalo,spell,nalo,nalo.pos)
	w.time+=GameUnit.TICK
	check(has_target(w,by,nalo),"original NPC rule retains a previously noticed hostile after invisibility")
	# Scripted Aggression has the same hostile-retention rule.
	nalo.buffs.clear();nalo.refresh_max_hp();forget(w,by)
	by.set_meta("um",UnitAI.MOT_AGGRESSION)
	check(has_target(w,by,nalo),"scripted aggression acquires the unbuffed opponent")
	Spells.apply(w,nalo,spell,nalo,nalo.pos);w.time+=GameUnit.TICK
	check(has_target(w,by,nalo),"scripted aggression retains the already spotted invisible opponent")
	by.remove_meta("um")
	forget(w,by);Spells.apply(w,nalo,"invisibility{e2;e2;e2;e2;e2;e2;e2;e2}",nalo,nalo.pos)
	check(nalo.detect(0)==0.0 and not has_target(w,by,nalo),"power runes can suppress ordinary sight completely")
	by.pos=nalo.pos+Vector2(0.5,0);by.facing=PI
	check(w.ai.can_notice(by,nalo,float(by.stats.sight)),"original close peripheral detection remains possible")
	nalo.buffs.clear();nalo.refresh_max_hp();nalo.action="walk"
	by.pos=nalo.pos+Vector2(1,0);forget(w,by);w.ai._help.clear()
	w.ai.noise_event(nalo,nalo.noise()*nalo.detect(3))
	check(w.ai._help.any(func(e:Array):return e[0]==by),"ordinary footsteps generate delayed enemy suspicion")
	w.ai._help.clear();Spells.apply(w,nalo,"silence{d2;d2}",nalo,nalo.pos)
	w.ai.noise_event(nalo,nalo.noise()*nalo.detect(3))
	check(nalo.detect(3)==0.0 and w.ai._help.is_empty(),"Silent Step prevents movement noise from alerting nearby listeners")
	nalo.buffs.silence[GameUnit.EFFECT_TICKS]=1;nalo._tick_effects()
	w.ai.noise_event(nalo,nalo.noise()*nalo.detect(3))
	check(nalo.detect(3)==1.0 and w.ai._help.any(func(e:Array):return e[0]==by),"same listener hears footsteps again when the effect expires")
	print("STEALTH_GAMEPLAY ",JSON.stringify({"sight_range":radius,"spell_power":Spells.parse(spell).effect,"observer":by.proto.name,"prone":true}))
func capture(view:SubViewport,label:String) -> Image:
	await frames(10);await RenderingServer.frame_post_draw
	var im:=view.get_texture().get_image();im.save_png("user://stealth-"+label+".png");return im
func face(view:SubViewport,nalo:GameUnit,label:String) -> void:
	var cam:=view.get_camera_3d();var transform:=cam.global_transform
	var head:=nalo.model.find_child("hd",true,false) as Node3D
	var forward:=nalo.model.eye_position()-head.global_position;forward.y=0;forward=forward.normalized()
	if forward==Vector3.ZERO:forward=Vector3.RIGHT
	cam.global_position=head.global_position+forward*.9+Vector3.UP*.25;cam.look_at(head.global_position+Vector3.UP*.05)
	await capture(view,label);cam.global_transform=transform
func visuals(g:Game,nalo:GameUnit) -> void:
	var w:=g.world;var fx:=ParticleFx.of(w)
	g.rig.set_process(false);g.direct.set_process(false);g.get_node("UnitFog").set_process(false);g.marks.set_process(false)
	for u:GameUnit in w.unit_rows():u.visible=u==nalo
	for ef in fx.effects:fx.delete(ef)
	nalo.buffs.clear();nalo.refresh_max_hp();nalo.controller=1;nalo.hidden=false;nalo.fogged=false;nalo.visible=true
	nalo.stance=GameUnit.STANCE_CRAWL;nalo.model.pose_state=EIUnitModel.ST_LIE;nalo.model.act("idle",1,0);nalo.model.player.advance(0);nalo.model.set_process(false)
	nalo.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;nalo._sync_transform(0)
	var at:=nalo.global_position+Vector3(0,.35,0)
	var view:=SubViewport.new();view.size=Vector2i(960,540);view.world_3d=g.get_world_3d();view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var cam:=Camera3D.new();view.add_child(cam);cam.global_position=at+Vector3(2,1.5,1.5);cam.look_at(at);cam.fov=45;cam.current=true
	g.rig.camera.global_transform=cam.global_transform;g.rig.camera.fov=45
	await capture(view,"plain")
	await face(view,nalo,"face-plain")
	nalo.model.set_detailed_head(false);await capture(view,"original-head");nalo.model.set_detailed_head(true)
	Spells.apply(w,nalo,"invisibility",nalo,nalo.pos)
	await capture(view,"invisible")
	await face(view,nalo,"face-invisible")
	g.marks._lighten(nalo.model,true);g.marks._lighten(nalo.model,true)
	await capture(view,"selected-invisible");g.marks._lighten(nalo.model,false)
	nalo.buffs.strength={};nalo.refresh_figure();nalo.model.player.advance(0)
	check(nalo.model.get("_invisible")==true,"figure rebuild retains active invisibility")
	await capture(view,"rebuilt")
	nalo.buffs.clear();nalo.refresh_max_hp();nalo.model.player.advance(0);await capture(view,"restored")
	Spells.apply(w,nalo,"silence",nalo,nalo.pos)
	fx.magic_fx({"uid":nalo.uid,"code":"silence","secs":8.0,"s":ParticleFx.strength(Spells.parse("silence")),"replay":true})
	await get_tree().create_timer(.4).timeout
	await capture(view,"silent-step")
	var effect:ParticleFx.Effect=nalo.get_meta("fx_magic",{}).get("silence")
	check(effect!=null and effect.e.live()>0,"Silent Step renders its original lasting star emitter on a prone actor")
	if effect:
		print("SILENT_STEP_VISUAL ",JSON.stringify({"type":effect.e.type,"live":effect.e.live(),"point":str(effect.e.wp),"head":str(fx._bone(nalo,"hd").global_position),"parts":effect.e.parts,"visible":effect.mmi.multimesh.visible_instance_count,"box":str(effect.mmi.multimesh.custom_aabb),"screen":str(cam.unproject_position(ParticleFx.godot(effect.e.wp)))}))
		GameData.get_texture("stun").get_image().save_png("user://stealth-stun-atlas.png")
		cam.global_position=at+Vector3(4,3,3);cam.look_at(at+Vector3.UP*.7);g.rig.camera.global_transform=cam.global_transform
		await capture(view,"silent-step-wide")
	view.free()
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1,"gfx_detailed_heads":1},true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	s.state.create_party("Pretty");s.state.add_party_unit("Pretty","Nalo","Human Hadagan Pretty");s.state.set_current_party("Pretty")
	await s.enter_zone("gz15h",1,false);s.set_physics_process(false);s.world.vm.instances.clear();s.world.set_physics_process(false);s.world.set_process(false)
	for actor:GameUnit in s.world.unit_rows():actor.set_physics_process(false);actor.set_process(false)
	var hero:GameUnit=s.party_units(0)[0];var nalo:GameUnit
	for u:GameUnit in s.world.unit_rows():
		if String(u.info.get("name","")).to_lower().contains("nalo"):nalo=u;break
	check(nalo!=null,"native Nalo model is present")
	if not nalo:nalo=hero
	gameplay(s,nalo)
	check(Spells.title(Spells.effect_spell("invisible"))==GameData.text("spell invisibility").get_slice("\n",0),"effect panel uses original localized spell name")
	check(int(Spells.parse(Spells.effect_spell("invisible")).proto.texture_type)==15,"effect panel resolves original invisibility artwork")
	if DisplayServer.get_name()!="headless":await visuals(g,nalo)
	g.free();s.free();await frames(6);TexUpscale.shutdown()
	print("STEALTH_EFFECTS ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
