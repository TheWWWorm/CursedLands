extends Node
## Real LiA routes, occupied destinations and retry windows against the
## pre-optimization reference. Run with an isolated user-data directory.
var checks := 0
var failures := 0
var rows := []
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _run() -> void:
	seed(154117)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.VERY_LOW),true)
	for zone: String in ["bz2h","gz2h"]:
		var session := Session.new();add_child(session)
		var game := Game.new();game.session=session;session.game=game;add_child(game)
		session.state.ensure_hero(0,session._hero_proto(0))
		await session.enter_zone(zone,1,false)
		var world := session.world
		world.set_process(false);world.set_physics_process(false)
		var units := world.unit_rows()
		for i in mini(units.size(),24):
			var unit: GameUnit = units[i*units.size()/mini(units.size(),24)]
			var target: GameUnit = units[(i*17+7)%units.size()]
			for offset in [Vector2.ZERO,Vector2(3.25,-2.75),Vector2(-21.25,18.75)]:
				var to: Vector2 = target.pos+offset
				for retry in [false,true]:
					var path := world.nav.find_path(unit.pos,to,[unit],[],0.0,unit.move_class(),false,NAN,1e6,0.0,retry,to if retry else Vector2.INF)
					var result := {"zone":zone,"uid":unit.uid,"from":str(unit.pos),"to":str(to),"retry":retry,"cells":path.size(),"cell_hash":hash(world.nav.last_cells),"path_hash":hash(path),"blocks":world.nav.last_block_count,"turn_cost":world.nav.last_turn_cost,"end":str(world.nav.last_end)}
					rows.append(result)
		game.queue_free();session.queue_free();await get_tree().process_frame
	var reference_path: String = get_script().resource_path.get_base_dir()+"/fixtures/lia-navigation-paths.json"
	if OS.get_cmdline_user_args().has("--record-nav-reference"):
		DirAccess.make_dir_recursive_absolute(reference_path.get_base_dir())
		FileAccess.open(reference_path,FileAccess.WRITE).store_string(JSON.stringify(rows,"  ")+"\n")
		print("LIA_NAVIGATION_REFERENCE ",rows.size()," routes")
	else:
		var expected: Array = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
		checks+=1
		if rows.size()!=expected.size():failures+=1
		for i in mini(rows.size(),expected.size()):
			checks+=1
			var same: bool=rows[i].size()==expected[i].size()
			for key: String in rows[i]:same=same and rows[i][key]==expected[i].get(key)
			if not same:
				failures+=1
				if failures<12:printerr("FAIL route ",i," got ",rows[i]," expected ",expected[i])
		print("LIA_NAVIGATION_PATHS ",checks," checks ",failures," failures")
	FileAccess.open("user://lia-navigation-paths.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"routes":rows},"  "))
	get_tree().quit(1 if failures else 0)
