extends Node
func state(u: GameUnit) -> Dictionary:
	return {"uid":u.uid,"pos":[u.pos.x,u.pos.y],"order":String(u.order.get("type","")),
		"susp_order":bool(u.order.get("susp",false)),"suspect":(u.get_meta("suspect",{}) as Dictionary).duplicate(true),
		"seen_corpses":(u.get_meta("seen_corpses",{}) as Dictionary).values().map(func(x):return x.uid)}
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",message)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"auto_graphics":0},true)
	var s := Session.new();add_child(s);s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero");s.state.world_time=12.0;s.state.set_var(0,"q.gz3g.q1g",1)
	var g := Game.new();g.session=s;s.game=g;add_child(g)
	await s.enter_zone("gz3g",1,false)
	var w := s.world;w.set_process(false);w.set_physics_process(false)
	var observer: GameUnit = w.units[3327]
	var body: GameUnit = w.units[3326]
	body.pos=observer.pos+Vector2(0,-1.75);body._sync_transform(0);w.nav.track_unit(body)
	var rows := [{"before":state(observer),"logic":w.ai.logic(observer),"motivations":w.ai.mots(observer)}]
	body.die()
	for tick in 240:
		w._tick(GameUnit.TICK)
		if tick%10==0:
			rows.append({"tick":tick,"observer":state(observer),"can_notice_corpse":w.ai.can_notice(observer,body,float(observer.stats.sight)),"corpse_motivations":w.ai.mots(observer)})
			await get_tree().process_frame
	check(rows[1].observer.seen_corpses.has(body.uid),"authored wolf notices the dead packmate")
	check(rows[1].observer.suspect.get("l0",0)==800.0,"corpse raises original suspicion level")
	check(rows.any(func(row):return row.has("observer") and row.observer.order=="move" and row.observer.susp_order),"wolf approaches the corpse under suspicion")
	check(rows.any(func(row):return row.has("observer") and row.observer.order=="wait" and row.observer.susp_order),"wolf waits and looks around at the corpse")
	var result := {"checks":checks,"failures":failures,"scope":"Authored right-hand wolf; another pack wolf killed 1.75m in front; hero at entrance; manual 55ms ticks.","native_query":w.ai._unit_query!=null,"native_perception":w.ai._perception!=null,"rows":rows}
	FileAccess.open("user://corpse-probe.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("CORPSE_PROBE ",JSON.stringify(result))
	g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	TexUpscale.shutdown();print("AUTHORED_WOLF_CORPSE ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
