extends Node
## LiA 4aeac0/4b5fd0: an unarmed nonhuman without baserh3 uses the
## stored authored figure centre. This comparison deliberately does not invent
## a mouth socket that the inspected original branch never requests.
var checks:=0
var failures:=0
var cases:=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func array(v:Vector3)->Array:return [v.x,v.y,v.z]
func _ready()->void:
	var w:=GameWorld.new();w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	var fx:=ParticleFx.of(w);fx.set_process(false)
	var ids:=["zone32 DeadDeer","zone34 DeadDeer","zone35 DeadDeer"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="):
			GameData.campaign_roots[CampaignProfile.ASTRAL]=arg.trim_prefix("--astral-path=")
			check(ArenaExpansion.mount(),"namespaced Astral data mounted")
			ids=["arena-lia/deer1","arena-lia/deer2","arena-lia/deer3"]
	for id:String in ids:
		var u:=w.spawn_unit({"prototype":id,"player":1})
		check(is_instance_valid(u),id+" exists")
		if not is_instance_valid(u):continue
		check(int(u.race.type_id)==0x34 and int(u.proto.weapon_type_id)==16,id+" is a spell-only deer")
		check(fx._bone(u,"baserh3")==null,id+" has no legacy weapon socket")
		check(Array(u.proto.spells).any(func(s):return Spells.parse(s).code=="acid_ray"),id+" authored acid spell")
		u.model.set_process(false)
		u.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if id.begins_with("arena-lia/"):ArenaPveMatch._fit_figure(u)
		var clip:=u._cast_clip()
		for angle in [0.0,PI/2,PI]:
			for frame in [0,GameUnit._clip_hit_frame(u.model.template,clip)]:
				u.pos=Vector2(20,23);u.facing=angle;u.resync_drawn()
				u.model.player.play("ei/"+clip,0.0);u.model.player.seek(maxi(0,frame)/EIAnim.FPS,true);u.model.flush_pending_pose()
				var geometry:=fx._unit_geometry(u)
				var position:=ParticleFx.ei(u.global_position)
				var expected:Vector3=position+geometry.centre
				check(fx.cast_point(u).distance_to(expected)<0.0001,id+" native body fallback")
				var parts:=[]
				var inv:=u.model.global_transform.affine_inverse()
				var factor:=float(u.get_meta("arena_figure_scale",1.0))
				for ref:WeakRef in u.model.get_meta(EIFigureGeometry.PARTS,[]):
					var part:Node3D=ref.get_ref()
					var g:Dictionary=part.get_meta(EIFigureGeometry.META)
					parts.append({"position":array(ParticleFx.ei(inv*part.global_position)*factor),"centre":array(g.centre*factor),"min":array(g.min*factor),"max":array(g.max*factor)})
				cases.append({"id":id,"facing":angle,"frame":frame,"position":array(position),"parts":parts,"centre":array(geometry.centre),"actual":array(fx.cast_point(u))})
				w.position=Vector3(75,3,-40);w.set_meta("arena_local_fx",true)
				check(fx.cast_point(u).distance_to(expected)<0.0001,id+" board-local source")
				w.position=Vector3.ZERO;w.remove_meta("arena_local_fx")
		fx.spell_cast({"code":"acid_ray","spell":"acid_ray","a":u.uid,"x":u.pos.x+10,"y":u.pos.y})
		check(not fx.missiles.is_empty() and fx.missiles.back().pos.distance_to(fx.cast_point(u))<0.0001,id+" released acid ray starts at inspected fallback")
		w.erase_unit(u.uid);u.free()
	FileAccess.open("user://dead-deer-cast-source.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases}))
	w.free()
	print("DEAD_DEER_CAST_SOURCE ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
