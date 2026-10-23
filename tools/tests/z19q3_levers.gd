extends Node
## z19q3 on the campaign's zone 19: the teleport panels TCP-A / TCP-B start
## switched on, as on the quest's multiplayer map, so objectives 5..7 wait for
## the player to switch them off; a stored zone keeps the switched panels.
var checks := 0
var failures := 0
const PANELS := [43968, 43974]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func obj(s: Session, k: int) -> float:
	return s.state.get_var(0, "q.z19q3.z19q3.%d" % k)

func watchers(s: Session) -> Array:
	return s.world.vm.instances.filter(func(x): return x.sname in ["VCheck#0#1", "VCheck#0#4", "VCheck#0#447", "VCheck#0#448"]).map(func(x): return x.sname)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	var q: Dictionary = SideQuests.all().filter(func(x): return x.id == "z19q3")[0]
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	var zone := SideQuests.zone_of(s, q)
	# The quest is offered once the zone was visited: the zone's own panel
	# watchers (q72h) have run there with the panels off.
	await s.enter_zone(zone, 1, false)
	for i in 80: s.world._tick(GameUnit.TICK)
	print("FIRST VISIT ", watchers(s), " PState=", s.state.get_var(0, "PState"))
	s.state.store_zone(zone, s.world)
	s.state.side_quests["z19q3"] = "active"
	await s.enter_zone(zone, 1, false)
	for i in 80: s.world._tick(GameUnit.TICK)
	print("RETURN ", watchers(s))
	check(s.state.get_var(0, "PState") == 0.0, "turning the panels on for the quest does not count for q72h (PState %.0f)" % s.state.get_var(0, "PState"))
	for nid in PANELS:
		check(s.world.levers.has(nid) and int(s.world.levers[nid].state) == 1, "panel %d starts on (%s)" % [nid, str(s.world.levers.get(nid, {}).get("state"))])
	var q72h := []
	for k in range(1, 30):
		if s.state.get_var(0, "q.gz19h.q72h.%d" % k) > 0: q72h.append(k)
	print("ARRIVAL PState=", s.state.get_var(0, "PState"), " q72h set=", q72h)
	for k in [5, 6, 7]:
		check(obj(s, k) < 2.0, "objective %d not met on arrival (%.0f)" % [k, obj(s, k)])
	check(s.world.lever_sys.usable(PANELS[0]) and int(s.world.levers[PANELS[0]].cycled) == 1, "TCP-A can be switched back off")
	s.world.lever_sys.toggle(PANELS[0])   # the player's use (cycled: 1 -> 0)
	for i in 40: s.world._tick(GameUnit.TICK)
	check(obj(s, 5) >= 2.0 and obj(s, 6) < 2.0 and obj(s, 7) < 2.0, "TCP-A off meets objective 5 only (%.0f %.0f %.0f)" % [obj(s, 5), obj(s, 6), obj(s, 7)])
	s.world.lever_sys.restore(PANELS[1], 0, 0.0)
	for i in 40: s.world._tick(GameUnit.TICK)
	check(obj(s, 6) >= 2.0 and obj(s, 7) >= 2.0, "both off meet objectives 6 and 7 (%.0f %.0f)" % [obj(s, 6), obj(s, 7)])
	print("AFTER OFF ", watchers(s), " PState=", s.state.get_var(0, "PState"))
	# The campaign still counts the player switching them back on (q72h).
	for nid in PANELS: s.world.lever_sys.restore(nid, 1, 1.0)
	for i in 40: s.world._tick(GameUnit.TICK)
	check(s.state.get_var(0, "PState") == 2.0, "switching both back on counts for q72h (PState %.0f)" % s.state.get_var(0, "PState"))
	for nid in PANELS: s.world.lever_sys.restore(nid, 0, 0.0)
	for i in 20: s.world._tick(GameUnit.TICK)
	# Stored and re-entered: the switched panels stay off.
	s.state.store_zone(zone, s.world)
	await s.enter_zone(zone, 1, false)
	for i in 20: s.world._tick(GameUnit.TICK)
	for nid in PANELS:
		check(int(s.world.levers[nid].state) == 0, "panel %d stays off after re-entry (%s)" % [nid, str(s.world.levers[nid].state)])
	print("Z19Q3_LEVERS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
