extends Node
## Run with an isolated user profile and --tool=<absolute path to this file>.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var w := GameWorld.new()
	var vm := ScriptVM.new()
	vm.world = w; w.vm = vm
	var b := Briefings.new(vm); vm.briefings = b
	var units: Array[GameUnit] = []
	for i in 3:
		var u := GameUnit.new(); u.uid = i+1; u.world = w
		u.pos = Vector2(10.0+i*3.0,20.0+i); u.position.y = 2.0+i
		units.append(u); w.set_unit(u.uid, u)
	var c := {"a":1,"b":2,"c":3}
	b._face(c,false,true)
	check(b._return_actors.size() == 1, "clicked conversation remembers the third actor's return")
	for i in [0,2]:
		var u := units[i]
		check(u.orders.size() == 1 and u.orders[0].type == "move" and u.orders[0].story_move, "clicked actor walks to the original mark")
		check(w.dialog_movers[u].state == 1 and w.dialog_movers[u].to != u.pos, "clicked actor uses walking stage")
	check(units[1].orders.is_empty(), "ordinary conversation retains the partner's position")
	# Reconcile a partial/blocked route using actual final positions and heights.
	b._face_in_place(c,units[0],units[1])
	for i in 3:
		var u := units[i]; var key: String = ["a","b","c"][i]
		check(c.at[key] == [u.pos.x,u.pos.y] and c.at_z[key] == u.position.y, "camera uses actual actor position and height")
		check(u.orders.size() == 1 and u.orders[0].type == "rotate", "all participants face after walking")
	for u in units: u.orders.clear()
	w.dialog_movers.clear()
	units[1].blocked = true
	b._face(c,false,true)
	check(units[1].orders.is_empty() and not w.dialog_movers.has(units[1]), "blocked story actor remains blocked")
	units[1].blocked = false
	for u in units: u.orders.clear()
	w.dialog_movers.clear()
	b._face(c)
	check(units[0].orders[0].type == "move", "programmatic side-quest briefing retains its staging")
	check(c.at.a != [units[0].pos.x,units[0].pos.y], "programmatic camera retains authored mark")
	check(b._return_actors.size() == 1, "programmatic third actor keeps return lifecycle")
	var hero := units[1]
	hero.set_meta("interact",[units[0],0])
	hero.command({"type":"move","to":hero.pos},true)
	check(hero.has_meta("interact"), "queuing later movement preserves current interaction")
	hero.command({"type":"move","to":hero.pos})
	check(not hero.has_meta("interact"), "replacement movement cancels current interaction")
	w.dialog_movers.clear(); w.units = {}
	for u in units: u.free()
	w.free()
	print("DIALOG_STAGING_CHECKS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
