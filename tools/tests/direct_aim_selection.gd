extends "third_person_kbm.gd"

func press(code: Key, down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
	Input.parse_input_event(event);await frames(2)

func choose_part(part: int) -> void:
	await press(KEY_ALT,true)
	var field:=g.direct.field()
	check(field.wheel.visible,"Alt opens the body-part selector")
	var point: Vector2=field.wheel.get_global_transform_with_canvas()*field.wheel._cell_center(part)
	var event:=InputEventMouseMotion.new();event.position=point
	Input.parse_input_event(event);await frames(2)
	await press(KEY_ALT,false)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"pad_wheel_pause":0,"blood":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="Alt aimed direct attacks";await s.enter_zone("gz1g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	hero.restore_gait(2);hero._anim_lock=0;hero.pos=Vector2(69.82051,128);hero._sync_transform(0);s.world.nav.track_unit(hero)
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	var enemy:=body(hero.pos+Vector2(1.5,0),0,false)
	enemy.faction=1;hero.faction=0;s.world.set_relation(0,1,2);s.world.set_relation(1,0,2)
	enemy._perceive_next=INF;enemy.ai_next=INF;enemy.visible=true;enemy.fogged=false;enemy.hidden=false
	g.rig._window_focused=true;get_tree().paused=false
	for camera_mode: int in [2,3]:
		GameData.options.control_mode=camera_mode;reset();g.cancel_touch_target()
		# Verify the selected impact part independently of the Attack/Defence roll.
		hero.stats.to_hit=1000
		hero.stats.dmg_min=20.0;hero.stats.dmg_max=20.0;enemy.max_hp=5000.0;enemy.restore_parts()
		enemy.stats.armor=PackedFloat32Array([0,0,0,0,0,0,0])
		var before:=enemy.parts.map(func(part: UnitBodyPart):return part.cur)
		g.direct.heading=0;g.direct.tilt=-0.1;g.direct._neutral=false;g.direct.apply_camera();await aim(enemy)
		check(g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==enemy,"crosshair identifies the live enemy in mode "+str(camera_mode))
		await choose_part(4)
		check(g.held_aim()==4,"Alt confirmation retains selected leg with an enemy in the crosshair in mode "+str(camera_mode))
		check(hero.orders.is_empty(),"Alt selection in direct mode does not issue a classic chase attack")
		g.direct._neutral=false;g.direct.attack()
		check(hero.orders.size()==1 and hero.orders[0].get("type")=="direct_attack" and hero.orders[0].get("aim")==4,"next direct attack carries the selected leg in mode "+str(camera_mode))
		if not hero.orders.is_empty():hero.facing=Vector2(hero.orders[0].direction.x,-hero.orders[0].direction.z).angle()
		for i in 50:
			hero.tick(GameUnit.TICK)
			if not hero._pending_hit.is_empty():break
		check(hero.strike_aim==4 and not hero._pending_hit.is_empty(),"committed hit retains leg selection")
		var arrow:=Projectile.launch_direct(s.world,hero,Vector3.RIGHT,true)
		arrow.set_physics_process(false)
		check(int(arrow.roll.get("aim",-1))==4,"projectile damage record retains selected leg")
		arrow.free()
		for i in 90:
			hero.tick(GameUnit.TICK)
			if hero._pending_hit.is_empty():break
		var changed:=[]
		for i in enemy.parts.size():
			if float(enemy.parts[i].cur)<float(before[i]):changed.append(i)
		check(changed==[4],"resolved melee impact damages only the selected leg in mode "+str(camera_mode))
	var report={"checks":checks,"failures":failures,"assertions":evidence.assertions}
	FileAccess.open("user://direct_aim_selection.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ALT_DIRECT_CHECKS ",checks," checks ",failures.size()," failures")
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
