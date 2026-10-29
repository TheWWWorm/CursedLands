extends Node
const Route=preload("res://tools/tests/path_trace_zone_traversal.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	var session:=Session.new();add_child(session)
	var game:=Game.new();game.session=session;session.game=game;add_child(game)
	session.state.ensure_hero(0,session._hero_proto(0))
	await session.enter_zone("gz7g",1,false);session.set_physics_process(false)
	var hero:GameUnit=session.party_heroes()[0]
	var nav:=session.world.nav
	# Exact reported river boundary. The authority can stand just west of
	# it, while its ordinary 1/64-metre snapshot rounds onto the blocked side.
	var precise:=Vector2(161.0-1.0/256.0,273.1875)
	hero.pos=precise
	check(nav.cell_open(hero.pos,hero.move_class()),"authored river terrain admits the precise authority position")
	var snapshot:=hero.snapshot()
	var replica:=Vector2(snapshot[1],snapshot[2]);hero.pos=replica
	check(replica==Vector2(161,273.1875),"production snapshot reproduces the reported rounded position")
	check(not nav.cell_open(replica,hero.move_class()),"rounded replica lands on the closed side of the native boundary tie")
	var route:=Route.new();route.s=session;route.hero=hero
	var goal:Vector2=route.choose_goal(2)
	check(goal.is_finite(),"route selection handles the snapshot rounding interval")
	check(hero.pos==replica,"route search does not move the replica")
	hero.pos=precise
	check(goal.is_finite() and nav.direct_line(hero,goal,false),"selected leg is clear on the authored terrain from the authority position")
	check(goal.is_finite() and nav.steering_blocker(hero,goal)==null,"selected leg retains actor body sweeps")
	check(goal.is_finite() and not route.reaches_exit(goal),"selected leg retains the authored exit exclusion")
	check(goal.is_finite() and goal.distance_to(precise)>3.0,"regression retains a substantial travel leg")
	# A route selector must also handle a small clear pocket. Its historical
	# 3 m minimum candidate can reject every direction although normal input
	# can still move more than the traversal's required metre.
	var land:=nav.layer(hero.move_class()).land.duplicate()
	var at:=nav.cell(hero.pos)
	for y in range(at.y-40,at.y+41):
		for x in range(at.x-40,at.x+41):
			var cell:=Vector2i(x,y)
			if nav._in(cell) and nav.center(cell).distance_to(precise)>2.25:
				nav.layer(hero.move_class()).land[y*nav.size.x+x]=1
	var short_goal:Vector2=route.choose_goal(2)
	check(short_goal.is_finite(),"a confined clear pocket still supplies a movement leg")
	check(short_goal.is_finite() and short_goal.distance_to(precise)>1.0 and short_goal.distance_to(precise)<3.0,"short candidate retains the actual-movement assertion")
	check(short_goal.is_finite() and nav.direct_line(hero,short_goal,false),"short candidate retains every terrain and slope constraint")
	nav.layer(hero.move_class()).land=land
	hero.pos=replica+Vector2(0.125,0)
	var blocked:=hero.pos
	check(not nav.cell_open(blocked,hero.move_class()),"negative control lies beyond the snapshot rounding interval")
	check(not route.choose_goal(2).is_finite(),"route search does not manufacture an escape from genuinely closed terrain")
	check(hero.pos==blocked,"failed route search also preserves the replica position")
	route.free();game.queue_free();session.queue_free()
	for i in 12:await get_tree().process_frame
	print("PT_ROUTE_ORIGIN ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
