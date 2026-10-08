extends Node
## The native edge-entry rule on real base/LiA map graphs, without a world.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"net_directory":0,"net_lan":0,"net_upnp":0,"start_zones":0}, true)
	var s := Session.new()
	add_child(s)
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	var completed := "gz1h" if astral else "gz2g"
	var new_region := "gz2h" if astral else "gz3g"
	var edge := completed + "_" + new_region
	var camp_region := "gz3h" if astral else "gz1g"
	var camp := "bz3h" if astral else "bz1g"
	s.state = CampaignState.new()
	s.state.set_var(0, "z." + completed, 2)
	s.state.set_var(0, "z.gz4h" if astral else "z.gz4g", 0)
	s.leave_zone(edge, 1)
	check(s.map_open, "entering an authored edge opens the map")
	check(s.state.get_var(0, "z." + completed) == 2, "completed adjacent region stays completed")
	check(s.state.get_var(0, "z." + new_region) == 1 and not s.state.visited.has(new_region),
		"an unvisited adjacent game region becomes explored")
	check(s.state.get_var(0, "z.gz4h" if astral else "z.gz4g") == 0,
		"reveal does not walk through the graph to later regions")
	check(s._travel_ev.zone_states.get(completed) == 2 and s._travel_ev.zone_states.get(new_region) == 1,
		"reliable map event contains the authoritative adjacent states")
	s.leave_zone(edge, 1)
	check(s.state.get_var(0, "z." + completed) == 2 and s.state.get_var(0, "z." + new_region) == 1,
		"opening the edge again is idempotent")
	s.leave_zone(camp_region + "_" + camp, 1)
	check(s.state.get_var(0, "z." + camp_region) == 1, "camp edge reveals its adjacent game region")
	check(s.state.get_var(0, "z." + camp) == 0, "camp visibility remains controlled by its story script")
	check(s.state.get_var(0, "z." + camp_region + "_" + camp) == 0, "entering an edge does not change its gate state")
	s.free()
	print("TRAVEL_REVEAL ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
