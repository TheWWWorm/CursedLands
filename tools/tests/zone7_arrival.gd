extends Node
## Actual mounted LiA entry/navigation; isolated original q1g script chain.
## Controlled owners are not ENet peers. All unrelated simulation is paused.
const Compat := preload("res://src/game/script/story_compat.gd")
const FAMILY := ["VCheck#0#1", "VCheck#0#2", "VCheck#0#3"]
var checks := 0
var failures := []
var s: AuditSession
var game: Game
var evidence := {}

class AuditSession extends Session:
	var portal_fx := []
	func broadcast(event: Dictionary) -> void:
		if event.get("t", "") == "fxcmd" and event.get("f", "") == "CreateParticleSource":
			_track(event); portal_fx.append(event.duplicate(true)); return
		super.broadcast(event)

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)
	return ok

func digest(data: PackedByteArray) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(data)
	return hash.finish().hex_encode()

func xy(p: Vector2) -> Array:
	return [p.x, p.y]

func ticks(count: int, allow_world := false) -> void:
	var vm := s.world.vm
	for i in count:
		vm.instances = vm.instances.filter(func(inst): return inst.sname in FAMILY or allow_world and inst.sname == "WorldScript")
		vm.tick(ScriptVM.POLL)

func role(vm: ScriptVM, slot: int):
	return vm._call("GetUnitOfPlayer", [[ScriptParser.N_NUM, 0.0], [ScriptParser.N_NUM, float(slot)]], ScriptVM.Instance.new())

func rows(units: Array) -> Array:
	return units.map(func(unit): return {"uid":unit.uid, "owner":unit.controller, "name":unit.info.get("name", ""), "pos":xy(unit.pos)})

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	if not check(GameData.campaign_id == CampaignProfile.ASTRAL and SaveInfo.files().is_empty(), "isolated mounted LiA profile"):
		await finish(); return
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"auto_graphics":0, "autosave":0, "show_tutorial":0, "net_upnp":0, "net_lan":0, "net_directory":0, "confine_mouse":0, "control_mode":1}, true)
	TutorialPanel.auto_show = false
	var mob_bytes := GameData.read_file("maps/zone7.mob")
	var mob := EIMob.load_bytes(mob_bytes)
	var raw := ScriptParser.parse(mob.script_text)
	var adapted := ScriptParser.parse(mob.script_text); Compat.apply(adapted, CampaignProfile.ASTRAL, "gz7g")
	check(raw.errors.is_empty() and adapted.errors.is_empty(), "mounted original zone7 source parses")
	var normalized := adapted.scripts.duplicate(true)
	var second: Array = normalized[FAMILY[0]].blocks[0].body[5]
	check(second[1] == "RemakeGipatArrivalParticles", "original arrival source admits the bounded guest particle hook")
	if second[1] == "RemakeGipatArrivalParticles": second[1] = "CreateParticleSource"
	check(raw.scripts == normalized and raw.world == adapted.world, "all zone7 definitions stay exact after normalizing the single particle hook")
	var previous := EIMob.load_bytes(GameData.read_file("maps/bz7h.mob"))
	var ast_previous := ScriptParser.parse(previous.script_text)
	var transitions := []
	for block: Dictionary in ast_previous.scripts["#OnBriefingComplete"].blocks:
		if block.body.has([ScriptParser.S_CALL, "LeaveToZone", [[ScriptParser.N_NUM,0.0], [ScriptParser.N_STR,"gz7g"], [ScriptParser.N_NUM,5.0]]]): transitions.append(block)
	check(transitions.size() == 2, "both original Sergeant outcomes enter gz7g through zero-based exit 5")
	evidence.source = {"zone7_mob_sha256":digest(mob_bytes), "zone7_script_sha256":mob.script_text.sha256_text(), "bz7h_script_sha256":previous.script_text.sha256_text(), "entry_handlers":transitions, "arrival_family":FAMILY.map(func(name): return {"name":name, "definition":raw.scripts[name]}), "quest_text":GameData.text("quest q1g"), "quest_db":GameData.db.find("quests", "q1g")}
	FileAccess.open("user://zone7.txt", FileAccess.WRITE).store_string(mob.script_text)
	FileAccess.open("user://bz7h.txt", FileAccess.WRITE).store_string(previous.script_text)
	s = AuditSession.new(); add_child(s); s.set_physics_process(false)
	game = Game.new(); game.session = s; s.game = game; add_child(game)
	s.state.ensure_hero(0, "Hero2")
	s.state.create_party("Gipat"); s.state.add_party_unit("Gipat", "Hero", "Hero3"); s.state.add_party_unit("Gipat", "merc2", "merc2g"); s.state.set_current_party("Gipat")
	for owner in range(1,4):
		s.players[40 + owner] = {"index":owner, "name":"Guest " + str(owner), "colour":owner+1}
		s.state.ensure_hero(owner, "Hero3", "Guest " + str(owner))
	s.state.set_var(0, "q.gz7g.q1g", 1)
	s._enter_zone("gz7g", 6, false)
	s.world.set_process(false); s.world.set_physics_process(false); game.rig.set_process(false)
	var w := s.world; var vm := w.vm
	var party := vm._party_records()
	var story := vm._story_records()
	if not check(s.zone_id == "gz7g" and story.size() == 2 and party.size() == 5, "actual arrival deploys Kir, named Kel and three extra heroes"):
		await finish(); return
	var kir: GameUnit = story[0]; var kel: GameUnit = story[1]
	check(kir.get_meta("hero").prototype == "Hero3" and kel.get_meta("hero").prototype == "merc2g", "active Gipat roster uses authored Kir and Kel records")
	var initial := rows(party)
	var at := {}
	for unit: GameUnit in party: at[unit.uid] = unit.pos
	ticks(5, true)
	check(kel.pos.is_equal_approx(Vector2(14.4,208)), "original startup places Kel at the fixed story mark")
	check(party.all(func(unit): return unit == kel or unit.pos == at[unit.uid]), "Kir and every extra hero retain their actual entrance positions")
	check(role(vm,1) == kel, "original indexed relocation still resolves the named companion")
	var original_pair := [
		{"t":"fxcmd","f":"CreateParticleSource","a":[1.0,kir.pos.x,kir.pos.y,8.0,1.0,"teleport"]},
		{"t":"fxcmd","f":"CreateParticleSource","a":[2.0,kel.pos.x,kel.pos.y,7.5,1.0,"teleport"]}]
	check(s.portal_fx.slice(0,2) == original_pair, "actual startup preserves both authored particles exactly and first")
	check(s.portal_fx.size() == 5, "actual startup emits one additional particle for each extra arrival hero")
	var extra_ids := []
	for event: Dictionary in s.portal_fx.slice(2): extra_ids.append(event.a[0])
	check(extra_ids == [-1.0,-2.0,-3.0] and vm._fx_auto == -4, "actual startup uses the default saved negative allocator without colliding with original IDs")
	for unit: GameUnit in party.filter(func(u):return u != kir and u != kel):
		check(s.portal_fx.filter(func(event):return event.a[1] == unit.pos.x and event.a[2] == unit.pos.y and event.a.slice(3) == [8.0,1.0,"teleport"]).size() == 1, "actual guest %d receives exactly one effect at its entrance point" % unit.controller)
	var replay: Array = s._replay_events().filter(func(event):return event.get("t","") == "fxcmd" and event.get("f","") == "CreateParticleSource")
	check(replay == s.portal_fx, "actual zone replay retains each original and guest portal event once")
	evidence.arrival = {"map_deploy":str(w.zone.exits[6].deploy), "before":initial, "after":rows(party), "portal_fx":s.portal_fx.duplicate(true)}
	# This map's named-party companion is in heroes[0], not the hireable mercs
	# dictionary used by some older roster probes. Exercise that exact form.
	var owner_cases := []
	for owner in [1,3,0]:
		kel.controller = owner; kel.pos = at[kel.uid]
		vm.instances.clear(); vm.spawn(FAMILY[0], [null]); s.portal_fx.clear()
		ticks(1)
		check(role(vm,1) == kel and kel.pos.is_equal_approx(Vector2(14.4,208)), "Kel remains the moved story role under controller %d" % owner)
		check(party.all(func(unit): return unit == kel or unit.pos == at[unit.uid]), "owner %d does not redirect SetCP to a guest" % owner)
		owner_cases.append({"owner":owner, "story_ids":vm._story_records().map(func(unit):return unit.uid), "party_ids":vm._party_records().map(func(unit):return unit.uid), "portal_fx":s.portal_fx.duplicate(true)})
	evidence.owner_cases = owner_cases
	# Static map-route observations are not equivalent to walking the route.
	var ignored: Array = w.units.values()
	var waypoint := w.nav.nearest_walkable(Vector2(129.5,270), 10, kir.move_class())
	var destination := w.nav.nearest_walkable(Vector2(210.5,311), 10, kir.move_class())
	check(waypoint.distance_to(Vector2(129.5,270)) < 5.0 and Rect2(204,304,13,14).has_point(destination), "route probes target walkable points inside both native quest areas")
	var routes := []
	for unit: GameUnit in party:
		var path := w.nav.find_path(unit.pos, waypoint, ignored, [], maxf(0.0,unit.body_radius()-NavGrid.R_REF),unit.move_class(),true)
		routes.append({"uid":unit.uid, "from":xy(unit.pos), "to":xy(waypoint), "points":path.size(), "end":xy(path[-1]) if not path.is_empty() else [], "class":unit.move_class()})
	var onwards := w.nav.find_path(waypoint,destination,ignored,[],maxf(0.0,kir.body_radius()-NavGrid.R_REF),kir.move_class(),true)
	evidence.navigation = {"ignored_actors":ignored.size(), "entrance_to_first_area":routes, "waypoint_to_finish":{"from":xy(waypoint), "to":xy(destination), "points":onwards.size(), "end":xy(onwards[-1]) if not onwards.is_empty() else []}}
	print("ZONE7_NAV ",JSON.stringify(evidence.navigation))
	# Only this q1g chain advances; arrival positions above remain recorded.
	# Any/Every use the live Heroes group, so require proof that an extra hero
	# can discover the route and that one left outside still delays completion.
	ticks(22)
	check(s.state.get_var(0,"q.gz7g.q1g.1") == 1.0, "original 20-tick arrival wait opens the first q1g objective")
	var extra: Array = party.filter(func(unit):return unit != kir and unit != kel)
	extra[0].pos = waypoint; ticks(3)
	check(s.state.get_var(0,"q.gz7g.q1g.1") == 2.0 and s.state.get_var(0,"q.gz7g.q1g.2") == 1.0, "an extra participant alone satisfies native first-area Any")
	for unit: GameUnit in party: unit.pos = destination
	extra[-1].pos = waypoint; ticks(3)
	check(s.state.get_var(0,"q.gz7g.q1g") == 1.0, "native final Every waits while one extra participant remains outside")
	extra[-1].pos = destination; ticks(3)
	check(s.state.get_var(0,"q.gz7g.q1g") == 2.0 and s.state.get_var(0,"b.bz8g.brief_101") == 1.0, "native q1g completes once every current participant reaches its authored area")
	check(vm.unknown_calls.is_empty(), "arrival and route family has no unresolved calls")
	await finish()

func finish() -> void:
	if s and s.world:
		s.world.vm.instances.clear()
	if game: game.queue_free()
	if s: s.queue_free()
	for i in 10: await get_tree().process_frame
	TexUpscale.shutdown()
	FileAccess.open("user://lia-zone7-arrival.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "evidence":evidence, "limits":"Actual headless LiA map and native entry/q1g definitions. Controlled player rosters, no network peers. Other AI/story threads paused. Static navigation queries ignore actor stamps. Quest-area checks use prepared positions; no full walking route. Portal particle dispatch is recorded, not rendered."}, "\t"))
	print("LIA_ZONE7_ARRIVAL ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
