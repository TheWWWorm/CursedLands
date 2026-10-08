extends Node
## Real original-data party instruction sequences, package/merge and private
## save roundtrips. Does not pretend to play their surrounding quests.
const OPS := ["CreateParty", "AddUnitToParty", "CopyStats", "CopyItems", "SetCurrentParty", "CopyLoot", "AddLoot", "RemoveUnitFromParty", "FixItems"]
var checks := 0
var failures := 0
var s: Session
var origin: CampaignState
var entry: Dictionary
var vm: ScriptVM
var steps := 0

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_ev: Dictionary) -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func capture(st: CampaignState) -> Dictionary:
	return {"version":1, "current_party":st.current_party, "roster":st.heroes.get(0,[]),
		"parties":st.parties, "money":st.money, "items":st.items, "party_bags":st.party_bags,
		"mercs":st.mercs, "pets":st.pets}.duplicate(true)

func clone(st: CampaignState) -> CampaignState:
	var out := CampaignState.new()
	for key in st.to_dict():
		if key != "version":
			var v: Variant = st.to_dict()[key]
			out.set(key, v.duplicate(true) if v is Dictionary or v is Array else v)
	return out

func transition(mob: String, party: String) -> void:
	var ast := ScriptParser.parse(EIMob.load_bytes(GameData.read_file("maps/" + mob + ".mob")).script_text)
	var body: Array = []
	for script: Dictionary in ast.scripts.values():
		for block: Dictionary in script.blocks:
			if block.body.any(func(stmt): return stmt[0] == ScriptParser.S_CALL and stmt[1] == "SetCurrentParty" and stmt[2][1][1] == party):
				body = block.body
				break
		if not body.is_empty(): break
	check(not body.is_empty(), "original " + mob + " contains transition to " + party)
	for stmt: Array in body:
		if stmt[0] == ScriptParser.S_CALL and stmt[1] in OPS:
			vm._call(stmt[1], stmt[2], ScriptVM.Instance.new())
	check(s.state.current_party == party, "authority selects authored " + party)

func checkpoint(party: String, unit: String, prototype: String) -> CampaignState:
	steps += 1
	s.zone_id = {"FPrison":"bz1h", "FSusel":"bz2h", "Shaina":"gz2h", "Gipat":"gz7g", "HeroAlone":"bz13h", "Pretty":"gz15h", "JunParty":"bz7g"}.get(party, "gz15h")
	var host_before := s.state.to_dict().duplicate(true)
	var original_before := origin.to_dict().duplicate(true)
	var pkg := s.coop.package(entry)
	check(pkg.get("party_context", {}).get("current_party", "missing") == party, "package contains chapter " + party)
	var recipient := clone(origin)
	CoopProgress.merge(recipient, pkg)
	check(recipient.current_party == party, "guest resumes chapter " + party)
	var roster: Array = recipient.heroes.get(0, [])
	check(not roster.is_empty() and roster[0].get("unit_name", "Hero") == unit and roster[0].prototype == prototype, "guest deploys authored " + unit + " body")
	check(CoopProgress.main_hero(recipient).str == 31.0 and CoopProgress.main_hero(recipient).name == "Personal Guest", "guest retains personal stats/name")
	check(CoopProgress.main_bag(recipient) == {"money":222,"items":["rune:e1"]}, "guest purse excludes host gold and goods")
	check(s.state.to_dict() == host_before and origin.to_dict() == original_before, "packaging leaves host and origin intact")
	var path := "user://party-context-%d.sav" % steps
	check(recipient.save(path) == OK, "guest chapter saves")
	var resumed := CampaignState.load_from(path)
	check(resumed != null and capture(resumed) == capture(recipient), "guest chapter reloads all party records")
	var first := capture(recipient)
	CoopProgress.merge(recipient, pkg)
	check(capture(recipient) == first, "repeated package does not duplicate bags/dependents")
	return recipient

func _ready() -> void:
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	s = QuietSession.new()
	s.online = true
	s.state = CoopProgress.fresh_state()
	s.state.heroes[0][0].str = 91.0
	s.state.heroes[0][0].name = "Private Host"
	s.state.money = 9000
	s.state.items = ["rune:r1"]
	s.state.ensure_hero(1, "Human Hero", "Network Guest")
	origin = CoopProgress.fresh_state()
	origin.heroes[0][0].str = 31.0
	origin.heroes[0][0].name = "Personal Guest"
	origin.heroes[0][0].pos = Vector2(4,5)
	origin.money = 222
	origin.items = ["rune:e1"]
	s.state.heroes[1][0] = origin.heroes[0][0].duplicate(true)
	s.state.heroes[1][0].pos = Vector2(20,30)
	s.state.heroes[1][0].name = "Network Guest"
	s.coop = CoopProgress.new()
	s.coop.session = s
	s.world = GameWorld.new()
	s.world.session = s
	s.zone_id = "gz2h" if astral else "gz15h"
	vm = ScriptVM.new()
	vm.session = s
	vm.world = s.world
	entry = {"idx":1, "pid":2, "active":true, "in_sync":true, "clean":true, "present":true,
		"hero_in":s.state.heroes[1][0].duplicate(true), "orig_name":"Personal Guest", "seq":0,
		"vars":{}, "visited":{}, "side_quests":{}, "quest_items":{},
		"credits":{"vars":{},"visited":{},"side_quests":{},"quest_items":{},"zones":{}},
		"purse":{"money":222,"items":["rune:e1"]}, "party_context":capture(origin)}
	s.coop.joiners.guest = entry
	if astral:
		transition("bz1h", "FPrison")
		var prison := checkpoint("FPrison", "Hero", "Hero1")
		check(prison.parties.has("") and prison.party_bags.get("",{}).get("money") == 222, "opening personal party and bag wait through prison chapter")
		transition("bz2h", "FSusel")
		var susel := checkpoint("FSusel", "Hero2", "Hero2")
		check(susel.parties.has("FPrison") and susel.party_bags.get("FPrison",{}).get("items") == ["rune:e1"], "prison chapter and personal bag remain waiting")
		# Kel's live record is owned by another peer but is a required story role.
		var kel: Dictionary = s.state.heroes[0][0].duplicate(true)
		kel.merge({"prototype":"merc2", "unit_name":"merc2", "name":"Kel", "merc":2, "controller":2, "party":"FSusel", "str":47.0, "hp":23.0, "body":{"wounds":[1,2]}, "follow":["hero","Network Guest",1]},true)
		s.state.mercs[2] = kel
		transition("bz5h", "Shaina")
		var shaina := checkpoint("Shaina", "merc8", "merc8")
		check(shaina.mercs.get(2,{}).get("controller") == 0 and shaina.mercs.get(2,{}).get("hp") == 23.0, "waiting story companion keeps health and becomes locally owned")
		check(CoopProgress.main_hero(shaina).get("pos") == Vector2(20,30), "temporary substitute retains last protagonist location")
		var waiting: Array = entry.party_context.parties.get("FSusel", [])
		if not waiting.is_empty(): waiting[0].erase("pos")
		var no_position := clone(origin)
		CoopProgress.merge(no_position, s.coop.package(entry))
		check(not waiting.is_empty() and not CoopProgress.main_hero(no_position).has("pos"), "waiting protagonist without a saved position does not inherit substitute-map coordinates")
		transition("bz5h", "FSusel")
		checkpoint("FSusel", "Hero2", "Hero2")
		transition("bz7h", "Gipat")
		var gipat := checkpoint("Gipat", "Hero", "Hero3")
		check(gipat.heroes[0].size() == 2 and gipat.heroes[0][1].unit_name == "merc2" and gipat.heroes[0][1].str == 47.0, "Gipat includes authored Kel with copied progression")
		check(gipat.parties.has("FPrison") and gipat.parties.has("FSusel") and gipat.parties.has("Shaina"), "all prior story parties survive Gipat")
	else:
		transition("bz7g", "HeroAlone")
		checkpoint("HeroAlone", "Hero", "Human Hero Hadagan")
		transition("bz13h", "Pretty")
		var nalo := checkpoint("Pretty", "Nalo", "Human Hadagan Pretty")
		check(nalo.money == 0 and nalo.items.is_empty() and nalo.parties.has("HeroAlone"), "Nalo has an independent bag while Zak waits")
		transition("zone15", "HeroAlone")
		checkpoint("HeroAlone", "Hero", "Human Hero Hadagan")
		transition("bz13h", "")
		var home := checkpoint("", "Hero", "Human Hero")
		check(home.parties.has("Pretty") and home.parties.has("HeroAlone"), "rescue return retains both substitute parties")
		transition("bz7g", "JunParty")
		var jun := checkpoint("JunParty", "JunBoy", "Jun Male Hero")
		check(jun.heroes[0][0].str == 31.0, "Jun disguise does not copy host attributes")
	# Personal pet transfer and dismissal are cumulative, not append-only.
	var pet := {"rec":{"prototype":"Human Hero","name":"Personal pet"},"controller":1,"party":"","hp":17.0,"pos":Vector2(6,7)}
	s.state.pets = [pet, {"rec":{"prototype":"Human Hero","name":"Host pet"},"controller":0}]
	var with_pet := clone(origin)
	CoopProgress.merge(with_pet,s.coop.package(entry))
	check(with_pet.pets.size() == 1 and with_pet.pets[0].controller == 0 and with_pet.pets[0].hp == 17.0, "personal animal keeps body/ownership; host animal stays private")
	# Rejoining with a merged save resets the credit baseline, while keeping
	# the identity of dependents already returned by this same session.
	entry.sid = "context-reconnect"
	entry.seq = 4
	s.coop._pending[72] = {"hero":CoopProgress.main_hero(with_pet), "vars":{}, "visited":{s.zone_id:true},
		"side_quests":{}, "quest_items":{}, "seq":{"context-reconnect":4}, "purse":entry.purse,
		"party_context":capture(with_pet)}
	s.coop.on_hello(72,1,"Guest")
	entry.clean = true
	entry.present = true
	var rebased := clone(with_pet)
	CoopProgress.merge(rebased,s.coop.package(entry))
	check(rebased.pets.size() == 1, "reconnecting from merged save does not duplicate the personal animal")
	check(CoopProgress.main_bag(rebased) == CoopProgress.main_bag(with_pet), "reconnecting from merged save does not add the purse again")
	s.state.pets.clear()
	CoopProgress.merge(with_pet,s.coop.package(entry))
	check(with_pet.pets.is_empty(), "departed personal animal is removed from cumulative package")
	var credited := s.coop.package(entry)
	entry.in_sync = false
	s.zone_id = "gz99unknown"
	var later := s.coop.package(entry)
	check(later.move == credited.move and later.get("party_context", {}) == credited.get("party_context", {}), "later uncredited location keeps the last complete checkpoint")
	var cumulative := clone(origin)
	CoopProgress.merge(cumulative,later)
	check(cumulative.current_party == credited.get("party_context", {}).get("current_party", "missing"), "cumulative package retains chapter when merged from original save")
	entry.in_sync = true
	# A missed party transition cannot move an incompatible origin to the host.
	entry.party_context = capture(origin)
	entry.erase("context_checkpoint")
	entry.clean = false
	var before: Dictionary = entry.party_context.duplicate(true)
	transition("bz13h" if not astral else "bz5h", "Pretty" if not astral else "Shaina")
	check(entry.party_context == before, "uncredited party transition leaves guest context untouched")
	check(s.coop.package(entry).move.is_empty(), "incompatible chapter does not receive a destination")
	var missing := entry.duplicate(true)
	missing.erase("party_context")
	check(s.coop.package(missing).hero.str == 31.0, "legacy tally still returns personal hero progress")
	s.world.free()
	s.coop.free()
	s.free()
	print("COOP_PROGRESS_CONTEXT ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
