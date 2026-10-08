extends Node
## Full route coverage and a rendered destination with the hero >90 m away.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func route(start: Vector2, length: float, cutoff := 1e6) -> Dictionary:
	var cells := []
	var values := []
	for x in int(length * 2) + 1:
		cells.append([int(start.x * 2) + x, int(start.y * 2)])
		values.append(512)
	return {"start":[start.x,start.y], "end":[start.x+length,start.y],
		"target":[start.x+length,start.y], "cells":cells, "values":values,
		"ticks":cutoff, "heading":0.0, "mode":0, "cross":0}
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"show_path":1,"path_through":1},true)
	var marks := OrderMarks.new()
	var long_path := marks._ghost_ticks(route(Vector2(10,10),1000))
	check(long_path.size() <= 2500,"long path retains a bounded particle budget")
	check(not long_path.is_empty() and Vector2(long_path[-1].x,long_path[-1].y).distance_to(Vector2(1010,10)) < 0.01,
		"one-kilometre route reaches its destination")
	var short_path := marks._ghost_ticks(route(Vector2(10,10),20))
	check(short_path.size()==81,"short path retains native quarter-metre spacing")
	check(short_path[40].distance_to(Vector3(20,10,0)) < 0.01,"short path preserves native sample positions")
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session=s; s.game=g; add_child(g)
	s.set_physics_process(false)
	s.state=CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.world.vm.instances.clear()
	var hero: GameUnit=s.party_units(0)[0]
	var fx := ParticleFx.of(s.world)
	fx.set_process(false)
	g.rig.set_process(false)
	var camera := Camera3D.new(); add_child(camera); camera.current=true
	var start := Vector2(40,40)
	var end := start+Vector2(130,0)
	var z := s.world.ground_at(end.x,end.y)
	camera.position=EISpace.pos(end.x-8,end.y-12,z+18)
	camera.look_at(EISpace.pos(end.x-8,end.y,z),Vector3.UP)
	var event := route(start,130)
	event.uid=hero.uid
	g.marks.on_path(event)
	fx._tick(); fx._tick(); fx._draw(1.0)
	var trail: ParticleFx.Effect
	for ef in fx.effects:
		if ef.e.type==0x2039: trail=ef
	check(trail!=null,"move order creates a trail")
	if trail:
		check(trail.mmi.multimesh.visible_instance_count>0,"visible destination keeps its trail when the starting point is over 90 m away")
		check(trail.e.parts.size() > 500,"complete 130-metre trail emits particles")
	if DisplayServer.get_name()!="headless":
		for i in 8: await get_tree().process_frame
		check(get_viewport().get_texture().get_image().save_png("user://distant-path.png")==OK,"rendered distant path captured")
		print("PATH_IMAGE ",ProjectSettings.globalize_path("user://distant-path.png"))
	# Action paths stop at the server's contact tick even when the route is long.
	event=route(start,1000,100.9); event.uid=hero.uid
	g.marks.on_path(event); fx._tick(); fx._draw(1.0)
	for ef in fx.effects:
		if ef.e.type==0x2039: trail=ef
	var last: Array=trail.e.parts[-1] if trail and not trail.e.parts.is_empty() else []
	check(not last.is_empty() and absf(float(last[0])-(start.x+25.0)) < 0.01,
		"action cutoff ends at the original whole contact tick")
	marks.free(); camera.queue_free(); g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("PATH_PREVIEW ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
