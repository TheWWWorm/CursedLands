extends Node
## Authored rat group on original Gipat zone5_1. Only the hero's start and
## equipment are prepared; the command, cast, warning and AI ticks are real.
const SPELL := "stun{r2;r2;m2;m2}"
class ObservedAI:
	extends UnitAI
	var calls := []
	var deliveries := []
	var notifying := false
	func on_attacked(u: GameUnit, by: GameUnit) -> void:
		notifying=true
		super.on_attacked(u,by)
		notifying=false
	func call_for_help(u: GameUnit, at: Vector2, threat: GameUnit = null) -> void:
		super.call_for_help(u, at, threat)
		calls.append({"time":world.time,"ai_tick":_tick_n,"from_notification":notifying,"source":u.uid,"at":[at.x,at.y],
			"recipients":_help.filter(func(e):return e[1]==at and e[2]==26).map(func(e):return e[0].uid)})
	func suspect(u: GameUnit, at: Vector2, level: float, delta := -2.0) -> void:
		super.suspect(u, at, level, delta)
		if level == 900 and delta == -3:
			deliveries.append({"time":world.time,"ai_tick":_tick_n,"unit":u.uid,"at":[at.x,at.y]})

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:failures += 1;printerr("FAIL ",label)

func state(u: GameUnit) -> Dictionary:
	return {"uid":u.uid,"position":[u.pos.x,u.pos.y],"hp":u.hp,"action":u.action,
		"order":String(u.order.get("type","")),"investigating":bool(u.order.get("susp",false)),
		"noticed":(u.get_meta("noticed",{}) as Dictionary).values().map(func(n):return n.uid),
		"target":u.target.uid if is_instance_valid(u.target) else -1,"buffs":u.buffs.keys()}

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	var s := Session.new();add_child(s);s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero")
	var h: Dictionary=s.state.heroes[0][0]
	h.skills={"elemental":100,"astral":100,"sense":0};h.int=38.0;h.dex=38.0;h.spells=[SPELL]
	h.exp_total=200271.0
	s.state.world_time=12.0
	var g := Game.new();g.session=s;s.game=g;add_child(g)
	await s.enter_zone("gz5g",1,false)
	var w := s.world
	w.set_process(false);w.set_physics_process(false);w.vm.instances.clear();w.vm.briefings._check=INF
	var ai := ObservedAI.new(w)
	for property: Dictionary in w.ai.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "script":ai.set(property.name,w.ai.get(property.name))
	w.ai=ai
	var hero: GameUnit=s.party_units(0)[0]
	hero.aggressive=false;hero.orders.clear();hero.order.clear();hero._anim_lock=0
	check(Spells.known_usable(hero,SPELL),"prepared learned spell meets ordinary knowledge and stamina limits")
	if not Spells.known_usable(hero,SPELL):
		print("SPELL_DIAGNOSTIC ",Spells.parse(SPELL)," max_mana=",hero.max_mana)
		get_tree().quit(2);return
	var rats: Array=w.unit_rows().filter(func(u):return "rat" in String(u.info.get("prototype","")).to_lower())
	var pair: Array=[]
	var closest:=INF
	for a: GameUnit in rats:
		for b: GameUnit in rats:
			var d:=a.pos.distance_to(b.pos)
			if a==b or w.relation(a.faction,b.faction)!=0 or d>=closest or d>=float(ai.logic(a).get("help_radius",7.0)):continue
			closest=d;pair=[a,b]
	check(pair.size()==2,"authored Gipat map has neighbouring allied rats")
	if pair.size()!=2:
		print("RAT_GROUP_DIAGNOSTIC ",JSON.stringify(rats.map(func(u):return {"uid":u.uid,"info":u.info,"pos":str(u.pos),"faction":u.faction,"logic":ai.logic(u)})))
		get_tree().quit(2);return
	var victim: GameUnit=pair[0]
	var ally: GameUnit=pair[1]
	var found:=false
	for distance: float in [24.0,22.0,20.0,16.0,12.0,10.0,8.0,6.0]:
		for direction in 32:
			var at:=victim.pos+Vector2.from_angle(float(direction)*TAU/32)*distance
			if not w.nav.cell_open(at,hero.move_class()):continue
			hero.pos=at;hero._sync_transform(0);w.nav.track_unit(hero)
			if ai.can_notice(victim,hero,float(victim.stats.sight)) or ai.can_notice(ally,hero,float(ally.stats.sight)):continue
			if not Spells._trace_ok(w,Spells.parse(SPELL),hero.pos,hero.eye_z(),victim):continue
			if hero.pos.distance_to(victim.pos)>float(Spells.parse(SPELL).range):continue
			found=true;break
		if found:break
	check(found,"hero begins in spell range outside both rats' initial perception")
	if not found:
		print("PAIR_DIAGNOSTIC ",victim.info," ",ally.info," ",victim.stats," ",Spells.parse(SPELL))
		get_tree().quit(2);return
	for u: GameUnit in w.unit_rows():
		for key in ["noticed","seen_corpses","perceived","notice_candidates","suspect","attacker"]:u.remove_meta(key)
	w.time+=12.0*GameUnit.TICK
	ai._help.clear();ai.calls.clear();ai.deliveries.clear()
	g.selected.assign([hero]);g.hud.text_window.open=false
	var centre: Vector3=(hero.position+victim.position)*0.5
	g.rig.hold_view(centre+Vector3(0,25,12),centre)
	var before:=state(victim)
	if DisplayServer.get_name()!="headless":
		for i in 5:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://spell-alert-encounter-before.png")
	s.apply_command({"t":"cast","unit":hero.uid,"spell":SPELL,"target":victim.uid},0)
	check(not hero.orders.is_empty(),"ordinary learned-spell command is admitted")
	var trace:=[]
	var cast_applied:=false
	var investigated:=false
	var fought:=false
	for tick in 210:
		w._tick(GameUnit.TICK)
		cast_applied=cast_applied or victim.buffs.has("stun")
		investigated=investigated or ally.order.get("susp",false)
		fought=fought or ally.order.get("target")==hero
		if tick%5==0:trace.append({"tick":tick,"time":w.time,"hero":state(hero),"target":state(victim),"ally":state(ally)})
		if tick%10==0:await get_tree().process_frame
	var calls:=ai.calls.filter(func(c):return c.from_notification and c.source==victim.uid and ally.uid in c.recipients)
	# Native queue counter starts at 26 and fires below zero: 27 AI queue
	# updates. Wall-time offset depends on the creation phase within a tick.
	var matched:=ai.deliveries.filter(func(d):return d.unit==ally.uid and calls.any(func(c):return c.at==d.at and d.ai_tick-c.ai_tick==27))
	check(cast_applied,"actual cast animation/timer delivers Stun")
	check(not calls.is_empty(),"spell target calls its authored nearby ally")
	check(not matched.is_empty(),"ally receives the spell warning when the original counter passes below zero")
	check(investigated or fought,"warned ally leaves calm wandering to investigate or fight")
	var spell_record:=Spells.parse(SPELL).duplicate()
	spell_record.erase("proto")
	FileAccess.open("user://spell-alert-encounter.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"scope":"Authored map and AI; prepared hero start/equipment; quest VM frozen; no original whole-scene replay",
		"target":victim.info,"ally":ally.info,"distance":closest,"before":before,"spell":spell_record,
		"matched_warnings":matched,"calls":calls,"trace":trace},"\t"))
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://spell-alert-encounter.png")
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	print("SPELL_ALERT_ENCOUNTER ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
