extends "third_person_kbm.gd"
## Loaded original terrain and hero, deterministic authority ticks. A local
## wall on the navigation grid isolates steering from route following.
var start := Vector2.ZERO

func send(v: Vector2, player := 0) -> void:
	s.apply_command({"t":"direct_move","units":[hero.uid],"direction":v},player)

func tick(n := 1) -> void:
	for i in n:
		s.world.time += GameUnit.TICK
		hero.tick(GameUnit.TICK)
		hero._draw_step(GameUnit.TICK)
		s.world.vm._check_interactions()

func place() -> void:
	reset();hero.pos=start;hero._perceive_next=INF;hero.ai_next=INF
	s.world.nav.track_unit(hero);hero._sync_transform(0)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"pad_glyphs":1,"blood":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="authority steering";await s.enter_zone("gz1g",1,false);await prepare()
	var nav:=s.world.nav
	var origin:=hero.pos
	var found:=false
	for ring in 32:
		for angle in 16:
			hero.pos=origin+Vector2.from_angle(float(angle)*TAU/16)*ring
			nav.track_unit(hero)
			if [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN].all(func(d):return nav.direct_line(hero,hero.pos+d*2.0)):
				found=true;break
		if found:break
	start=hero.pos;place()
	check(found,"original terrain contains an open patch for the steering regression")
	s.apply_command({"t":"direct_control","leader":hero.uid},0)
	hero.set_gait(2);hero._anim_lock=0
	send(Vector2.RIGHT);tick(12)
	var full:=hero.pos.distance_to(start)
	check(full>0.4 and absf(hero.pos.y-start.y)<0.001,"held input walks straight on actual terrain")
	check(hero.path.is_empty() and hero._goal==Vector2.INF,"held input creates no navigation destination or pursuit path")
	var at:=hero.pos;send(Vector2.LEFT);tick()
	check(hero.pos.x<at.x,"reversing input reverses displacement on the next tick")
	send(Vector2.ZERO);at=hero.pos;tick(12)
	check(hero.pos==at,"release stops at authority position without walking back to a stale client position")
	place();send(Vector2.RIGHT*0.5);tick(12)
	check(absf(hero.pos.distance_to(start)-full*0.5)<0.1,"half stick tilt gives proportional movement")
	place();send(Vector2(20,0));tick(12)
	check(absf(hero.pos.distance_to(start)-full)<0.1,"authority clamps oversized input to normal speed")
	place();hero.set_gait(1);hero._anim_lock=0
	s.apply_command({"t":"direct_move","units":[hero.uid],"direction":Vector2.RIGHT,"run":true},0)
	check(hero.stance==GameUnit.STANCE_NONE,"Shift-run requests standing through normal posture clearance")
	hero._anim_lock=0;hero.mana=hero.max_mana
	var stamina:=hero.mana;tick(12)
	check(hero.pos.distance_to(start)>full*1.2 and hero.mana<stamina,"run input increases speed and consumes normal stamina")
	hero.set_gait(2)
	place()
	for v:Variant in [Vector2(NAN,0),Vector2(INF,0),Vector2(1e30,0),Vector3.RIGHT,"right"]:
		s.apply_command({"t":"direct_move","units":[hero.uid],"direction":v},0)
	check(hero.orders.is_empty(),"malformed and overflowing steering inputs are refused")
	send(Vector2.RIGHT,1);check(hero.orders.is_empty(),"another player cannot steer this hero")
	hero.blocked=true;send(Vector2.RIGHT);check(hero.orders.is_empty(),"script-blocked hero cannot be steered");hero.blocked=false
	send(Vector2.RIGHT);tick();hero.order.until=Time.get_ticks_msec()-1;at=hero.pos;tick(10)
	check(hero.pos==at and hero.is_idle(),"missing input refresh expires without runaway movement")
	place();send(Vector2.RIGHT);tick()
	hero.order.village_limit=Vector3(start.x,start.y,0.8);tick(70)
	check(hero.pos.distance_to(start)<=0.801,"steering respects the scripted village movement boundary")
	place()
	var layer:=nav.layer(hero.move_class())
	var wall:=nav.cell(start+Vector2(2,0))
	var restore:Dictionary={}
	for y in range(wall.y-12,wall.y+13):
		var cell:=Vector2i(wall.x,y)
		if not nav._in(cell):continue
		restore[cell]=[layer.land[cell.y*nav.size.x+cell.x],layer.astar.is_point_solid(cell)]
		layer.land[cell.y*nav.size.x+cell.x]=1;layer.astar.set_point_solid(cell,true)
	send(Vector2.RIGHT);tick(90)
	var blocked:=hero.pos
	check(nav.cell(blocked).x<wall.x and absf(blocked.y-start.y)<0.001,"forward against a wall stops without choosing a route or side")
	send(Vector2(1,1).normalized());tick(15)
	check(nav.cell(hero.pos).x<wall.x and hero.pos.y>blocked.y+0.15,"diagonal input slides along the wall without crossing it")
	send(Vector2.LEFT);at=hero.pos;tick()
	check(hero.pos.x<at.x,"steering away from a wall responds immediately")
	for cell:Vector2i in restore:
		layer.land[cell.y*nav.size.x+cell.x]=restore[cell][0];layer.astar.set_point_solid(cell,restore[cell][1])
	place()
	var actor:=body(start+Vector2(2,0),0,false);actor._perceive_next=INF;actor.ai_next=INF;nav.track_unit(actor)
	send(Vector2.RIGHT);tick(80);blocked=hero.pos
	check(blocked.x<actor.pos.x,"standing actor blocks forward movement")
	s.world.remove_unit(actor);send(Vector2.RIGHT);tick(12)
	check(hero.pos.x>blocked.x+0.2,"movement resumes when the actor leaves")
	place();var loot:=body(free_point());sky()
	# Exercise the actual interaction while movement is held, then key-up.
	g.direct.steer(Vector2.UP,0.1);tick()
	g.direct.interact()
	check(hero.has_meta("interact") and hero.get_meta("interact")[0]==loot,"interact while steering posts the nearby loot action")
	g.direct.step(Vector2.UP,0.1)
	check(hero.has_meta("interact"),"held movement cannot immediately overwrite interaction")
	g.direct.step(Vector2.ZERO,0.1);g.direct.stop_move()
	var money:=s.state.money
	for i in 300:
		tick()
		if not s.world.units.has(loot.uid):break
	check(not s.world.units.has(loot.uid) and s.state.money==money+7,"release during pickup preserves the use animation and collects once")
	place();loot=body(free_point());sky();GameData.options.pad_enabled=1;PadInput.active="pad"
	var press:=InputEventJoypadButton.new();press.device=42;press.button_index=JOY_BUTTON_A;press.pressed=true
	Input.parse_input_event(press);await frames(2)
	press=InputEventJoypadButton.new();press.device=42;press.button_index=JOY_BUTTON_A;Input.parse_input_event(press);await frames(2)
	check(hero.has_meta("interact") and hero.get_meta("interact")[0]==loot,"real gamepad A routing selects nearby loot outside the crosshair")
	check(g.direct.field().hints().any(func(h):return h.size()>2 and h[0]==PadInput.button_of("interact") and h[1]==RemakeText.t("Loot") and h[2]),"gamepad prompt names the available pickup")
	PadInput.release_all();PadInput.active="kbm";place();send(Vector2.RIGHT);tick()
	s.apply_command({"t":"direct_control","leader":-1},0);at=hero.pos;tick(5)
	check(hero.pos==at and hero.order.is_empty(),"leaving shoulder controls cancels held steering")
	evidence.checks=checks;evidence.failures=failures;evidence.scope="Original loaded map and hero, authority movement/collision, injected gamepad A input; no physical playthrough claim."
	FileAccess.open("user://direct-movement.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("DIRECT_MOVEMENT ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
