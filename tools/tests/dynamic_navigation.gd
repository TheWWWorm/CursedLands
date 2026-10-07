extends Node
## Run with original Lost in Astral content. Compare complete planner outputs
## across a real lever footprint change and live actor occupancy changes.
const Blocks := preload("res://src/game/nav_blocks.gd")
const DOOR := 1032949
const A := Vector2(27.89964,93.33531)
const B := Vector2(27.89964,89.33531)
var checks := 0
var failures := 0
var session: Session
var game: Game
var hero: GameUnit
var nav: NavGrid

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func route(from: Vector2, to: Vector2) -> Dictionary:
	var path := nav.find_path(from,to,[hero],[],0.0,hero.move_class(),false,hero.facing)
	return {"path":path,"cells":nav.last_cells,"end":nav.last_end,
		"blocks":nav.last_block_count,"turn":nav.last_turn_cost}

func compare(label: String, pairs: Array) -> void:
	var cls := hero.move_class()
	var native = Blocks.new(nav,nav.layer(cls))
	var scalar = Blocks.new(nav,nav.layer(cls))
	scalar._native_topology = false
	check(native._native_topology,label+" native topology available")
	for pair: Array in pairs:
		nav._native_graphs[cls] = native
		var actual := route(pair[0],pair[1])
		nav._native_graphs[cls] = scalar
		var expected := route(pair[0],pair[1])
		check(actual == expected,label+" complete path "+str(pair))
		check(native.route(nav.cell(pair[0]),nav.cell(pair[1])) == scalar.route(nav.cell(pair[0]),nav.cell(pair[1])),label+" static block route")
	nav._native_graphs[cls] = native
	check(native._links.is_empty() and native._edges8.is_empty(),label+" native graph avoids script edge allocation")

func _ready() -> void:
	GameData.options.merge({"net_upnp":0,"net_directory":0,"net_lan":0,"autosave":0,"show_tutorial":0},true)
	session = Session.new(); add_child(session)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.state = CampaignState.new()
	session.state.ensure_hero(0,session._hero_proto(0))
	await session.enter_zone("gz1d2",1,false)
	var w := session.world
	w.set_process(false); w.set_physics_process(false); session.set_physics_process(false)
	hero = session.party_units(0)[0]
	nav = w.nav
	nav.path_memo = false
	hero.pos = A
	var pairs: Array = [[A,B],[B,A]]
	for u: GameUnit in w.unit_rows():
		if u != hero and u.pos.distance_to(A) > 15.0:
			pairs.append([A,u.pos]); pairs.append([u.pos,A])
			if pairs.size() >= 10: break
	check(pairs.size() >= 6,"long routes exercise the block planner")
	var previous = nav.native_graph(nav.layer(hero.move_class()))
	for state in [1,0,1,0]:
		var rev := nav.map_rev
		w.lever_sys.set_state(DOOR,state,0)
		check(nav.map_rev > rev,"door changes live map revision "+str(state))
		var current = nav.native_graph(nav.layer(hero.move_class()))
		check(current != previous,"door replaces cached graph "+str(state))
		compare("door "+str(state),pairs)
		previous = nav.native_graph(nav.layer(hero.move_class()))
	var blocker: GameUnit = w.units[105543]
	var old_pos := blocker.pos
	var rev := nav.map_rev
	for point in [A+Vector2(0,-1),B,old_pos]:
		blocker.pos = point
		nav.track_unit(blocker)
		check(nav.map_rev == rev,"moving actor keeps static revision")
		check(nav.native_graph(nav.layer(hero.move_class())) == previous,"moving actor retains static records")
		compare("occupancy "+str(point),pairs.slice(0,4))
		previous = nav.native_graph(nav.layer(hero.move_class()))
	print("DYNAMIC_NAVIGATION ",checks," checks ",failures," failures")
	w.queue_free(); session.world = null; game.world = null
	game.queue_free(); session.queue_free()
	for i in 5: await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
