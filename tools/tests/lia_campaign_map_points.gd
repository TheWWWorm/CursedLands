extends Node
## Campaign-wide map controls, not a simulated campaign playthrough. Quest and
## travel states here are explicit prepared inputs. The normal map/entrance UI
## and Session command dispatch run unchanged; only final world loading is
## recorded. The loaded-map quest programs separately earn and follow gates.
class MapSession extends Session:
	var loads: Array = []
	var deliveries: Array = []
	func _begin_host_load(id: String, _cancel_movie := true, _saved_mods: Dictionary = {}) -> void:
		loads.append(id); loading_game = true; _load_serial += 1
	func _complete_zone_travel(id: String, entrance: int, serial: int, autosave := true, island_resume: Dictionary = {}) -> void:
		deliveries.append([id,entrance,serial,autosave,island_resume])

var s: MapSession
var w: GameWorld
var h: GameUnit
var checks := 0
var failures: Array[String] = []
var evidence: Array = []
var inventory: Dictionary
var tested_exits := 0
var tested_routes := 0
var tested_markers := 0
var tested_pieces := 0
var tested_settlements := 0
func missing_maps() -> Array: return ["mov1","cz3h","cz4h","gz17g","bz15g"]
func unused_edges() -> Array: return ["gz21k_gz23dk"]
func marker_fixture() -> String: return "res://tools/tests/fixtures/lia_campaign_quest_markers.json"
func result_marker() -> String: return "LIA_CAMPAIGN_MAP_POINTS"
func campaign_name() -> String: return "LiA"
func starting_areas() -> int: return 0
func scripted_only_maps() -> Array: return []

func check(ok: bool, label: String) -> bool:
	checks += 1
	evidence.append({"ok":ok,"label":label})
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
	return ok

func _ready() -> void: run.call_deferred()

func frame() -> void: await get_tree().process_frame

func available(id: String) -> bool:
	var z := s.campaign.zone(id)
	return GameFiles.exists(GameData.root.path_join("maps/%s.mpr"%z.get("mpr",""))) \
		and GameFiles.exists(GameData.root.path_join("maps/%s.mob"%z.get("mob","")))

func prepare() -> void:
	s.loading_game = false
	s.travel_options.clear()
	s.loads.clear(); s.deliveries.clear()
	s.state.vars.clear()
	if starting_areas(): s.state.visited["gz1g"] = true
	s.state.set_var(0,"i.nocamp",1)
	for z: Dictionary in s.campaign.zones.values():
		s.state.set_var(0,"z."+z.id,2 if z.type == "edge" or available(z.id) else 1)

func exit_geometry() -> void:
	var missing: Array[String] = []
	for z: Dictionary in s.campaign.zones.values():
		if z.type == "edge": continue
		if not available(z.id): missing.append(z.id); continue
		w.zone = z; s.zone_id = z.id
		for number: int in z.exits:
			var ex: Dictionary = z.exits[number]
			if ex.get("to","none") == "none":
				check(not s._exit_is_open(number),"%s:%d entrance-only record cannot be used as an exit"%[z.id,number])
				continue
			tested_exits += 1
			var label := "%s:%d → %s"%[z.id,number,ex.to]
			if not check(ex.has("remove") and ex.has("deploy"),label+" has authored trigger and arrival rectangles"): continue
			var point: Vector2 = ex.remove.get_center()
			check(ex.remove.has_area() and point.is_finite(),label+" trigger has finite nonzero area")
			check(not s.campaign.zone(ex.to).is_empty(),label+" destination is defined")
			for state: int in [0,1,2]:
				s.state.set_var(0,"z."+ex.to,state)
				check(s._exit_is_open(number) == (state != 1),label+" respects prepared gate "+str(state))
				check((s.open_exit_at(point,0) >= 0) == (state != 1),label+" ground picking respects prepared gate "+str(state))
				s._arm_exit(0,point,true,number)
				check((s._leave_armed == number) == (state != 1),label+" deliberate exit selection respects gate "+str(state))
				s._arm_exit(0,point,false,number)
				check(s._leave_armed < 0,label+" requires selected party units")
			# Generic geometry has no loaded MOB, so the exact-source cellar
			# exception deliberately does not apply. Its loaded test covers it.
			s.state.set_var(0,"z."+ex.to,2)
			var objectives := ZoneObjectives.new()
			objectives.setup(s,z.id,[],true,"field"); add_child(objectives)
			var arrow := objectives.entrances.filter(func(e):return e.n == number)
			check(arrow.size() == 1 and arrow[0].ok,label+" field map exposes the opened exit arrow")
			objectives.free()
	missing.sort()
	var expected: Array = missing_maps().duplicate(); expected.sort()
	check(missing == expected,"missing authored assets match the explicitly classified dormant map records")

func edge_routes() -> void:
	for edge: Dictionary in s.campaign.zones.values():
		if edge.type != "edge": continue
		if unused_edges().has(edge.id):
			check(not s.campaign.zones.values().any(func(z):return z.exits.values().any(func(ex):return ex.get("to","") == edge.id)),
				edge.id+" has no authored incoming passage; excluded from reachable map choices")
			continue
		prepare()
		# Adjacent regions begin unseen. Entering this edge must reveal them
		# without revealing an unrelated region or unlocking a settlement.
		for ex: Dictionary in edge.exits.values():
			if s.campaign.zone(ex.to).get("type","") == "game": s.state.set_var(0,"z."+ex.to,0)
		s.leave_zone(edge.id,1)
		check(s.map_open and not s.travel_options.is_empty(),edge.id+" opens usable map choices")
		for ex: Dictionary in edge.exits.values():
			var to := s.campaign.zone(ex.to)
			if to.get("type","") != "game" or not available(to.id): continue
			check(s.state.get_var(0,"z."+to.id) == 1,edge.id+" reveals adjacent region "+to.id)
			check(s.travel_options.any(func(o):return o.zone == to.id and int(o.entrance) == int(ex.to_exit)),
				edge.id+" offers authored adjacent entrance "+to.id+":"+str(ex.to_exit))
		var offered := s.travel_options.duplicate(true)
		for option: Dictionary in offered:
			tested_routes += 1
			var label: String = edge.id+" → "+str(option.zone)+":"+str(option.entrance)
			var dest := s.campaign.zone(option.zone)
			check(available(option.zone),label+" has both required map assets")
			check(dest.exits.has(int(option.entrance)) and dest.exits[int(option.entrance)].has("deploy"),label+" resolves an authored arrival")
			# Exercises the actual entrance arrow and confirmation action.
			var panel := ZoneObjectives.new()
			panel.setup(s,option.zone,offered,true)
			panel.confirmed.connect(func(o):s.apply_command({"t":"travel","zone":o.zone,"entrance":o.entrance},0))
			add_child(panel)
			var index := -1
			for i in panel.entrances.size():
				if panel.entrances[i].n == int(option.entrance): index = i
			if check(index >= 0,label+" has an objective-map arrow"):
				s.loading_game = false; s.travel_options = offered.duplicate(true)
				s.loads.clear(); s.deliveries.clear()
				panel.press(["entrance",index]); panel.press(["ok"])
				await frame()
				check(s.loads == [option.zone] and s.deliveries.size() == 1,label+" confirmation reaches exactly one load")
				if not s.deliveries.is_empty(): check(s.deliveries[0][1] == int(option.entrance),label+" keeps the selected arrival")
				panel.press(["ok"]); await frame()
				check(s.loads.size() == 1,label+" duplicate confirmation cannot load twice")
			panel.free()
		# Closed/unoffered entrance controls must not create a route.
		s.loading_game = false; s.travel_options.clear(); s.loads.clear()
		s.apply_command({"t":"travel","zone":"gz36j","entrance":9999},0)
		check(s.loads.is_empty(),edge.id+" rejects an unoffered destination and entrance")

func pick_piece(map: TravelMap, index: int) -> Vector2:
	var rect := map._screen_rect(map._pieces[index].node)
	for angle in [0.0,0.7,1.4,2.1,2.8,3.5,4.2,4.9,5.6]:
		map.angle = angle; map._update_pivot()
		rect = map._screen_rect(map._pieces[index].node)
		for yy in range(1,10):
			for xx in range(1,10):
				var p := rect.position+rect.size*Vector2(xx/10.0,yy/10.0)
				if map.get_rect().has_point(p) and map._button_at(p) < 0 and map._piece_at(p) == index: return p
	return Vector2.INF

func map_points() -> void:
	for allod: String in s.campaign.allods:
		prepare()
		var edge := ""
		for z: Dictionary in s.campaign.zones.values():
			if z.allod == allod and z.type == "edge": edge = z.id; break
		if not check(not edge.is_empty(),allod+" has a travel graph entry"): continue
		for zone: String in inventory.zones:
			if s.campaign.zone(zone).get("allod","") != allod: continue
			for quest: String in inventory.zones[zone]: s.state.set_var(0,"q."+zone+"."+quest,1)
		# Prepared complete regions let all reachable route controls be exercised.
		s.leave_zone(edge,1)
		var map := TravelMap.new()
		map.setup(s,s.travel_options,true,edge,s.start_zones_shown()); add_child(map)
		await frame(); await frame()
		for i in map._pieces.size():
			var piece: Dictionary = map._pieces[i]
			if not available(piece.id): continue
			tested_pieces += 1
			if scripted_only_maps().has(piece.id):
				check(not s.travel_options.any(func(o):return o.zone == piece.id),piece.id+" is reached by story transfer, never an invented map route")
			else:
				var p := pick_piece(map,i)
				if check(p.is_finite(),piece.id+" island piece is reachable by a ground pointer"):
					var got := []
					var receive := func(o):got.append(o)
					map.picked.connect(receive)
					map._on_press(p)
					if map._link and piece.link >= 0 and not map._separate_brief(i):
						check(got.size() == 1 and got[0].zone == map._briefs[piece.link].id,piece.id+" linked village piece selects its authored settlement")
					else:
						check(map.objectives != null and map.objectives.zone == piece.id,piece.id+" pointer opens the matching map objectives")
					map.picked.disconnect(receive)
					map.close_objectives(); await frame()
			var quests: Array = inventory.zones.get(piece.id,[])
			check(piece.quests.size() == quests.size(),piece.id+" exposes every prepared active quest marker")
			var panel := map.open_objectives(piece.id)
			for q: String in quests:
				tested_markers += 1
				var idx := panel.quests.find(q)
				if not check(idx >= 0,piece.id+" journal includes "+q): continue
				panel.press(["row",idx])
				check(panel.sel == idx,piece.id+" quest point selects "+q)
				check(panel._areas.size() == s.campaign.quest_areas.get(q,PackedVector2Array()).size(),piece.id+" quest point areas match original map for "+q)
				s.state.set_var(0,"q."+piece.id+"."+q,2)
			map.close_objectives(); await frame()
			check(map._quests_of(piece.id,"","").is_empty(),piece.id+" completed quests no longer draw active map markers")
		for i in map._briefs.size():
			var brief: Dictionary = map._briefs[i]
			if map._offer(brief.id).is_empty(): continue
			tested_settlements += 1
			var got := []
			var receive := func(o):got.append(o)
			map.picked.connect(receive)
			map._on_press(map._screen_rect(brief.node).get_center())
			check(got.size() == 1 and got[0].zone == brief.id,brief.id+" settlement map point chooses its offered route")
			map.picked.disconnect(receive)
		map.free()

func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TutorialPanel.auto_show = false
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_exit":0,"start_zones":starting_areas(),"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	s = MapSession.new(); add_child(s); s.set_physics_process(false)
	w = GameWorld.new(); w.session = s; w.presentation = false; s.world = w
	h = GameUnit.new(); h.uid = 1; h.controller = 0; h.set_meta("hero",{"name":"Map checkpoint"}); w.set_unit(h.uid,h)
	inventory = JSON.parse_string(FileAccess.get_file_as_string(marker_fixture()))
	prepare(); exit_geometry()
	await edge_routes()
	await map_points()
	var report := {"checks":checks,"failures":failures,"assertions":evidence,"exits":tested_exits,"route_choices":tested_routes,
		"quest_markers":tested_markers,"island_pieces":tested_pieces,"settlement_points":tested_settlements,
		"scope":"All authored available "+campaign_name()+" map records: prepared gates, exit geometry, ordinary entrance controls, map ray picking and quest points. Final load boundary recorded, not full scene traversal or earned story-state proof."}
	FileAccess.open("user://"+result_marker().to_lower()+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	s.world = null; w.units = {}; h.free(); w.free(); s.free()
	await frame(); TexUpscale.shutdown()
	print(result_marker()," ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
