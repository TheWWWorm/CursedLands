extends Node
const Grants := preload("res://src/game/script/camp_grants.gd")
var checks := 0
var failures := 0

class ProbeSession extends Session:
	var refreshed: Array = []
	func _refresh_character(u: GameUnit, _h: Dictionary) -> void: refreshed.append(u.uid)
	func broadcast(_event: Dictionary) -> void: pass
	func sync_state() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func actor(w: GameWorld, id: int, owner: int, h: Dictionary) -> GameUnit:
	var u := GameUnit.new()
	u.uid = id
	u.world = w
	u.controller = owner
	u.info = {"complexion":h.complexion}
	u.set_meta("hero",h)
	w.set_unit(id, u)
	return u

func _ready() -> void:
	check(GameData.campaign_id == CampaignProfile.ASTRAL,"runs with original LiA content")
	var mob := EIMob.load_bytes(GameData.read_file("maps/bz1h.mob"))
	for branch: String in ["a","b","c","d","e","f"]:
		var s := ProbeSession.new()
		var w := GameWorld.new()
		s.world = w
		s.online = true
		s.state = CampaignState.new()
		w.session = s
		w.zone = {"id":"bz1h","type":"brief"}
		s.state.ensure_hero(0,"Human Hero")
		s.state.ensure_hero(1,"Human Hero","Guest")
		s.state.ensure_hero(2,"Human Hero","Disconnected")
		var host: Dictionary = s.state.heroes[0][0]
		var guest: Dictionary = s.state.heroes[1][0]
		# Existing character development and body build must survive the gift.
		guest.str = 31.0; guest.dex = 37.0; guest.int = 29.0
		guest.skills.science = 42
		guest.complexion = Vector3(.3,.4,.6)
		var old := guest.duplicate(true)
		var main := actor(w,1500000001,0,host)
		var joiner := actor(w,1500000002,1,guest)
		var kel_record := host.duplicate(true)
		kel_record.merc = 2
		var kel := actor(w,ScriptVM.name_id("merc2"),1,kel_record)
		s.state.mercs[2] = kel_record
		var vm := ScriptVM.new()
		vm.world = w; vm.session = s; w.vm = vm
		vm.ast = ScriptParser.parse(mob.script_text)
		s.state.set_var(0,"b.Clerk.brief_3"+branch,2)
		var script := "VCheck#0#%d" % (["a","b","c","d","e","f"].find(branch)+2)
		vm.spawn(script,[null])
		vm._run(vm.instances[-1])
		for key: String in ["str","dex","int"]:
			check(float(guest[key])-float(old[key]) == float(host[key])-25.0, branch+" guest receives Kir delta "+key)
		check(int(guest.skills.science) == 42+int(Grants.HERO[branch].get("science",0)),branch+" paid skills preserved")
		check(guest.complexion.z == old.complexion.z,branch+" body height preserved")
		check(s.refreshed.has(main.uid) and s.refreshed.has(joiner.uid) and s.refreshed.has(kel.uid),branch+" live recipients refresh")
		check(guest[Grants.KEY].role == "hero" and kel_record[Grants.KEY].role == "kel",branch+" companion ownership does not remap role")
		for key: String in Grants.KEL[branch]:
			check(kel_record[Grants.KEY].effects.has(key),branch+" Kel gets authored "+key)
		check(s.state.heroes[2][0][Grants.KEY] == host[Grants.KEY],branch+" absent guest retains grant")
		var finished := guest.duplicate(true)
		vm.spawn(script,[null]); vm._run(vm.instances[-1])
		check(guest == finished,branch+" replay cannot apply twice")
		check(not Grants.catch_up(s.state,1),branch+" reconnect cannot duplicate grant")
		var sanitized := CoopProgress.sanitize_hero(guest)
		check(sanitized[Grants.KEY] == guest[Grants.KEY],branch+" receipt survives bring/merge sanitizer")
		check(s.state.save("user://camp-"+branch+".sav") == OK,branch+" saves")
		var loaded := CampaignState.load_from("user://camp-"+branch+".sav")
		check(loaded.heroes[1][0] == guest,branch+" reload preserves full record")
		check(not Grants.catch_up(loaded,1),branch+" reload cannot duplicate grant")
		loaded.ensure_hero(3,"Human Hero","Late")
		check(Grants.catch_up(loaded,3),branch+" late fresh guest receives known choice")
		check(not Grants.catch_up(loaded,3),branch+" late guest receives choice once")
		loaded.ensure_hero(4,"Human Hero","Ambiguous")
		loaded.heroes[4][0].str = 26.0
		check(not Grants.catch_up(loaded,4),branch+" modified legacy record is not guessed")
		loaded.ensure_hero(5,"Human Hero","Unknown")
		loaded.set_var(0,"b.Clerk.brief_3"+("b" if branch=="a" else "a"),2)
		check(not Grants.catch_up(loaded,5),branch+" ambiguous story choice is not guessed")
		w.units = {}
		main.free(); joiner.free(); kel.free(); w.free(); s.free()
	print("CAMP_GRANTS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
