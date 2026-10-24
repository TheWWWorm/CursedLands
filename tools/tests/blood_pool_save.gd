extends Node
## Full Session kill/save/reload, including persisted age, geometry, stale
## events and expired pools. Run with a display for image evidence too.
var checks := 0
var failures := 0
var s: Session
var g: Game
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func freeze() -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	g.rig.set_process(false)
	GroundMarks.of(s.world).set_process(false)
	for u: GameUnit in s.world.unit_rows():
		u.resync_drawn()
		u.set_process(false); u.set_physics_process(false)

func picture(label: String, at: Vector2) -> void:
	if DisplayServer.get_name()=="headless": return
	var fog := g.get_node_or_null("UnitFog")
	if fog: fog.set_process(false)
	var body: GameUnit = s.world.units.get(3326)
	if body: body.fogged=false; body.visible=true
	var view := SubViewport.new(); view.size=Vector2i(960,540); view.world_3d=g.get_world_3d()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.current=true
	var point := EISpace.pos(at.x,at.y,s.world.ground_at(at.x,at.y))
	camera.global_position=point+Vector3(0,4,4); camera.look_at(point)
	for i in 8: await RenderingServer.frame_post_draw; await get_tree().process_frame
	view.get_texture().get_image().save_png("user://blood-pool-"+label+".png")
	view.free()

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0,"auto_graphics":0,"marks":1},true)
	s=Session.new(); add_child(s); s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero"); s.state.world_time=12.0; s.state.set_var(0,"q.gz3g.q1g",1)
	g=Game.new(); g.session=s; s.game=g; add_child(g)
	await s.enter_zone("gz3g",1,false); freeze()
	var w := s.world
	var body: GameUnit = w.units[3326]
	var hero: GameUnit = s.party_units(0)[0]
	hero.set_meta("noticed",{body.get_instance_id():body})
	w.corpse_pools.refresh()
	body.die()
	var marks := GroundMarks.of(w)
	for i in 180:
		w._logic_step+=1; w.time+=GameUnit.TICK; body._tick_blood_pool()
		if not marks.blood_marks.is_empty(): break
	check(body._pool_sent and marks.blood_marks.size()==1,"actual death queue creates one blood pool")
	if marks.blood_marks.is_empty(): get_tree().quit(1); return
	for i in 20: w.time+=GameUnit.TICK; marks._tick()
	var original := marks.blood_marks[0]
	var before := {"a":original.a,"angle":original.angle,"life":original.life,"alpha":original.decal.modulate.a,"x":original.x,"y":original.y}
	var death_clip := body.model._current
	var at := Vector2(original.x,original.y)
	await picture("before",at)
	check(s.save_game("blood-pool")==OK,"full Session save succeeds")
	var saved := CampaignState.load_from(SaveInfo.path("blood-pool"))
	var ledger: Array = saved.zones[saved.current_zone].get("pool_membership",{}).get("pools",[])
	check(ledger.size()==1 and int(ledger[0].mark.age)==20,"save contains the living pool at its current age")
	check(s.load_game("blood-pool"),"full Session load succeeds"); freeze()
	check(s.world.units[3326].model._current==death_clip,"reload keeps the same death pose above the pool")
	marks=GroundMarks.of(s.world)
	check(marks.blood_marks.size()==1,"reload recreates exactly one pool")
	if not marks.blood_marks.is_empty():
		var after := marks.blood_marks[0]
		check(is_equal_approx(after.a,before.a) and is_equal_approx(after.angle,before.angle),"reload retains pool growth and rotation")
		check(after.life==before.life and is_equal_approx(after.decal.modulate.a,before.alpha),"reload retains remaining life and opacity")
		check(after.x==before.x and after.y==before.y,"reload retains pool position")
	await picture("after",at)
	var event: Dictionary = s._replay_events().filter(func(e):return e.get("t")=="blood_pool")[0]
	s._on_event(event); s._replay_local()
	check(marks.blood_marks.size()==1,"late/repeated replay cannot duplicate the pool")
	var stale := event.duplicate(true); stale.pool_epoch-=1; stale.pool_id=999
	s._on_event(stale)
	check(marks.blood_marks.size()==1,"previous-world event cannot recreate a pool")
	s.world.remove_unit(s.world.units[3326])
	check(s.save_game("blood-pool-looted")==OK and s.load_game("blood-pool-looted"),"save/load after removing the corpse succeeds"); freeze()
	check(GroundMarks.of(s.world).blood_marks.size()==1,"pool survives removal of the original body")
	s.world.time += float(ledger[0].mark.life+1)*GameUnit.TICK
	check(s.save_game("blood-pool-expired")==OK and s.load_game("blood-pool-expired"),"save/load after natural expiry succeeds"); freeze()
	check(GroundMarks.of(s.world).blood_marks.is_empty(),"expired pools are not resurrected by loading")
	for invalid in [{}, {"x":NAN}, {"age":-1}]:
		check(not GroundMarks.valid_pool(invalid),"malformed pool rejected")
	FileAccess.open("user://blood-pool-save.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"before":before,"saved_pools":ledger},"\t"))
	g.queue_free(); s.queue_free()
	for i in 6: await get_tree().process_frame
	TexUpscale.shutdown(); print("BLOOD_POOL_SAVE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
