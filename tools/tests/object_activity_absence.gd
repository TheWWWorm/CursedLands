extends Node
## A revisited campaign zone catches up on the party's absence as the
## original does (base 57a48a): 100 object steps per campaign hour away, at
## most 1000, waking only the objects within 70 m of the entrance's deploy
## centre. No scripts run and the clock stands still meanwhile.
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0))
	await s.enter_zone("gz3g",1,false)
	var z := s.campaign.zone("gz3g")
	var centre: Vector2 = (z.exits[1].deploy as Rect2).get_center()
	var before := {}
	for u: GameUnit in s.world.unit_rows():
		if u.controller < 0 and not u.dead: before[u.uid] = u.pos
	await s.enter_zone("bz1g",1,false)
	check(s.state.zones.get("gz3g", {}).has("left"), "leaving gz3g records the campaign clock")
	var left := float(s.state.zones.gz3g.left)
	s.state.advance_hours(3.0)
	var hours := s.state.get_var(0, "gtime")
	await s.enter_zone("gz3g",1,false)
	var w := s.world
	check(s.state.get_var(0, "gtime") == hours, "the clock does not run during the catch-up")
	var expect := mini(int((hours - left) * 100.0), 1000)
	check(expect == 300, "3 hours away are %d steps" % expect)
	check(w._logic_step >= expect, "the zone ran its absence steps (%d)" % w._logic_step)
	var near_moved := 0
	var far_moved := 0
	var near := 0
	for uid in before:
		var u: GameUnit = w.units.get(uid)
		if u == null: continue
		var d: float = (before[uid] as Vector2).distance_to(centre)
		var moved: bool = u.pos.distance_to(before[uid]) > 0.01
		# Wake cells reach r/32 + 1 cells around the centre's cell.
		if d < 30.0:
			near += 1
			if moved: near_moved += 1
		elif d > 70.0 + 3 * ObjectActivity.CELL and moved and not w.active_set.is_awake(u):
			far_moved += 1
	check(near_moved > 0, "units near the entrance moved meanwhile (%d of %d)" % [near_moved, near])
	check(far_moved == 0, "units far from the entrance stayed put (%d moved)" % far_moved)
	print("RESULT failures=", failures)
	get_tree().quit(1 if failures else 0)
