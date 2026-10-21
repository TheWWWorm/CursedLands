extends "direct_aim_selection.gd"
## The wheel selects an aim; an existing auto-attack cannot consume that choice.
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":0,"pad_enabled":0,"pad_wheel_pause":0,"blood":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.get_node("UnitFog").set_process(false);hero=s.party_units(0)[0];hero.blocked=false;g.selected.assign([hero]);g.rig.release()
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	hero.restore_gait(2);hero._anim_lock=0
	var enemy:=body(hero.pos+Vector2(1.5,0),0,false)
	enemy.faction=1;hero.faction=0;s.world.set_relation(0,1,2);s.world.set_relation(1,0,2)
	enemy._perceive_next=INF;enemy.ai_next=INF;enemy.max_hp=5000;enemy.restore_parts()
	g.rig.set_process(false);g.direct.set_process(false);g.rig._window_focused=true
	g.rig.camera.global_position=hero.global_position+Vector3(0,5,8)
	g.rig.camera.look_at(enemy.global_position+Vector3.UP,Vector3.UP)
	await frames(3)
	var point:=Vector2.INF
	for rect:Rect2i in enemy.screen_rects(g.rig.camera).slice(1):
		var p:=Vector2(rect.position)+Vector2(rect.size)*0.5
		if g.pick_unit(p,hero)==enemy:point=p;break
	check(point!=Vector2.INF,"native mesh provides a live enemy pick")
	for fighting:bool in [false,true]:
		mode="auto-combat" if fighting else "idle"
		reset();g.cancel_touch_target()
		if fighting:
			hero.command({"type":"attack","target":enemy})
			for i in 25:
				hero.tick(GameUnit.TICK)
				if not hero._pending_hit.is_empty():break
			check(not hero._pending_hit.is_empty(),"ordinary attack reaches its active swing")
		var event:=InputEventMouseMotion.new();event.position=point;get_viewport().push_input(event,true);await frames(2)
		await press(KEY_ALT,true)
		var field:=g.direct.field()
		# Headless DisplayServer has no OS pointer position. Supply the already
		# verified native mesh pick captured when opening the wheel.
		field._ring_target={"unit":enemy}
		var hover:=InputEventMouseMotion.new();hover.position=field.wheel.get_global_transform_with_canvas()*field.wheel._cell_center(4)
		get_viewport().push_input(hover,true);await frames(2)
		await press(KEY_ALT,false)
		check(g.held_aim()==4,"selected leg remains armed over an enemy")
		check(g._forced_cursor(point)=="cursor_attack_ll","targeting cursor shows selected leg")
		for i in 90:hero.tick(GameUnit.TICK)
		check(g.held_aim()==4,"ongoing combat and impacts retain pending aim")
		g._click(point,false)
		check(hero.orders.size()==1 and hero.orders[0].get("aim")==4,"explicit target click sends aimed attack")
		check(g.touch_aim==-1,"explicit target click consumes pending choice")
	g.touch_aim=4
	var cancel:=InputEventMouseButton.new();cancel.button_index=MOUSE_BUTTON_RIGHT;cancel.pressed=true
	g._unhandled_input(cancel)
	check(g.touch_aim==-1,"right click cancels pending aim")
	FileAccess.open("user://classic_aim_selection.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"assertions":evidence.assertions},"\t"))
	print("CLASSIC_AIM ",checks," checks ",failures.size()," failures")
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
