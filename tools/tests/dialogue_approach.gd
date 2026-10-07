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
		units.append(u); w.units[u.uid] = u
	var c := {"a":1,"b":2,"c":3}
	b._face(c,false,true)
	check(b._return_actors.is_empty(), "clicked conversation has no return walk")
	for i in 3:
		var u := units[i]; var key: String = ["a","b","c"][i]
		check(c.at[key] == [u.pos.x,u.pos.y] and c.at_z[key] == u.position.y, "camera preserves actual actor position and height")
		check(u.orders.size() == 1 and u.orders[0].type == "rotate", "clicked actor only turns")
		check(w.dialog_movers[u].state == 2 and w.dialog_movers[u].to == u.pos, "clicked actor skips route staging")
	for u in units: u.orders.clear()
	w.dialog_movers.clear()
	units[1].blocked = true
	b._face(c,false,true)
	check(units[1].orders.is_empty() and not w.dialog_movers.has(units[1]), "blocked story hero remains blocked")
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
	w.dialog_movers.clear(); w.units.clear()
	for u in units: u.free()
	w.free()
	print("DIALOG_STAGING_CHECKS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
