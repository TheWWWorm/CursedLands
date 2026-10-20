extends Node
## Real authority dispatch and campaign graph, with only the final world-loading
## boundary recorded. Co-op zone-transfer tests separately load the destination.
class RouteSession extends Session:
	var loads: Array = []
	var deliveries: Array = []
	var events: Array = []
	func _begin_host_load(id: String, _cancel_movie := true, _saved_mods: Dictionary = {}) -> void:
		loads.append(id)
		loading_game=true
		_load_serial+=1
	func _complete_zone_travel(id: String, entrance: int, serial: int, autosave := true, island_resume: Dictionary = {}) -> void:
		deliveries.append([id,entrance,serial,autosave,island_resume])
	func broadcast(event: Dictionary) -> void:
		events.append(event.duplicate(true))
		super.broadcast(event)

var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)

func _ready() -> void:
	var s := RouteSession.new(); add_child(s); s.set_physics_process(false)
	var astral := GameData.campaign_id==CampaignProfile.ASTRAL
	var from_zone := "gz1h" if astral else "gz2g"
	var destination := "gz2h" if astral else "gz3g"
	var edge := from_zone+"_"+destination
	var w := GameWorld.new(); w.session=s; w.presentation=false; s.world=w
	s.zone_id=from_zone; w.zone=s.campaign.zone(from_zone).duplicate(true)
	var hero := GameUnit.new(); hero.uid=1; hero.controller=0
	hero.set_meta("hero",{"name":"Route fixture"}); w.set_unit(hero.uid,hero)
	s.state.visited[from_zone]=true
	s.players={1:{"index":0,"name":"Host"},2:{"index":1,"name":"Guest"}}
	w.zone.exits={1:{"to":edge,"to_exit":1}}
	check(not s.campaign.zone(edge).is_empty(),"authored campaign edge exists")
	s.apply_command({"t":"leave_exit","exit":999},0)
	check(s.travel_options.is_empty() and s.loads.is_empty(),"unknown exit cannot open a route")
	s.apply_command({"t":"leave_exit","exit":1},1)
	check(s.travel_options.is_empty() and s.loads.is_empty(),"guest cannot confirm the host party's exit")
	s.apply_command({"t":"leave_exit","exit":1},0)
	check(s.map_open and not s.travel_options.is_empty(),"host confirmation opens the authored global map")
	check(s._travel_ev.get("from")==edge,"join-late map event identifies the selected edge")
	var offered := s.travel_options.duplicate(true)
	var route: Dictionary = {}
	for candidate: Dictionary in offered:
		if candidate.zone==destination: route=candidate
	check(not route.is_empty(),"map offers its adjacent destination")
	if route.is_empty(): finish(s,w,hero); return
	var time := s.state.get_var(0,"gtime")
	s.apply_command({"t":"travel_cancel"},0)
	check(not s.map_open and s.travel_options.is_empty() and s._travel_ev.is_empty(),"cancel clears visible map, offers and replay event")
	check(s.loads.is_empty() and s.state.get_var(0,"gtime")==time,"cancel neither loads a world nor charges travel time")
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},0)
	check(s.loads.is_empty(),"late destination selection after cancel is rejected")
	s.apply_command({"t":"travel_cancel"},0)
	check(not s.map_open and s.loads.is_empty(),"repeated cancel is harmless")
	s.apply_command({"t":"leave_exit","exit":1},0)
	check(s.map_open and s.travel_options==offered,"cancelled route can be opened again")
	s.apply_command({"t":"travel","zone":"missing-zone","entrance":1},0)
	s.apply_command({"t":"travel","zone":route.zone,"entrance":int(route.entrance)+999},0)
	check(s.loads.is_empty() and s.map_open,"unoffered destination and entrance cannot start travel")
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},1)
	check(s.loads.is_empty(),"guest cannot select the destination while the host is present")
	s.loading_game=true
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},0)
	check(s.loads.is_empty(),"pending load cannot start another transfer")
	s.loading_game=false
	hero.dead=true
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},0)
	check(s.loads.is_empty() and s.events[-1].t=="game_over","dead single-player protagonist cannot escape through the map")
	hero.dead=false
	s.apply_command({"t":"leave_exit","exit":1},0)
	s.state.set_var(0,"gtime",47.5)
	time=s.state.get_var(0,"gtime")
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},0)
	check(s.loads==[destination] and s.loading_game,"valid selection begins exactly one destination load")
	check(not s.map_open and s.travel_options.is_empty() and s._travel_ev.is_empty(),"accepted selection closes and consumes the route")
	check(is_equal_approx(s.state.get_var(0,"gtime"),time+float(route.get("hours",0.0))),"accepted selection charges the authored hours once across day boundaries")
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},0)
	await get_tree().process_frame
	check(s.loads.size()==1 and s.deliveries.size()==1,"duplicate selection cannot schedule a second transfer")
	check(s.deliveries[0][0]==destination and s.deliveries[0][1]==int(route.entrance),"deferred transfer keeps the chosen destination and entrance")
	s.loading_game=false
	s.players.erase(1)
	s.multiplayer_game=true
	s.apply_command({"t":"leave_exit","exit":1},0)
	s.apply_command({"t":"travel","zone":route.zone,"entrance":route.entrance},1)
	await get_tree().process_frame
	check(s.loads.size()==2,"remaining guest can choose a route when no host player occupies the party")
	finish(s,w,hero)

func finish(s: Session,w: GameWorld,hero: GameUnit) -> void:
	s.world=null; w.units={}; hero.free(); w.free(); s.free()
	print("TRAVEL_COMMAND_LIFECYCLE ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
