extends "third_person_kbm.gd"
## Real models, native movement/use ticks, shared rules and camera HUD.
class ExitProbe extends Session:
	var departures: Array = []
	func leave_zone(to: String, entrance: int, player := -1, _source_zone := "", _source_generation := 0) -> void:
		departures.append([to, entrance, player])

func tick() -> void:
	s.world.time += GameUnit.TICK
	hero.tick(GameUnit.TICK)
	hero._draw_step(GameUnit.TICK)
	hero.model.player.advance(GameUnit.TICK)
	s.world.vm._check_interactions()

func pickup_cases() -> void:
	for camera_mode in [1,2,3]:
		GameData.options.control_mode=camera_mode
		reset();hero.ai_next=INF;hero._perceive_next=INF
		var loot := body(free_point(0.6))
		var money := s.state.money
		g.order_on(loot,false)
		var approach := hero.orders.duplicate(true)
		for i in 20: g.order_on(loot,false)
		check(hero.orders==approach,"repeated pickup keeps one approach in camera "+str(camera_mode))
		var phases: Array=[]
		var resets:=0
		var last_phase:=-1
		for i in 240:
			if s.world.units.has(loot.uid): g.order_on(loot,false)
			tick()
			if hero.order.get("sub","")=="loot":
				var phase:=int(hero.order.get("phase",0))
				if phase<last_phase: resets+=1
				if phases.is_empty() or phases[-1]!=phase: phases.append(phase)
				last_phase=phase
			if not s.world.units.has(loot.uid) and hero.order.is_empty():break
		check(s.state.money==money+7 and not s.world.units.has(loot.uid),"pickup spam grants loot exactly once in camera "+str(camera_mode))
		check(resets==0 and phases.size()>1,"pickup animation never restarts while spammed in camera "+str(camera_mode))

func stamina_cases() -> void:
	reset();hero.ai_next=INF;hero._perceive_next=INF
	var legacy:=ModStore.snapshot();legacy.rules.erase("free_run")
	check(ModStore.configuration_error(legacy)=="","older saved rule list remains compatible")
	legacy.rules.erase("difficulty")
	check(ModStore.configuration_error(legacy)!="","missing established rules still reject damaged saves")
	check(ModStore.apply_rules({"free_run":1})=="" and s.mod_config.rules.free_run==1,"host can enable the shared free-running rule")
	hero.mana=hero.max_mana;hero.action="run";hero._anim_lock=1.0
	var before:=hero.mana
	hero._tick(GameUnit.TICK)
	check(hero.free_running() and hero.mana==before,"running outside combat consumes no stamina")
	hero.mana=0
	check(not hero.cannot_run(),"free running works even with depleted spell stamina")
	hero.stats.load=hero.stats.get("max_load",100.0)+1
	check(hero.cannot_run(),"free running preserves carrying restrictions")
	hero.stats.load=0
	# An attack by the party is the original shared combat flag, without audio.
	hero.order={"type":"attack","target":hero};hero._anim_lock=1.0
	s.world.time+=GameUnit.TICK;hero.mana=hero.max_mana;hero.action="run";before=hero.mana
	hero._tick(GameUnit.TICK)
	check(not hero.free_running() and hero.mana<before,"combat restores normal running stamina cost")
	reset();s.world.time+=GameUnit.TICK;hero.mana=hero.max_mana
	var cost:=hero._spell_cost(Spells.parse("healing{}"))
	hero.order={"type":"cast","spell":"healing{}","target":hero,"point":hero.pos,"known_spell":true}
	for i in 10:
		hero._tick(GameUnit.TICK)
		if hero.mana<hero.max_mana:break
	check(cost>0 and hero.mana<hero.max_mana,"free running does not remove spell costs")
	ModStore.apply_rules({"free_run":0});reset();hero.action="run";hero._anim_lock=1;hero.mana=hero.max_mana;before=hero.mana
	hero._tick(GameUnit.TICK)
	check(hero.mana<before,"disabling the toggle restores ordinary running cost")

func bars_cases() -> void:
	reset();GameData.options.control_mode=2
	var bars:=EnemyBars.of(g);bars.set_process(false)
	bars._step(0.25)
	var hp:=hero.hp
	hero.hp=hp*0.5;bars._step(0.03)
	check(bars.health_fraction(hero)>hero.hp/hero.max_hp and bars.health_fraction(hero)<hp/hero.max_hp,"health changes animate between snapshots")
	bars._step(0.12)
	check(is_equal_approx(bars.health_fraction(hero),hero.hp/hero.max_hp),"health display converges to exact authority value in 120 ms")
	hero.hp=hp
	var replacement:=GameUnit.new();replacement.uid=hero.uid;replacement.hp=10;replacement.max_hp=10
	check(bars.health_fraction(replacement)==1.0,"reused unit ID never inherits an old health value")
	replacement.free()
	hero.set_process(false)
	var head:=hero.model._head;var old:=head.position
	await frames(1)
	var height:=EnemyBars.head_top(hero)
	head.position.y+=0.2
	await frames(1)
	check(EnemyBars.head_top(hero)>height+0.15,"bar anchor follows head height on the next rendered frame")
	head.position=old;hero.set_process(true)
	var zone:Dictionary=s.world.zone
	s.world.zone=zone.duplicate(true);s.world.zone.type="brief"
	for camera_mode in [1,2,3]:
		GameData.options.control_mode=camera_mode;g.hud._process(0);bars._process(0)
		check(not g.hud._field.visible and not bars.visible,"safe zone hides combat HUD and health bars in camera "+str(camera_mode))
	s.world.zone=zone

func exit_cases() -> void:
	reset();GameData.options.control_mode=2
	var probe:=s as ExitProbe
	var zone:Dictionary=s.world.zone
	var start:=hero.pos
	var end:=free_point(2.0)
	check(end.distance_to(start)>1.0,"fixture has a nearby open exit approach")
	var direction:=(end-start).normalized()
	s.world.zone={"type":"brief","restrict":Vector3(start.x,start.y,0.5),"exits":{1:{"to":"fixture_field","to_exit":1,"remove":Rect2(end-Vector2.ONE*0.5,Vector2.ONE)}}}
	s.state.set_var(0,"z.fixture_field",0)
	s.apply_command({"t":"direct_control","leader":hero.uid},0)
	s._auto_world=null;s._village_exit_check()
	check(s.village_exit_path(end,0),"open exit corridor bypasses the village camera circle")
	check(not s.village_exit_path(start-direction*4,0),"unrelated village boundary remains closed")
	hero.set_gait(3);hero.mana=hero.max_mana;hero.ai_next=INF;hero._perceive_next=INF;hero._anim_lock=0
	for i in 100:
		s.apply_command({"t":"direct_move","units":[hero.uid],"direction":direction},0)
		tick();s._village_exit_check()
		if not probe.departures.is_empty():break
	check(probe.departures.size()==1,"running through open village exit transitions without E/A")
	s._village_exit_check();check(probe.departures.size()==1,"remaining inside exit does not repeat transition")
	s.state.set_var(0,"z.fixture_field",1)
	check(not s.village_exit_path(end,0),"story-locked exit cannot bypass the boundary")
	s.state.set_var(0,"z.fixture_field",0)
	reset();hero.pos=start;hero._sync_transform(0);s._auto_world=null
	s.apply_command({"t":"direct_control","leader":-1},0)
	s.apply_command({"t":"move","units":[hero.uid],"x":end.x,"y":end.y,"line":true,"walk_exit":true},0)
	check(s.walking_to_exit(0) and hero.orders[0].to==end,"classic gamepad steering can reach the same exit")
	s._village_exit_check();hero.pos=end;s._village_exit_check()
	check(probe.departures.size()==2,"classic gamepad arrival also transitions without a prompt")
	s.world.zone=zone;hero.pos=start;reset()

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	PadInput.active="kbm";s=ExitProbe.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="direct view regressions";await s.enter_zone("gz1g",1,false);await prepare()
	await pickup_cases();await stamina_cases();await bars_cases();await exit_cases()
	evidence.checks=checks;evidence.failures=failures
	FileAccess.open("user://direct-view-regressions.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("DIRECT_VIEW_REGRESSIONS ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
