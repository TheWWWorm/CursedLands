extends "third_person_kbm.gd"
class ProbeSession extends Session:
	var acknowledgements: Array[int]=[]
	func broadcast(event: Dictionary) -> void:
		if event.get("t")=="ack": acknowledgements.append(int(event.code))
		super.broadcast(event)
func tick() -> void:
	s.world.time+=GameUnit.TICK; s.world._logic_step+=1; hero.tick(GameUnit.TICK)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0},true)
	s=ProbeSession.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1g",1,false);await prepare()
	for u: GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	hero.ai_next=INF;hero._perceive_next=INF
	for camera_mode in [1,2,3]:
		for route in ["portrait","self shortcut"]:
			mode="mode%d %s"%[camera_mode,route]
			GameData.options.control_mode=camera_mode
			reset();hero.stop_steering();hero.direct_controlled=camera_mode!=1
			hero.restore_gait(2);hero.alert=true;hero._pose_snap=true;hero._update_pose();hero._anim_lock=0
			hero.mana=0;hero.race=hero.race.duplicate(true);hero.race.mana_regen=.02
			hero.order={"type":"move","to":hero.pos+Vector2(3,0)}
			if camera_mode!=1:g.direct.step(Vector2.UP,.1)
			(s as ProbeSession).acknowledgements.clear()
			g.pending_spell="healing{}"
			if route=="portrait":check(g.cast_portrait(hero),"portrait accepts known affordable-capacity spell")
			elif camera_mode==1:s.apply_command({"t":"cast","unit":hero.uid,"target":hero.uid,"spell":"healing{}"},0)
			else:g.direct.cast_self()
			var stopped:=hero.pos
			for i in 8:tick()
			check(hero.order.get("type")=="cast" and hero.order.get("stamina_notified",false),"known spell remains queued while stamina recovers")
			check(hero.pos==stopped and hero.direct_steering.is_empty(),"self-cast stops the previous movement")
			check((s as ProbeSession).acknowledgements.count(EIAcks.CANT_CAST)==1,"one spoken stamina acknowledgement per order")
			if camera_mode!=1:
				g.direct.step(Vector2.UP,.1);tick()
				check(hero.pos==stopped and hero.order.get("type")=="cast","held key cannot cancel the waiting self-cast")
			var before:=hero.mana
			for i in 15:tick()
			check(hero.mana>before,"waiting spell permits normal idle stamina recovery")
			var recovery_ticks:=15*(ceili(g.spell_ui_cost(hero,Spells.parse("healing{}"))/(hero.max_mana*.02))+2)
			for i in recovery_ticks:
				tick()
				if hero.action.begins_with("cast"):break
			check(hero.action.begins_with("cast"),"spell commits automatically after stamina recovers")
			check((s as ProbeSession).acknowledgements.count(EIAcks.CANT_CAST)==1,"regeneration does not repeat voice acknowledgement")
		# Replacement movement must still cancel a wait, in both input styles.
		reset();hero.stop_steering();hero.mana=0;hero._anim_lock=0
		s.apply_command({"t":"direct_cast" if camera_mode!=1 else "cast","unit":hero.uid,"target":hero.uid,"spell":"healing{}"},0)
		tick()
		if camera_mode==1:hero.move_to(hero.pos+Vector2(1,0))
		else:s.apply_command({"t":"direct_move","units":[hero.uid],"direction":Vector2.RIGHT},0)
		check(hero.order.get("type")!="cast" and not hero.orders.any(func(o):return o.get("type")=="cast"),"new movement cancels stamina wait")
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("SPELL_STAMINA_WAIT ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
