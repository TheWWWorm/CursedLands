extends Node
## Real authored rigs at release time: sources follow animation, facing and
## board placement; spell targets, replay timing and direct aim stay separate.
var checks := 0
var failures := 0
var w: GameWorld
var fx: ParticleFx
var serial := 600000

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func unit(id: String) -> GameUnit:
	serial += 1
	var u := GameUnit.new()
	check(u.setup(w, {"prototype":id, "nid":serial, "player":1}), "loads " + id)
	w.add_child(u); w.set_unit(u.uid, u)
	u.pos = Vector2(20,20); u.facing = PI/2; u.resync_drawn()
	u.model.set_process(false)
	u.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return u

func pose(u: GameUnit, physical := false) -> void:
	var clip := u.model.action_clip("attack") if physical else u._cast_clip()
	u.model.player.play("ei/"+clip, 0.0)
	var hit := GameUnit._clip_hit_frame(u.model.template,clip)
	u.model.player.seek(float(maxi(hit,1))/EIAnim.FPS, true)
	u.model.flush_pending_pose()

func equip(u: GameUnit, kind: String) -> void:
	for row: Dictionary in GameData.db.table("weapons"):
		if String(row.type).to_lower()!=kind: continue
		for material: Dictionary in GameData.db.table("materials"):
			if String(material.type).to_lower()!=String(row.material_type).to_lower(): continue
			u.set_equipment(PackedStringArray(),PackedStringArray([String(row.name)+"."+String(material.name)]))
			u.model.set_process(false)
			check(u.model.weapon_type==kind,"loads authored "+kind)
			return
	check(false,"available "+kind+" fixture")

func _ready() -> void:
	w = GameWorld.new(); w.process_mode = Node.PROCESS_MODE_DISABLED; add_child(w)
	fx = ParticleFx.of(w); fx.set_process(false)
	for id: String in ["DragonBrownM16","DragonGreenM12","DragonBlueM14","ToadM1",
		"BatDarkM12","EvileyeGreenM13","EvileyeRedM12","BansheeDarkM12Canyon",
		"OctopusHadaganM13","ShadowM13","SuccubGreyM13Canyon","UnicornBlackM15",
		"Rick","DriadGreenM7","DriadDarkM9","AncientCurseM25","WillowispM1","Human Hero"]:
		var u := unit(id); pose(u)
		var start := ParticleFx.godot(fx.cast_point(u))
		check(start.is_finite(), id + " finite launch point")
		var local := u.to_local(start)
		var incoming := fx.unit_point(u,0)
		u.facing += PI; u.resync_drawn()
		check(ParticleFx.godot(fx.cast_point(u)).distance_to(u.to_global(local)) < 0.001, id + " source follows facing")
		u.pos += Vector2(7,-9); u.resync_drawn()
		check(ParticleFx.godot(fx.cast_point(u)).distance_to(u.to_global(local)) < 0.001, id + " source follows movement")
		w.set_meta("arena_local_fx", true); w.position = Vector3(75,3,-40)
		check((ParticleFx.godot(fx.cast_point(u))+w.global_position).distance_to(u.to_global(local)) < 0.001, id + " offset arena board uses local coordinates")
		w.position = Vector3.ZERO; w.remove_meta("arena_local_fx")
		u.pos = Vector2(20,20); u.facing = PI/2; u.resync_drawn()
		check(fx.unit_point(u,0).distance_to(incoming)<0.001, id + " target point unchanged by source query")
		var s := fx.cast_point(u)
		u.model.player.seek(0.0,true); u.model.flush_pending_pose()
		check(fx.cast_point(u).distance_to(s)>0.005, id + " source follows animated casting part")
		pose(u)
		if id == "DragonBrownM16":
			var head := fx._bone(u,"hd")
			var head_source := head.to_local(ParticleFx.godot(fx.cast_point(u)))
			var g: Dictionary = head.get_meta(EIFigureGeometry.META)
			check(absf(ParticleFx.ei(head_source).z - (g.centre.z+g.max.z))<0.001,"dragon starts at front of snout")
			check(fx.cast_point(u).distance_to(fx.unit_point(u,0))>3.0,"dragon fire no longer starts inside torso")
			var event := {"t":"spellfx","a":u.uid,"code":"fireball","spell":"fireball", "x":u.pos.x,"y":u.pos.y+20}
			fx.spell_cast(event)
			check(fx._pending_fireballs.back().pos.distance_to(fx.cast_point(u))<0.001,"live fireball uses animated snout")
			var session := Session.new(); session.world = w; w.session = session
			session._track(event)
			var saved: Dictionary = session._replay_state().spells.back()[0]
			var from: Array = saved.flight_from
			check(Vector3(from[0],from[1],from[2]).distance_to(fx.cast_point(u))<0.001,"save/late join captures exact launch position")
			check(saved.fx==u.pos.x and saved.fy==u.pos.y,"fireball retains authoritative flight duration origin")
			u.pos += Vector2(12,0); u.resync_drawn()
			fx.spell_cast(saved)
			check(fx._pending_fireballs.back().pos.distance_to(Vector3(from[0],from[1],from[2]))<0.001,"replayed fireball does not restart at moved caster")
			w.session = null; session.free()
		elif id == "BatDarkM12":
			fx.spell_cast({"code":"lightning","spell":"lightning","a":u.uid,"x":u.pos.x+6,"y":u.pos.y})
			var bolt = fx.bolts.back()
			u.facing += 0.7; u.resync_drawn(); bolt.update_tick()
			check(bolt.a.distance_to(fx.cast_point(u))<0.001,"continuous lightning follows its casting part")
		elif id == "UnicornBlackM15":
			var head := fx._bone(u,"hd")
			var g: Dictionary = head.get_meta(EIFigureGeometry.META)
			var at := ParticleFx.ei(head.to_local(ParticleFx.godot(fx.cast_point(u))))
			check(absf(at.z-g.centre.z-g.max.z)<0.001 and absf(at.y-g.centre.y-g.min.y)<0.001,"unicorn uses tip of forward horn")
		elif id.begins_with("Driad"):
			check(fx.cast_point(u).distance_to(fx.ranged_point(u))<0.001,"woodsfolk spell and dart share the animated blowpipe muzzle")
		elif id == "AncientCurseM25":
			ArenaPveMatch._fit_figure(u)
			var finger := fx._bone(u,"rh4")
			var geometry := u.model.animated_part_geometry(finger)
			var tip: Vector3 = geometry.centre + Vector3(geometry.min.x,0,0)
			var expected := ParticleFx.ei(finger.to_global(ParticleFx.godot(tip)))
			check(fx.cast_point(u).distance_to(expected)<0.001,"scaled Horror casts from its animated fingertips")
			check(fx.cast_point(u).distance_to(fx.unit_point(u,0))>0.5,"Horror lightning source remains outside the torso")
			fx.spell_cast({"code":"curse_magic","spell":"curse_magic","a":u.uid,"x":u.pos.x+6,"y":u.pos.y})
			var bolt = fx.bolts.back()
			check(bolt.a.distance_to(expected)<0.001,"live curse lightning begins at the visible fingertips")
			u.model.player.seek(12.0/EIAnim.FPS,true); u.model.flush_pending_pose(); bolt.update_tick()
			check(bolt.a.distance_to(fx.cast_point(u))<0.001,"curse lightning follows the animated fingers through its lifetime")
		fx._point_cache_active=true
		check(fx.cast_point(u)==fx.cast_point(u) and fx._point_cache[u.get_instance_id()].has("cast"),"overview reuses source sample separately from targets")
		fx._point_cache_active=false;fx._point_cache.clear()
		w.erase_unit(u.uid); u.free()
	for id: String in ["DriadDarkA7","GoblinA1","CyclopsA16","Human Mercenary Thief","OrcFemaleA3"]:
		var u := unit(id)
		if id=="Human Mercenary Thief": equip(u,"bow")
		elif id=="OrcFemaleA3": equip(u,"crossbow")
		pose(u,true)
		var source := ParticleFx.godot(fx.ranged_point(u))
		var arrow := Projectile.launch(w,u,u,false)
		check(arrow.global_position.distance_to(source)<0.001,id+" physical projectile starts at weapon/hand")
		check(arrow.global_position.distance_to(u.global_position+Vector3.UP*1.3)>0.1,id+" no fixed waist-height launch")
		if id=="DriadDarkA7":
			var tube := fx._bone(u,"rh3_tube00")
			var g: Dictionary = tube.get_meta(EIFigureGeometry.META)
			var at := ParticleFx.ei(tube.to_local(source))
			check(absf(at.y-g.centre.y-g.max.y)<0.001,"blowpipe uses open muzzle rather than mouthpiece")
		arrow.free()
		var direct := Projectile.launch_direct(w,u,Vector3.FORWARD,false,Vector3(9,7,3))
		check(direct.global_position==Vector3(9,7,3),id+" direct aim keeps explicit origin")
		direct.free(); w.erase_unit(u.uid); u.free()
	var low := Vector3(10,10,0.25)
	for code in ["arrow","acid_ray","rick_magic"]:
		fx._missile(code,low,null,low+Vector3(8,0,0),1.0,{"proto":{"light_radius":0.0}})
		var missile: Dictionary = fx.missiles.back(); fx._missile_tick(missile)
		check(absf(missile.pos.z-low.z)<0.001,code+" low launch does not jump to one metre")
	fx._fireball(low,Vector3(18,10,0),1.0,Spells.parse("fireball"),0,low)
	var ball: Dictionary = fx._pending_fireballs.back()
	var next := fx._fireball_step(ball.pos,ball.to,ball.speed,ball.clearance)
	check(next.z>0.25 and next.z<0.5,"low fireball climbs smoothly toward its target")
	var missing := GameUnit.new(); w.add_child(missing); missing.world=w
	check(fx.cast_point(missing).is_finite() and fx.ranged_point(missing).is_finite(),"missing/custom rig retains safe fallback")
	missing.free(); w.queue_free(); await get_tree().process_frame
	print("CREATURE_PROJECTILE_ORIGINS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
