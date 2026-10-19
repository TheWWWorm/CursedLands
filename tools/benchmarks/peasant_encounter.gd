extends Node
## Targeted authored encounter, not a gameplay/performance benchmark. Only the
## hero's initial location/equipment is prepared; NPCs, scripts, perception,
## movement and damage all run normally. No AI helpers or metadata are injected.
class HelpTrace:
	extends UnitAI
	var calls:=[]
	var deliveries:=[]
	func call_for_help(u:GameUnit,at:Vector2)->void:
		super.call_for_help(u,at)
		var recipients:=[]
		for e:Array in _help:
			if e[1]==at and e[2]==26:recipients.append(e[0].uid)
		calls.append({"time":world.time,"caller":u.uid,"point":str(at),"recipients":recipients})
	func suspect(u:GameUnit,at:Vector2,level:float,delta:=-2.0)->void:
		super.suspect(u,at,level,delta)
		if level==900 and delta==-3:
			deliveries.append({"time":world.time,"unit":u.uid,"point":str(at),"notice":str(u.get_meta("noticed",{})),"suspect":str(u.get_meta("suspect",{}))})
var s:Session
var g:Game
var peon:GameUnit
var guard:GameUnit
var hero:GameUnit
var rows:=[]
var active:=false
var began:=0
var next_sample:=0.0
var attacked:=false
var cast_sent:=false
var expansion:=false
var initial_guard:=Vector2.ZERO
var observed_warning:=false
var observed_fear:=false
var observed_investigation:=false
var tracer:HelpTrace
var started_world:=0.0
func frames(n:int)->void:
	for i in n:await get_tree().process_frame
func _ready()->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()
func run()->void:
	if OS.get_cmdline_user_args().has("--validate-only"):
		print("PASS peasant encounter diagnostic parses");get_tree().quit();return
	if DisplayServer.get_name()=="headless":
		push_error("Peasant encounter diagnostic requires rendering");get_tree().quit(2);return
	expansion=GameData.campaign_id==CampaignProfile.ASTRAL
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"display_mode":0,"confine_mouse":0,"scroll_border":0,"pad_enabled":0},true)
	await frames(15);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,720)
	s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");s.state.world_time=12
	var h:Dictionary=s.state.heroes[0][0]
	h.str=38.0;h.dex=38.0;h.int=38.0;h.level=15
	h.skills={"melee":100,"sense":60,"science":25,"elemental":100,"astral":100}
	h.spells=["weak{}"]
	h.weapons=["crystal sword.diamond"]
	h.armors=["hadagan highest helm.mithrill","hadagan highest plate.mithrill","hadagan highest leggins.mithrill","hadagan highest shirt.mithrill","hadagan highest pants.mithrill","hadagan highest boots.mithrill","hadagan highest gloves.mithrill"]
	await s.enter_zone("gz1h" if expansion else "gz18h",1,false)
	await frames(15)
	peon=s.world.units.get(153729 if expansion else 150111)
	guard=s.world.units.get(21322 if expansion else 150110)
	if not expansion:
		# The farmland guards patrol. Choose an authored pair actually inside
		# the help radius now, rather than relying on their initial map points.
		var closest:=INF
		for candidate:GameUnit in s.world.unit_rows():
			if not "peasants" in String(candidate.info.get("prototype","")).to_lower():continue
			for ally:GameUnit in s.world.unit_rows():
				var proto:=String(ally.info.get("prototype","")).to_lower()
				if not ("guards" in proto or "overseer" in proto) or s.world.relation(candidate.faction,ally.faction)!=0:continue
				var distance:=candidate.pos.distance_to(ally.pos)
				if distance<closest:closest=distance;peon=candidate;guard=ally
		print("ENCOUNTER_PAIR ",peon.uid," ",guard.uid," distance ",closest)
	hero=s.party_units(0)[0]
	if not peon or not guard:push_error("Authored pair missing");get_tree().quit(2);return
	# Observe normal dispatch without altering AI state or calling its helpers.
	# Preserve all instance members, including activity/distant scheduling.
	var original:UnitAI=s.world.ai
	tracer=HelpTrace.new(s.world)
	for property:Dictionary in original.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name!="script":
			tracer.set(property.name,original.get(property.name))
	s.world.ai=tracer
	initial_guard=guard.pos
	var away:Vector2=(peon.pos-guard.pos).normalized()
	hero.pos=s.world.nav.nearest_walkable(peon.pos+away*6.0);hero.resync_drawn()
	g.selected.assign([hero]);g.rig.focus(peon.position);g.hud.text_window.open=false
	g.issue({"t":"aggression","units":[hero.uid],"on":false});g.set_speed(2)
	print("ENCOUNTER_SETUP ",JSON.stringify({"campaign":GameData.campaign_id,"peon":peon.info,"guard":guard.info,"peon_relation":s.world.relation(peon.faction,hero.faction),"guard_relation":s.world.relation(guard.faction,hero.faction),"friend":s.world.relation(peon.faction,guard.faction),"hero":str(hero.pos),"peon_stats":peon.stats,"guard_stats":guard.stats}))
	var goal:=peon.pos+away*4.0
	g.issue({"t":"move","units":[hero.uid],"x":goal.x,"y":goal.y,"run":false})
	began=Time.get_ticks_msec();started_world=s.world.time;active=true
func state(u:GameUnit)->Dictionary:
	return {"id":u.uid,"pos":[u.pos.x,u.pos.y],"hp":u.hp,"dead":u.dead,"action":u.action,"mode":u.mode,"order":str(u.order),"fear":u.has_meta("fear_on"),"suspect":str(u.get_meta("suspect",{})),"noticed":str(u.get_meta("noticed",{})),"ai_next":u.ai_next}
func _process(_dt:float)->void:
	if not active:return
	var t:=(Time.get_ticks_msec()-began)/1000.0
	var warnings:=[]
	for e:Array in s.world.ai._help:
		if e[0]==guard:warnings.append({"point":str(e[1]),"ticks":e[2]});observed_warning=true
	observed_fear=observed_fear or peon.has_meta("fear_on")
	observed_investigation=observed_investigation or guard.order.get("susp",false)
	if not expansion and not cast_sent and s.world.time-started_world>=1:
		cast_sent=true;g.begin_cast(0);g.cast_on(peon);g.cancel_touch_target()
		print("ENCOUNTER_CAST_WEAK ",s.world.time," radius ",peon.pos.distance_to(guard.pos))
	if t>=next_sample:
		next_sample=t+.25
		var row:={"wall":t,"world":s.world.time,"peon":state(peon),"guard":state(guard),"hero":state(hero),"warnings":warnings}
		rows.append(row);print("ENCOUNTER_SAMPLE ",JSON.stringify(row))
	if s.world.time-started_world>=8 and not attacked:
		attacked=true;g.issue({"t":"attack","units":[hero.uid],"target":peon.uid,"run":true});print("ENCOUNTER_ATTACK ",t)
	if s.world.time-started_world>=40 or t>=90:
		active=false;finish.call_deferred()
func finish()->void:
	var peasant_calls:=tracer.calls.filter(func(c):return c.caller==peon.uid and guard.uid in c.recipients)
	var delivered:=tracer.deliveries.filter(func(d):return d.unit==guard.uid and peasant_calls.any(func(c):return c.point==d.point and absf(d.time-c.time-26*GameUnit.TICK)<.12))
	var success:=observed_warning and observed_fear and not delivered.is_empty()
	print("ENCOUNTER_RESULT ",JSON.stringify({"pass":success,"warning":observed_warning,"fear":observed_fear,"investigation":observed_investigation,"guard_distance":guard.pos.distance_to(initial_guard),"guard_action":guard.action,"hero_alive":not hero.dead,"peasant_calls_to_guard":peasant_calls.size(),"first_peasant_call":peasant_calls[0] if not peasant_calls.is_empty() else {},"matched_deliveries":delivered.size(),"first_delivery":delivered[0] if not delivered.is_empty() else {}}))
	FileAccess.open("user://peasant-encounter.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	FileAccess.open("user://peasant-help-calls.json",FileAccess.WRITE).store_string(JSON.stringify(tracer.calls,"\t"))
	FileAccess.open("user://peasant-help-deliveries.json",FileAccess.WRITE).store_string(JSON.stringify(tracer.deliveries,"\t"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://peasant-encounter.png")
	g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown();get_tree().quit(0 if success else 1)
