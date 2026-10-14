extends "third_person_kbm.gd"
## Loaded original assets; injected input and authority orders, no live route claim.
func press(code:Key,down:bool) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down
	Input.parse_input_event(e);await frames(1)
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"blood":0,"pad_wheel_pause":1},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz11k",1,false);await prepare()
	for u:GameUnit in s.world.unit_rows():
		if u!=hero:s.world.remove_unit(u)
	hero.set_process(false);hero.set_physics_process(false);hero._perceive_next=INF;hero.ai_next=INF
	for camera_mode:int in [2,3]:
		mode="Alt movement / camera %d"%camera_mode;GameData.options.control_mode=camera_mode
		reset();g.rig._window_focused=true;g.direct._process(.02);g.direct._neutral=false
		await press(KEY_W,true);g.direct._process(.02)
		check(g.direct._move_id==hero.uid and not hero.direct_steering.is_empty(),"W begins authoritative direct movement")
		var steering:=hero.direct_steering.duplicate(true)
		g.direct.field().open_keyboard_aim()
		check(not get_tree().paused,"aim wheel does not pause direct movement")
		check(hero.direct_steering==steering and g.direct._move_id==hero.uid,"opening Alt keeps held steering")
		g.direct._process(.02)
		check(g.direct.usable(true) and not g.direct.usable() and not g.direct._neutral,"wheel permits movement while retaining mouse ownership")
		g.cursor.set_kind("cursor_spellcancel");g._update_cursor()
		check(g.cursor.kind=="cursor_default","stale spell cursor resets before menu/aim selection")
		g.direct.field().finish_keyboard_aim();g.direct._process(.02)
		check(not hero.direct_steering.is_empty(),"releasing Alt keeps W movement")
		await press(KEY_W,false);g.direct._process(.02);check(hero.direct_steering.is_empty(),"releasing W stops movement")
	mode="dialogue visibility"
	var target:=body(hero.pos+Vector2(3,0),0,false)
	var snapshot:=target.snapshot();target.dialog_occluded=true
	target.apply_snapshot(snapshot,true)
	check(not target.visible and target.dialog_occluded,"authority snapshot cannot reveal the camera-hidden actor")
	var fog:=g.get_node("UnitFog") as UnitFog;fog._was_on=true;fog._t=0;fog._process(.1)
	check(not target.visible,"fog refresh cannot reveal the camera-hidden actor")
	target.hidden=true;target.dialog_occluded=false
	check(not target.visible,"dialogue end preserves script-hidden actors")
	target.hidden=false;target.fogged=false;target.dialog_occluded=true;target.dialog_occluded=false
	check(target.visible,"dialogue end restores an ordinary visible actor")
	mode="multitarget spell"
	reset();GameData.options.control_mode=1;g.direct._process(.02)
	var h:Dictionary=hero.get_meta("hero");h.spells=["lightning{t1}","arrow{t1}","fireball{t1}"]
	h.skills.elemental=100
	Combat.hero_stats(hero,h);hero.max_mana=10000
	var start:=hero.pos;var axis:=Vector2.RIGHT;var found:=false
	for ring in 35:
		for angle in 16:
			hero.pos=start+Vector2.from_angle(angle*TAU/16)*ring;s.world.nav.track_unit(hero)
			for direction in 8:
				axis=Vector2.from_angle(direction*TAU/8)
				if s.world.nav.direct_line(hero,hero.pos+axis*25):found=true;break
			if found:break
		if found:break
	start=hero.pos;check(found,"original navigation supplies a 25m spell approach lane")
	if found:
		for spell:String in h.spells:
			reset();hero.pos=start;hero.mana=10000;hero.facing=axis.angle();hero.action="idle"
			target.pos=start+axis*(float(Spells.parse(spell).range)+3);s.world.nav.track_unit(hero);s.world.nav.track_unit(target)
			g.pending_spell=spell;g.cast_on(target)
			if hero.orders.is_empty():print("CAST_DIAGNOSTIC ",g.pending_target(target)," known=",Spells.known_usable(hero,spell)," mana=",hero.mana," selected=",g.selected," allowed=",s.command_allowed({"t":"cast"})," direct=",g.direct.active())
			check(hero.orders.size()==1,"targeted far spell queues: "+spell)
			if hero.orders.is_empty():continue
			hero.order=hero.orders.pop_front();var mana:=hero.mana
			hero._do_cast(GameUnit.TICK)
			check(hero.mana==mana and not hero.order.is_empty(),"no premature self-cast or payment: "+spell)
			for i in 500:
				if hero.order.is_empty():break
				hero._do_cast(GameUnit.TICK)
			check(hero.mana<mana and hero.pos.distance_to(start)>2 and hero.pos.distance_to(target.pos)<=float(Spells.parse(spell).range)+.01,"approaches within range before casting: "+spell)
			var timers:=s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
			if timers:timers.pending.clear()
	reset();hero.mana=10000
	s.submit({"t":"cast","unit":hero.uid,"spell":"lightning{t1}","target":2147480000})
	check(hero.orders.is_empty(),"removed network target never falls back to caster position")
	s.submit({"t":"cast","unit":hero.uid,"spell":"lightning{t1}"})
	check(hero.orders.is_empty(),"targetless unit spell is rejected")
	hero.order={"type":"cast","spell":"lightning{t1}","target":target,"point":hero.pos};var mana:=hero.mana
	s.world.erase_unit(target.uid);hero._do_cast(GameUnit.TICK)
	check(hero.mana==mana and hero.order.is_empty(),"target removed during approach cancels before payment")
	Spells.cast_after(s.world,hero,"lightning{t1}",target,hero.pos,0)
	var saved_casts:=Spells.save_lasting(s.world)
	hero.order={"type":"cast","spell":"lightning{t1}","target":target,"point":hero.pos}
	target.free();var hp:=hero.hp;var timers:=s.world.get_node_or_null("SpellTimers") as Spells.WorldTimers
	hero._do_cast(GameUnit.TICK)
	check(hero.mana==mana and hero.order.is_empty(),"freed target during approach cannot become a point cast")
	for i in 5:s.world._logic_step+=1;s.world.time+=GameUnit.TICK;timers._tick(GameUnit.TICK,true)
	check(hero.hp==hp,"target removed during paid windup cannot redirect the effect to caster")
	Spells.restore_lasting(s.world,saved_casts)
	check(not saved_casts.is_empty() and timers.pending.is_empty(),"loading a paid cast with a missing unit target cannot restore a self-cast")
	print("GAMEPLAY_REPORT ",checks," checks ",failures.size()," failures ",failures)
	FileAccess.open("user://gameplay-report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"assertions":evidence.assertions},"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
