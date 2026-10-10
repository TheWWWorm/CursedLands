extends Node
## Host command/Briefings boundary checks with a controlled static route.
## Real bz23k geometry, original source and save/reload live in lia_haburu_audit.gd.
const AuthoredTalk = preload("res://src/game/script/authored_village_talk.gd")
var checks := 0
var failures: Array[String] = []
var s: ProbeSession
var w: GameWorld
var vm: ScriptVM
var b: ProbeBriefings
var nav: ProbeNav
var heroes: Array[GameUnit] = []
var npc: GameUnit
var other: GameUnit

class ProbeSession extends Session:
	var events: Array[Dictionary] = []
	func broadcast(event: Dictionary) -> void: events.append(event.duplicate(true))
	func sync_state() -> void: pass

class ProbeNav extends NavGrid:
	var route_open := false
	var ignored: Array = []
	func find_path(a: Vector2, z: Vector2, ignore: Array = [], _avoid: Array = [], _extra := 0.0,
			_cls := WALK_CLASS, _flat := false, _facing := NAN, _limit := 1e6,
			_min_radius := 0.0, _retry := false, _moving_at := Vector2.INF) -> PackedVector2Array:
		ignored=ignore.duplicate()
		return PackedVector2Array([a,z]) if route_open else PackedVector2Array()

class ProbeBriefings extends Briefings:
	var started: Array[Dictionary] = []
	func play_named(id: String, key: String, player := 0, partner: GameUnit = null,
			instant := false, approached := false) -> void:
		started.append({"id":id, "var":key, "player":player, "uid":partner.uid,
			"instant":instant, "approached":approached})

class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String,
		why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind!=ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code,why,file,line,fn])
var errors := Errors.new()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func add_actor(id: int, controller: int, at: Vector2, name: String) -> GameUnit:
	var u := GameUnit.new(); u.uid=id; u.controller=controller; u.world=w; u.pos=at
	u.info={"name":name}; w.set_unit(id,u)
	return u

func click(player := 0, target: GameUnit = null) -> void:
	if target==null: target=npc
	s.apply_command({"t":"interact", "target":target.uid, "units":[heroes[player].uid]},player)

func select(player := 0, key := AuthoredTalk.TOPIC) -> void:
	s.apply_command({"t":"topic", "uid":npc.uid, "var":key},player)

func topic_count() -> int:
	return s.events.filter(func(e:Dictionary):return e.t=="topics").size()

func fallback() -> bool:
	return AuthoredTalk.original_stage(s,heroes[0],npc,0)

func _ready() -> void:
	OS.add_logger(errors)
	s=ProbeSession.new(); s.state=CampaignState.new(); s.state.campaign_id=CampaignProfile.ASTRAL
	s.zone_id="bz23k"; w=GameWorld.new(); w.zone={"id":"bz23k", "type":"brief"}; s.world=w; w.session=s
	nav=ProbeNav.new(); w.nav=nav
	vm=ScriptVM.new(); vm.world=w; vm.session=s; w.vm=vm
	b=ProbeBriefings.new(vm); vm.briefings=b
	heroes.append(add_actor(101,0,Vector2(32.5,66),"Hero"))
	heroes.append(add_actor(102,1,Vector2(33.5,66),"Guest"))
	npc=add_actor(ScriptVM.name_id("Haburu"),-1,AuthoredTalk.DISPLAY_POSITION,"Haburu")
	other=add_actor(ScriptVM.name_id("Other"),-1,Vector2(42,83),"Other")
	s.state.set_var(0,AuthoredTalk.TOPIC,1)

	check(fallback(),"exact disconnected authored Haburu case is eligible")
	check(nav.ignored.size()==4 and nav.ignored[0]==heroes[0] and nav.ignored.has(other),
		"static probe ignores every actor and keeps the initiating mover first")
	nav.route_open=true; check(not fallback(),"reachable approach does not opt into original staging"); nav.route_open=false
	s.state.campaign_id=CampaignProfile.ORIGINAL; check(not fallback(),"base campaign is excluded"); s.state.campaign_id=CampaignProfile.ASTRAL
	s.zone_id="bz22k"; check(not fallback(),"other village is excluded"); s.zone_id="bz23k"
	w.zone.type="game"; check(not fallback(),"field interaction is excluded"); w.zone.type="brief"
	npc.uid+=1; check(not fallback(),"actor with a different identity is excluded"); npc.uid-=1
	npc.info.name="Other"; check(not fallback(),"renamed actor is excluded"); npc.info.name="Haburu"
	npc.pos+=Vector2(0.1,0); check(not fallback(),"modified display placement is excluded"); npc.pos=AuthoredTalk.DISPLAY_POSITION
	npc._talk_posted=1; check(not fallback(),"scripted moving NPC is excluded"); npc._talk_posted=9
	npc.dead=true; check(not fallback(),"dead NPC is excluded"); npc.dead=false
	heroes[0].dead=true; check(not fallback(),"dead hero is excluded"); heroes[0].dead=false
	heroes[0].controller=1; check(not fallback(),"another player's hero is excluded"); heroes[0].controller=0
	var home := heroes[0].pos
	heroes[0].pos=npc.pos+Vector2.ONE; check(not fallback(),"nearby talk retains normal arrival behavior"); heroes[0].pos=home
	s.state.set_var(0,AuthoredTalk.TOPIC,0); check(not fallback(),"unavailable first topic is excluded")
	s.state.set_var(0,AuthoredTalk.TOPIC,2); check(not fallback(),"completed first topic is excluded")
	s.state.set_var(0,AuthoredTalk.TOPIC,1)

	heroes[0].command({"type":"move", "to":Vector2(50,50)})
	heroes[0].set_meta("interact",[other,0])
	click()
	check(topic_count()==1,"fallback click opens the ordinary topic event")
	check(heroes[0].order.is_empty() and heroes[0].orders.size()==1 and heroes[0].orders[0].type=="wait"
		and heroes[0].path.is_empty() and not heroes[0].has_meta("interact"),"fallback stops old movement and pending interaction")
	check(b._original_village_topics.has(0),"host receives transient topic context")
	click(1)
	check(topic_count()==2 and s.events[-1].player==1,"guest's own click receives a guest-scoped topic list")
	check(b._original_village_topics.has(0) and b._original_village_topics.has(1),"guest opening does not overwrite host context")
	select(1)
	check(b.started.size()==1 and b.started[-1].player==1 and b.started[-1].instant and not b.started[-1].approached,
		"guest's valid selection chooses authored instant staging")
	check(b._original_village_topics.has(0) and not b._original_village_topics.has(1),"guest selection consumes only guest context")
	select()
	check(b.started.size()==2 and b.started[-1].player==0 and b.started[-1].instant and not b.started[-1].approached,
		"host selection retains its independently opened context")
	check(b._original_village_topics.is_empty(),"topic selection consumes context")
	var previous := topic_count()
	s.apply_command({"t":"interact", "target":npc.uid, "units":[heroes[0].uid]},1)
	check(topic_count()==previous,"guest cannot open a host hero's topic flow")

	# Goodbye is local UI state. A reopen must evaluate the new command, and
	# a subsequent walk or changed target must clear the old host-only marker.
	click(); nav.route_open=true; click()
	check(not b._original_village_topics.has(0) and heroes[0].orders[0].type=="follow" and heroes[0].has_meta("interact"),
		"reachable reopen replaces fallback context with cancellable approach")
	check(topic_count()==previous+1,"reachable reopen publishes no topics before arrival")
	heroes[0].pos=npc.pos+Vector2(1,0); vm._check_interactions()
	check(topic_count()==previous+2 and not heroes[0].has_meta("interact"),"reachable approach publishes topics only on arrival")
	select()
	check(not b.started[-1].instant and b.started[-1].approached,"reachable conversation retains D15 in-place staging")
	heroes[0].pos=home
	click(); previous=topic_count()
	s.apply_command({"t":"move", "units":[heroes[0].uid], "x":30.0, "y":60.0},0)
	vm._check_interactions()
	check(not heroes[0].has_meta("interact") and topic_count()==previous,"replacement movement cancels normal approach without dialogue")
	click(); heroes[0].orders.clear(); heroes[0].order={}; heroes[0].order_failed=true; vm._check_interactions()
	check(not heroes[0].has_meta("interact") and topic_count()==previous,"failed normal approach is cleared without instant fallback")

	nav.route_open=false; click(); previous=topic_count()
	s.state.set_var(0,"b.Other.fq15",1); click(0,other)
	check(not b._original_village_topics.has(0) and topic_count()==previous and heroes[0].has_meta("interact"),
		"changed target clears fallback context before its ordinary approach finishes")
	click(); s.apply_command({"t":"move", "units":[heroes[0].uid], "x":30.0, "y":60.0},0)
	check(not b._original_village_topics.has(0),"movement after topic cancellation clears original context")
	click(); select(0,"b.Haburu.unavailable")
	check(not b._original_village_topics.has(0),"invalid topic attempt also consumes the transient flow")
	click(); s.state.set_var(0,"b.Haburu.fq16",1); select(0,"b.Haburu.fq16")
	check(not b.started[-1].instant and b.started[-1].approached and not b._original_village_topics.has(0),
		"another offered topic cannot inherit fq15's staging exception")
	click(); npc.pos+=Vector2(0.1,0); select()
	check(not b.started[-1].instant and b.started[-1].approached,"selection revalidates the exact authored display position")
	npc.pos=AuthoredTalk.DISPLAY_POSITION
	click(); nav.route_open=true; select()
	check(not b.started[-1].instant and b.started[-1].approached,"selection revalidates static disconnection")
	nav.route_open=false; click(); var starts := b.started.size(); s.state.set_var(0,AuthoredTalk.TOPIC,2); select()
	check(b.started.size()==starts and not b._original_village_topics.has(0),"another player's completed shared topic cannot replay")
	s.state.set_var(0,AuthoredTalk.TOPIC,1)
	click(); b.active="b.Haburu.fq16"; select()
	check(b.started.size()==starts and not b._original_village_topics.has(0),"active dialogue rejects a stale topic and consumes its context")
	b.active=""
	click(); var restored := Briefings.new(vm)
	check(restored._original_village_topics.is_empty(),"a rebuilt Briefings instance has no saved topic context")
	b.clear_original_topics(0)
	w.zone.type="game"; previous=topic_count(); click()
	check(topic_count()==previous and heroes[0].has_meta("interact") and not b._original_village_topics.has(0),
		"unreachable field click always uses the ordinary approach")
	heroes[0].orders.clear(); heroes[0].order={}; heroes[0].order_failed=true; vm._check_interactions()
	check(not heroes[0].has_meta("interact") and topic_count()==previous,"unreachable field failure never opens fallback topics")

	# The completed base rescue has the same authored display constraint,
	# but its own chapter and exact-topic admission requirements.
	var haburu := npc
	s.state.campaign_id=CampaignProfile.ORIGINAL; s.zone_id="bz13h"
	s.state.current_party="HeroAlone"; s.state.set_var(0,"q.gz15h.q61h",2)
	w.zone={"id":"bz13h","type":"brief","cage":true}; w.levers={42999:{"state":1}}
	heroes[0].pos=Vector2(61,59.95)
	npc=add_actor(ScriptVM.name_id("Nalo"),-1,AuthoredTalk.NALO_DISPLAY_POSITION,"Nalo")
	s.state.set_var(0,AuthoredTalk.NALO_TOPIC,1)
	check(fallback(),"completed rescue admits original Nalo staging")
	check(not AuthoredTalk.original_stage(s,heroes[0],npc,0,"b.Nalo.Kr60"),"another Nalo topic cannot use rescue staging")
	s.state.current_party="Pretty"; check(not fallback(),"Nalo's active player party cannot use return staging"); s.state.current_party="HeroAlone"
	s.state.set_var(0,"q.gz15h.q61h",1); check(not fallback(),"unfinished rescue cannot use return staging"); s.state.set_var(0,"q.gz15h.q61h",2)
	w.levers[42999].state=0; check(fallback(),"offered return topic works while native cell-opening script is pending"); w.levers[42999].state=1
	w.zone.cage=false; check(not fallback(),"changed prison staging layout is excluded"); w.zone.cage=true
	npc.pos+=Vector2(0.1,0); check(not fallback(),"modified Nalo display placement is excluded"); npc.pos=AuthoredTalk.NALO_DISPLAY_POSITION
	nav.route_open=true; check(not fallback(),"reachable Nalo keeps normal approach"); nav.route_open=false
	s.state.set_var(0,AuthoredTalk.NALO_TOPIC,2); check(not fallback(),"completed Nalo topic is excluded"); s.state.set_var(0,AuthoredTalk.NALO_TOPIC,1)
	previous=topic_count(); click()
	check(topic_count()==previous+1 and b._original_village_topics.has(0),"normal prison click opens scoped Nalo topics")
	select(0,AuthoredTalk.NALO_TOPIC)
	check(b.started[-1].var==AuthoredTalk.NALO_TOPIC and b.started[-1].instant and not b.started[-1].approached,
		"valid rescue topic chooses original instant staging")
	check(b._original_village_topics.is_empty(),"Nalo topic consumes its host context")
	click(); s.state.current_party=""; select(0,AuthoredTalk.NALO_TOPIC)
	check(not b.started[-1].instant and b.started[-1].approached,"Nalo selection revalidates active rescue party")
	s.state.current_party="HeroAlone"
	click(); s.state.set_var(0,"b.Nalo.Kr60",1); select(0,"b.Nalo.Kr60")
	check(not b.started[-1].instant and b.started[-1].approached,"another offered Nalo topic cannot inherit rescue context")
	click(); s.apply_command({"t":"move","units":[heroes[0].uid],"x":61.0,"y":60.0},0)
	check(not b._original_village_topics.has(0),"replacement movement clears Nalo context")
	check(errors.messages.is_empty(),"command and topic controls have no runtime errors")
	var result := {"checks":checks, "failures":failures, "errors":errors.messages,
		"scope":"Host-authoritative command/topic dispatch for players 0 and 1 with a controlled static route; not an ENet transport or native scene run."}
	FileAccess.open("user://lia-haburu-guards.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	OS.remove_logger(errors)
	w.units={}; nav.ignored.clear(); restored.vm=null; b.vm=null; vm.briefings=null; vm.world=null; vm.session=null
	for u in heroes: u.free()
	npc.free(); haburu.free(); other.free(); s.world=null; w.vm=null; w.session=null; w.free(); s.free()
	print("LIA_HABURU_GUARDS ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
