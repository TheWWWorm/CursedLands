extends "third_person_kbm.gd"
## Input through the real game and authority, including a committed attack.
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1g",1,false);mode="direct command priority";await prepare()
	for camera_mode: int in [2,3]:
		GameData.options.control_mode=camera_mode;reset();hero.direct_controlled=true;hero.restore_gait(2);hero._anim_lock=0;hero._update_pose();hero._anim_lock=0
		hero.facing=0;hero.mana=hero.max_mana
		var attack_command:={"t":"direct_attack","units":[hero.uid],"direction":Vector3.RIGHT}
		s.apply_command(attack_command,0)
		for i in 80:
			hero._tick(GameUnit.TICK)
			if not hero._pending_hit.is_empty():break
		check(not hero._pending_hit.is_empty(),"weapon attack is committed in mode "+str(camera_mode))
		var hit:=hero._pending_hit.duplicate(true);var recovery:=hero._anim_lock
		s.apply_command({"t":"direct_cast","unit":hero.uid,"spell":"healing{}","target":hero.uid},0)
		for i in 20:s.apply_command(attack_command,0)
		check(hero.orders.size()==2 and hero.orders[0].type=="cast" and hero.orders[1].type=="direct_attack","confirmed cast leads one bounded weapon repeat")
		check(hero._pending_hit==hit and hero._anim_lock==recovery,"buffering leaves the committed attack intact")
		var mana:=hero.mana
		for i in 150:
			s.apply_command(attack_command,0)
			hero._tick(GameUnit.TICK)
			if hero.action.begins_with("cast"):break
		check(hero.action.begins_with("cast") and hero.mana<mana,"spell executes despite continuous attack requests")
		check(hero.orders.size()<=1,"attack spam does not build an unbounded queue")
	reset();var corpse:=body(free_point(2.2));await aim(corpse)
	g.begin_cast(0);await key(KEY_E)
	check(g.pending_spell.is_empty() and hero.looting(corpse),"E cancels spell targeting and loots the aimed corpse")
	check(not hero.orders.any(func(o):return o.get("type")=="cast"),"interact never self-casts the selected spell")
	reset();corpse.pos=free_point(8.0);corpse._sync_transform(0)
	s.apply_command({"t":"loot","units":[hero.uid],"target":corpse.uid},0)
	check(hero.orders.size()==1 and not hero.orders[0].run,"single click approaches normally")
	s.apply_command({"t":"loot","units":[hero.uid],"target":corpse.uid,"run":true},0)
	check(hero.orders.size()==1 and hero.orders[0].run,"double click upgrades approach without duplicate pickup")
	hero.order=hero.orders.pop_front()
	s.apply_command({"t":"loot","units":[hero.uid],"target":corpse.uid,"run":true},0)
	check(hero.order.run and hero.orders.is_empty(),"double click also upgrades an already active approach")
	reset();hero.direct_controlled=false
	var enemy:=s.world.spawn_unit({"nid":990001,"prototype":"Human Hero","player":1,"position":Vector3(hero.pos.x+3,hero.pos.y,0)})
	enemy.set_process(false);enemy.set_physics_process(false);enemy.controller=-1;enemy.faction=1;enemy.ai_next=INF;enemy._perceive_next=INF
	s.world.set_relation(hero.faction,enemy.faction,2)
	for aimed in [-1,0,1,2,3,4,5]:
		reset();hero.direct_controlled=false;hero.ai_next=0;hero.set_meta("noticed",{enemy.get_instance_id():enemy});hero.set_meta("perceived",s.world.time)
		g.touch_aim=aimed;g.forced_on("aim" if aimed>=0 else "attack",null,enemy.pos)
		check(hero.orders.size()==1 and hero.orders[0].get("aim")==aimed,"ground attack-move carries selected aim "+str(aimed))
		hero.order=hero.orders.pop_front();s.world.ai.swarm_tick(hero)
		var attack:=hero.orders[0] if not hero.orders.is_empty() else hero.order
		check(attack.get("type")=="attack" and attack.get("aim")==aimed,"automatic engagement retains aim "+str(aimed))
	g.touch_aim=-1
	GameData.options.control_mode=1;g.direct.pointer=true;g.rig._window_focused=true
	var wheel:=g.direct.field().wheel
	for point:Vector2 in [wheel.size*0.5,Vector2(4,4),wheel.size-Vector2(4,4)]:
		wheel.open(PadField.aim_entries(),-1,0.5,{"id":["aim",-1]},point)
		var geom:=wheel._geom();var c:Vector2=geom[0];var outer:float=geom[1]+geom[2]*1.35
		check(c.x>=outer and c.x+outer<=wheel.size.x and c.y>=outer and c.y+outer<=wheel.size.y,"cursor wheel stays on screen")
		if point==wheel.size*0.5:check(c==point,"wheel opens exactly at cursor when there is room")
		wheel.hover(wheel._cell_center(3));check(wheel.selected==3,"shifted wheel retains pointer hit testing")
	wheel.close()
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("DIRECT_COMMAND_PRIORITY ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
