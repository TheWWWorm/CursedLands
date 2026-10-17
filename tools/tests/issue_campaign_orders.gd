extends "third_person_kbm.gd"
## Paused authority commands and native source-data movement parity.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":0,
		"pad_enabled":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"show_path":1},true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1),true)
	s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	hero=s.party_units(0)[0];hero.blocked=false;g.selected.assign([hero]);g.rig.release()
	await frames(5);g.rig.set_process(false);g.direct.set_process(false)
	mode="issue 9"
	var speeds: Array=hero.race.speeds
	check(is_equal_approx(speeds[1],speeds[2]),"original human database gives identical walk and kneel speeds")
	check(absf(float(speeds[3])/float(speeds[1])-0.7816667)<0.0001,"original crawl base is 78.17% of walking")
	hero.running=false;hero.stance=GameUnit.STANCE_NONE;var walking:=hero.speed()
	hero.stance=GameUnit.STANCE_KNEEL;check(is_equal_approx(hero.speed(),walking),"native quantized crouch translation equals walking")
	hero.stance=GameUnit.STANCE_CRAWL;check(absf(hero.speed()/walking-0.8)<0.0001,"native packed crawl byte gives 80% of walking")
	hero.stance=GameUnit.STANCE_NONE
	mode="issue 12"
	var at:=free_point(6.0)
	var enemy:=body(at,900002,false);enemy.faction=1;hero.faction=0
	s.world.set_relation(0,1,2)
	s.world.set_relation(1,0,2)
	var fx:=ParticleFx.of(s.world)
	get_tree().paused=true
	var time:=s.world.time;var pos:=hero.pos;var mana:=hero.mana;var hp:=hero.hp;var ticks:=fx.tick
	for attack in [false,true]:
		reset()
		var before:=fx.effects.duplicate()
		var cmd:={"t":"attack","units":[hero.uid],"target":enemy.uid} if attack else {"t":"move","units":[hero.uid],"x":at.x,"y":at.y}
		s.apply_command(cmd,0)
		check(hero.orders.size()==1,"paused command remains queued, attack="+str(attack))
		var marks:=fx.effects.filter(func(ef):return ef not in before and ef.e.type==0x2039)
		check(not marks.is_empty(),"path is emitted before a simulation tick, attack="+str(attack))
		if attack:
			check(before.filter(func(ef):return ef.e.type==0x2039).all(func(ef):return ef not in fx.effects),"replacement paused command removes the previous preview")
		if not marks.is_empty():
			check(not marks[0].e.parts.is_empty(),"paused path has actual particle geometry")
			check(marks[0].e.parts.any(func(p):return (int(p[0x16])>>24)>0),"paused path particles have visible alpha")
			if DisplayServer.get_name()!="headless":
				await frames(3)
				check(marks[0].mmi!=null and marks[0].mmi.multimesh.visible_instance_count>0,"paused path reaches rendered instance buffer")
		check(hero.pos==pos and hero.mana==mana and hero.hp==hp and s.world.time==time and fx.tick==ticks,"preview does not advance actor, world or effects clocks")
	get_tree().paused=false
	mode="issues 13 and 14"
	for aggressive in [false,true]:
		reset();hero.aggressive=aggressive
		hero.order={"type":"move","to":at,"swarm":at,"path_notice":true};hero.ai_next=-1
		hero.set_meta("noticed",{enemy.get_instance_id():enemy});hero.set_meta("perceived",s.world.time)
		check(s.world.ai.swarm_tick(hero),"explicit attack-move acquires enemy, aggressive="+str(aggressive))
		check(order_target(enemy) and hero.orders[0].get("path_notice",false),"automatic attack requests its new path")
		check(hero.aggressive==aggressive,"attack-move leaves standing aggression preference intact")
	reset();hero.aggressive=false
	hero.set_meta("noticed",{enemy.get_instance_id():enemy});hero.set_meta("perceived",s.world.time)
	s.world.ai._player(hero)
	check(hero.orders.is_empty(),"defensive idle never starts an unsolicited attack")
	mode="issue 10"
	var audio:=GameSound.instance
	var dialog:=g.hud._dialog
	dialog._mode=DialogPanel.PLAYING;dialog.show();audio._screens()
	check(audio.dialogue_active() and audio.units.dialogue_silent,"playing quest dialogue silences incidental creature voices")
	audio._ack_queue(hero,EIAcks.BORED,"heroes\\Hero\\idle\\1.wav")
	check(Array(audio._ack_q.get(hero.uid,[])).is_empty(),"bored acknowledgement is not queued during dialogue")
	audio._ack_q[hero.uid]=[{"code":EIAcks.BORED,"handle":-1},{"code":EIAcks.SCENARIO,"handle":-1}]
	audio._silence_chatter()
	check(audio._ack_q[hero.uid].size()==1 and audio._ack_q[hero.uid][0].code==EIAcks.SCENARIO,"dialogue clears pending chatter but preserves scripted lines")
	audio._ack_q.clear();dialog.hide();audio._screens()
	check(not audio.dialogue_active() and not audio.units.dialogue_silent,"ordinary voices resume after dialogue")
	g.queue_free();s.queue_free();await frames(8)
	print("ISSUE_CAMPAIGN_ORDERS ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if failures else 0)
