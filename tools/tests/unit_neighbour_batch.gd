extends Node
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("FAIL ", label)

func _ready() -> void:
	var w := GameWorld.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 905671
	var rows: Array[GameUnit] = []
	for i in 120:
		var u := GameUnit.new()
		u.world = w; u.uid = i + 1; u._seq = i + 1
		u.controller = i % 5 - 1
		u._radius_base = rng.randf_range(0.01, 2.2)
		u.pos = Vector2(rng.randf_range(0, 64), rng.randf_range(0, 64))
		w.set_unit(u.uid, u)
		rows.append(u)
	for trial in 2000:
		var u := rows[rng.randi_range(0,rows.size()-1)]
		u.dead = trial % 17 == 0
		u._moving = trial % 2 == 0
		u.stance = trial % 3
		u.pos = Vector2(rng.randf_range(0,64), rng.randf_range(0,64))
		var p := Vector2(rng.randf_range(-10,70),rng.randf_range(-10,70))
		var r := rng.randf_range(-2,45)
		for ordered in [false,true]:
			check(w.nav.units_all_around(p,r,ordered) == w.nav.units_all_around_script(p,r,ordered), "all neighbourhood %d/%s" % [trial,ordered])
			check(w.nav.units_around(p,r,ordered) == w.nav.units_around_script(p,r,ordered), "live neighbourhood %d/%s" % [trial,ordered])
		var q := u.pos + Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		var next := NavGrid.cell(q) + Vector2i(trial % 3 - 1,0) if trial % 2 else Vector2i(-1,-1)
		var native_result := {}
		var script_result := {}
		var expected := w.nav.step_blocker_script(u,q,script_result,next)
		check(w.nav.step_blocker(u,q,native_result,next) == expected and native_result == script_result, "collision and layer %d" % trial)
	for p in [Vector2.INF,Vector2(NAN,2),Vector2(-20,-20),Vector2(100000,100000)]:
		for r in [NAN,INF,-INF,-10.0,0.0,6.0,10000000.0]:
			check(w.nav.units_all_around(p,r) == w.nav.units_all_around_script(p,r), "unusual query")
	# Read current classification, including before ordinary track_unit.
	for u: GameUnit in rows:
		u.dead = not u.dead
	check(w.nav.units_around(Vector2(32,32),100) == w.nav.units_around_script(Vector2(32,32),100), "direct death/revive before tick")
	w.units = {}
	for u: GameUnit in rows: u.free()
	w.free()
	print("UNIT_NEIGHBOUR_CHECKS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
