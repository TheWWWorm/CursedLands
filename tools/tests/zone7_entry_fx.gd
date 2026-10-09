extends Node
## Native zone7 arrival dispatch and saved-wait controls, not rendered effects.
const Compat := preload("res://src/game/script/story_compat.gd")
const P := preload("res://src/game/script/script_parser.gd")
const ROOT := "VCheck#0#1"
const WRAPPER := "RemakeGipatArrivalParticles"
var checks := 0
var failures := []
var allocations: Array[Node] = []
var vms: Array[ScriptVM] = []
var raw := ""
var evidence := []

class CaptureSession extends Session:
	var events := []
	func sync_state() -> void: pass
	func broadcast(event: Dictionary) -> void:
		if event.get("t", "") == "fxcmd":
			_track(event)
			events.append(event.duplicate(true))

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)
	return ok

func body(ast: ScriptParser) -> Array:
	return ast.scripts.get(ROOT, {}).get("blocks", [{}])[0].get("body", [])

func admitted(ast: ScriptParser) -> bool:
	return body(ast).any(func(st):return st[0] == P.S_CALL and st[1] == WRAPPER)

func definitions() -> void:
	var original := ScriptParser.parse(raw)
	var current := ScriptParser.parse(raw); Compat.apply(current, CampaignProfile.ASTRAL, "gz7g")
	check(admitted(current), "audited original zone7 arrival admits only the particle wrapper")
	var normalized := current.scripts.duplicate(true)
	for st: Array in normalized[ROOT].blocks[0].body:
		if st[0] == P.S_CALL and st[1] == WRAPPER: st[1] = "CreateParticleSource"
	check(normalized == original.scripts and current.world == original.world, "original definitions, statement counts and startup remain unchanged after wrapper normalization")
	var once := current.scripts.duplicate(true); Compat.apply(current, CampaignProfile.ASTRAL, "gz7g")
	check(current.scripts == once, "compatibility is idempotent")
	for scenario: String in ["missing", "parameter", "condition", "extra_body", "relocation", "first_id", "first_height", "second_id", "second_height", "second_texture", "delay", "continuation", "missing_start", "duplicate_start", "changed_start"]:
		var modified := ScriptParser.parse(raw)
		var b := body(modified)
		match scenario:
			"missing": modified.scripts.erase(ROOT)
			"parameter": modified.scripts[ROOT].params.append("another")
			"condition": modified.scripts[ROOT].blocks[0].conds.append([P.N_NUM,1.0])
			"extra_body": b.append([P.S_CALL,"Nop",[]])
			"relocation": b[3][2][1][1] += 1.0
			"first_id": b[4][2][0][1] = 99.0
			"first_height": b[4][2][3][1] += 1.0
			"second_id": b[5][2][0][1] = 99.0
			"second_height": b[5][2][3][1] += 1.0
			"second_texture": b[5][2][5][1] = "fire"
			"delay": b[6][2][0][1] += 1.0
			"continuation": b[8][1] = "VCheck#1#2"
			"missing_start": modified.world.erase([P.S_CALL,ROOT,[[P.N_VAR,"NULL"]]])
			"duplicate_start": modified.world.append([P.S_CALL,ROOT,[[P.N_VAR,"NULL"]]])
			"changed_start":
				for st: Array in modified.world:
					if st[0] == P.S_CALL and st[1] == ROOT: st[2] = [[P.N_NUM,1.0]]
		Compat.apply(modified, CampaignProfile.ASTRAL, "gz7g")
		check(not admitted(modified), "modified source stays authored: " + scenario)
	for scope: Array in [[CampaignProfile.ORIGINAL,"gz7g"],[CampaignProfile.ASTRAL,"gz19h"],[CampaignProfile.ASTRAL,"gz8g"]]:
		var other := ScriptParser.parse(raw); Compat.apply(other,scope[0],scope[1])
		check(not admitted(other), "other campaign/map scope stays authored: " + str(scope))

func unit(s: CaptureSession, h: Dictionary, owner: int, id: int, point: Vector2) -> GameUnit:
	var u := GameUnit.new(); allocations.append(u); u.world = s.world; u.uid = id; u.controller = owner
	u.info = {"name":h.get("unit_name",h.name),"complexion":h.complexion}; u.proto = {"name":h.prototype}
	u.set_meta("hero",h); u.pos = point; s.world.set_unit(u.uid,u)
	return u

func setup(guests: int) -> CaptureSession:
	var s := CaptureSession.new(); allocations.append(s)
	s.state = CampaignState.new(); s.state.campaign_id = CampaignProfile.ASTRAL
	s.state.ensure_hero(0,"Hero2"); s.state.create_party("Gipat")
	s.state.add_party_unit("Gipat","Hero","Hero3"); s.state.add_party_unit("Gipat","merc2","merc2g"); s.state.set_current_party("Gipat")
	s.world = GameWorld.new(); allocations.append(s.world); s.world.session = s; s.world.zone = {"id":"gz7g"}; s.world.ai = UnitAI.new(s.world)
	unit(s,s.state.heroes[0][0],0,1500000001,Vector2(73.95,206.2))
	unit(s,s.state.heroes[0][1],0,1500000002,Vector2(75.45,206.2))
	for owner in range(1,guests+1):
		s.state.ensure_hero(owner,"Hero3","Guest "+str(owner))
		unit(s,s.state.heroes[owner][0],owner,1500000002+owner,Vector2(77+owner,206+owner))
	s.state.set_var(0,"q.gz7g.q1g",1)
	return s

func vm_for(s: CaptureSession, adapt := true) -> ScriptVM:
	var vm := ScriptVM.new(); vms.append(vm); vm.world = s.world; vm.session = s; s.world.vm = vm
	vm.ast = ScriptParser.parse(raw); vm.briefings = Briefings.new(vm)
	if adapt: Compat.apply(vm.ast,CampaignProfile.ASTRAL,"gz7g")
	for name: String in vm.ast.globals: vm.globals[name] = [] if vm.ast.globals[name] == "group" else null
	return vm

func step(vm: ScriptVM, count: int) -> void:
	for i in count:
		vm._refresh_heroes(); vm.time += ScriptVM.POLL
		var current := vm.instances.duplicate(); current.reverse()
		for inst: ScriptVM.Instance in current: vm._run(inst)
		vm.instances = vm.instances.filter(func(inst):return not inst.killed or not inst.frames.is_empty())

func emit_count(events: Array, point: Vector2) -> int:
	return events.filter(func(event):return event.f == "CreateParticleSource" and is_equal_approx(event.a[1],point.x) and is_equal_approx(event.a[2],point.y)).size()

func replay_roundtrip(s: CaptureSession, label: String) -> Dictionary:
	var events := s.events.duplicate(true)
	var expected_keys := events.map(func(event):return "p%d" % int(event.a[0]))
	var replay: Dictionary = s.world.get_meta("replay")
	check(replay.fx.keys() == expected_keys and replay.fx.values().all(func(value):return value.size() == 1), label + ": each original/negative particle ID has one replay record")
	check(s._replay_events() == events and s._replay_events(true) == events, label + ": join and local replay preserve every particle event exactly")
	s.state.store_zone("gz7g",s.world)
	var path := "user://arrival-" + label.replace("/","-").replace(" ","-") + ".sav"
	var result := s.state.save(path)
	var loaded := CampaignState.load_from(path) if result == OK else null
	check(loaded != null and loaded.zones.gz7g.fx == replay.fx, label + ": real campaign file keeps exact original/negative particle records")
	if loaded == null: return {}
	var restored := CaptureSession.new(); allocations.append(restored); restored.state = loaded
	restored.world = GameWorld.new(); allocations.append(restored.world); restored.world.session = restored; restored.world.zone = {"id":"gz7g"}
	loaded.restore_zone("gz7g",restored.world)
	check(restored._replay_events() == events and restored._replay_events(true) == events, label + ": rebuilt zone replays each saved particle once without allocating IDs")
	return {"keys":expected_keys,"replayed":restored._replay_events(),"saved_fx_auto":loaded.zones.gz7g.vm.fx_auto}

func run_case(guests: int, owner: int, label: String, exclude := false) -> void:
	var s := setup(guests); var vm := vm_for(s); var party := vm._party_records(); var story := vm._story_records()
	var kir: GameUnit = story[0]; var kel: GameUnit = story[1]; kel.controller = owner
	var extras := party.filter(func(u):return not story.has(u))
	if exclude:
		extras[0].dead = true; extras[1].hidden = true
	var before := {}
	for u: GameUnit in party: before[u.uid] = u.pos
	vm._fx_auto = -41
	vm.spawn(ROOT,[null],"WorldScript"); step(vm,1)
	var expected := 2 + extras.filter(func(u):return not u.dead and not u.hidden).size()
	check(s.events.size() == expected, label + ": one entry particle per living original-arrival hero")
	var original_pair := [
		{"t":"fxcmd","f":"CreateParticleSource","a":[1.0,kir.pos.x,kir.pos.y,8.0,1.0,"teleport"]},
		{"t":"fxcmd","f":"CreateParticleSource","a":[2.0,kel.pos.x,kel.pos.y,7.5,1.0,"teleport"]}]
	check(s.events.slice(0,2) == original_pair, label + ": original Kir/Kel effects remain exact and first")
	for u: GameUnit in extras:
		check(emit_count(s.events,u.pos) == (0 if u.dead or u.hidden else 1), label + ": no missing or duplicate effect for guest " + str(u.controller))
	var added: Array = s.events.slice(2)
	var ids := []
	for event: Dictionary in added: ids.append(event.a[0])
	var wanted := []
	for i in expected-2: wanted.append(float(-41-i))
	check(ids == wanted and vm._fx_auto == -41-(expected-2), label + ": unique negative effect IDs consume only the saved allocator")
	check(added.all(func(event):return event.f == "CreateParticleSource" and event.a.slice(3) == [8.0,1.0,"teleport"]), label + ": additional effects retain Kir's authored height/size/type")
	check(kel.pos.is_equal_approx(Vector2(14.4,208)) and party.all(func(u):return u == kel or u.pos == before[u.uid]), label + ": no extra relocation or hero movement")
	var saved := vm.save_state()
	var waits: Array = saved.instances.filter(func(row):return row.s == ROOT)
	check(waits.size() == 1 and waits[0].i == 7 and is_equal_approx(waits[0].w,20*ScriptVM.SLEEP_UNIT), label + ": original Sleep(20) and saved continuation index 7 remain exact")
	var original_events := s.events.duplicate(true)
	var replay := replay_roundtrip(s,label)
	var resumed := vm_for(s); resumed._restore(saved)
	step(resumed,24)
	check(s.events == original_events and resumed._fx_auto == vm._fx_auto, label + ": save/reload resumes without duplicate guest effects or new IDs")
	check(s.state.get_var(0,"q.gz7g.q1g.1") == 1.0 and resumed.instances.any(func(inst):return inst.sname == "VCheck#0#2"), label + ": original route continuation is unchanged")
	# A later arrival is a separate event; this one-shot is not a registrar.
	var late_owner := guests + 1
	s.state.ensure_hero(late_owner,"Hero3","Late")
	unit(s,s.state.heroes[late_owner][0],late_owner,1500000100+late_owner,Vector2(91,209))
	step(resumed,5)
	check(s.events == original_events, label + ": late arrival cannot replay the original entry burst")
	evidence.append({"label":label,"guests":guests,"kel_owner":owner,"events":original_events,"saved_wait":waits,"saved_allocator":saved.fx_auto,"after_resume_allocator":resumed._fx_auto,"replay":replay})

func old_sleep() -> void:
	var s := setup(3); var old := vm_for(s,false); old._fx_auto = -41
	old.spawn(ROOT,[null],"WorldScript"); step(old,1)
	var saved := old.save_state(); var emitted := s.events.duplicate(true)
	var resumed := vm_for(s); resumed._restore(saved); step(resumed,24)
	check(s.events == emitted and emitted.size() == 2 and resumed._fx_auto == -41, "older native save already in Sleep never backfills or repeats entry effects")
	check(s.state.get_var(0,"q.gz7g.q1g.1") == 1.0, "older native sleep continues its original objective")

func _ready() -> void:
	raw = EIMob.load_bytes(GameData.read_file("maps/zone7.mob")).script_text
	check(GameData.campaign_id == CampaignProfile.ASTRAL and raw.sha256_text() == "f2a961fb14df7fc1eb1b9723376372257ec063b326c7bdbbd1423f8ab4785835", "real mounted LiA zone7 source matches the arrival audit")
	definitions()
	run_case(0,0,"solo")
	run_case(3,0,"three guests")
	run_case(3,3,"guest-owned Kel")
	run_case(3,1,"dead/hidden exclusions",true)
	old_sleep()
	for vm: ScriptVM in vms:
		vm.instances.clear(); vm.globals.clear(); vm.briefings = null; vm.world = null; vm.session = null
	for node: Node in allocations:
		if node is GameWorld: node.units = {}; node.vm = null
	for node: Node in allocations: node.free()
	FileAccess.open("user://lia-zone7-entry-fx.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"scope":"Original source/VM particle dispatch, named Gipat roster, controlled ownership/exclusion/late arrival, VM save/restore, campaign disk save/reload and normal Session replay. No rendered particle, ENet, complete chapter or performance claim."},"\t"))
	print("LIA_ZONE7_ENTRY_FX ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
