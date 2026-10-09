extends Node
## Campaign transfer eligibility without inventing z.<destination> unlocks.
## The ENet chapter fixture separately loads/deploys the returned saves.
var checks := 0
var failures := 0
var s: Session
var destination := "gz1h"

class QuietProgress extends CoopProgress:
	func send_all() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func entry() -> Dictionary:
	var st := CoopProgress.fresh_state()
	return {"active":true, "idx":1, "pid":2, "in_sync":true, "clean":true, "present":true,
		"orig_name":"Travel Guest", "hero_in":st.heroes[0][0], "purse":{"money":222,"items":[]},
		"vars":{}, "visited":{}, "side_quests":{}, "quest_items":{},
		"credits":{"vars":{},"visited":{},"side_quests":{},"quest_items":{},"zones":{}},
		"party_context":CoopProgress.PartyProgress.capture(st)}

func travel(e: Dictionary, loading := false) -> Dictionary:
	s.coop.joiners = {"guest":e}
	s.coop._zone = "bz1h" if GameData.campaign_id == CampaignProfile.ASTRAL else "gz1g"
	s.coop._loading = loading
	s.zone_id = destination
	s.coop.zone_entered(destination)
	return s.coop.package(e)

func _ready() -> void:
	s = Session.new()
	s.state = CoopProgress.fresh_state()
	s.state.heroes[1] = s.state.heroes[0].duplicate(true)
	s.state.heroes[1][0].pos = Vector2(20, 30)
	s.campaign = CampaignMap.load_from(GameData.texts)
	s.coop = QuietProgress.new()
	s.coop.session = s
	if GameData.campaign_id != CampaignProfile.ASTRAL: destination = "gz2g"
	check(s.campaign.zone(destination).get("type") == "game", "destination is an original field map")
	var e := entry()
	check(not CoopProgress._reached(e, destination), "guest starts without a fabricated destination flag")
	var pkg := travel(e)
	check(e.in_sync and e.clean and e.present, "fully aligned party carries campaign eligibility through field transfer")
	check(e.visited.has(destination) and e.credits.visited.has(destination), "shared transfer credits actual destination visit")
	check(pkg.move.get("zone") == destination, "returned save follows the shared destination")
	var solo := CoopProgress.fresh_state()
	CoopProgress.merge(solo, pkg)
	check(solo.current_zone == destination and solo.heroes[0][0].get("pos") == Vector2(20, 30), "returned save carries the guest's current position")
	check(solo.money == 222, "travel keeps the guest's personal purse")
	for field: String in ["active", "in_sync", "clean", "present"]:
		e = entry()
		e[field] = false
		pkg = travel(e)
		check(not e.in_sync and pkg.move.is_empty(), field + " is required for implicit shared travel")
	e = entry()
	pkg = travel(e, true)
	check(not e.in_sync and pkg.move.is_empty(), "loading a different host checkpoint cannot fabricate shared travel")
	e = entry()
	e.vars["q." + destination + ".ahead"] = 2.0
	pkg = travel(e)
	check(not e.clean and pkg.move.is_empty(), "a guest ahead at the destination keeps its own campaign location")
	e = entry()
	e.in_sync = false
	e.clean = false
	e.present = false
	e.vars["z." + destination] = 1.0
	s.state.set_var(0, "z." + destination, 1.0)
	pkg = travel(e)
	check(e.in_sync and e.clean and pkg.move.get("zone") == destination, "independently unlocked solo progress can join a compatible destination")
	e = entry()
	e.party_context.current_party = "DifferentChapter"
	pkg = travel(e)
	check(pkg.move.is_empty(), "a missed protagonist change cannot move an incompatible chapter")
	s.coop.free()
	s.free()
	print("COOP_PROGRESS_TRAVEL ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
