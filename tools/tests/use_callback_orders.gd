extends Node
## A successful interaction can replace its action through an authored order,
## party transition or death. All use-animation completion paths must yield.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func _ready() -> void:
	var w := GameWorld.new()
	var u := GameUnit.new(); u.world = w
	for phase in [1,2,5]:
		for change in ["clear","replace","command","in_place"]:
			var replacement := {"type":"wait","t":2.0}
			var called := [0]
			u.order = {"type":"use","phase":phase,"clip":"",
				"rest":0.0,"kneel":false,"done":func():
					called[0] += 1
					if change == "clear": u.order = {}
					elif change == "replace": u.order = replacement
					elif change == "command": u.command(replacement)
					else: u.order.clear()}
			if phase == 5: u.order.merge({"hold":0.0,"t0":0.0})
			u._do_use(GameUnit.TICK)
			check(called[0] == 1,"phase %d %s dispatches interaction once" % [phase,change])
			if change == "replace":
				check(is_same(u.order,replacement) and u.order == {"type":"wait","t":2.0},
					"phase %d retains replacement order without use fields" % phase)
			elif change == "command":
				check(u.order.is_empty() and u.orders == [replacement],"phase %d preserves queued replacement" % phase)
			else:
				check(u.order.is_empty(),"phase %d cleared action is not resumed" % phase)
			u.orders.clear()
		var called := [0]
		u.order = {"type":"use","phase":phase,"clip":"",
			"rest":0.0,"kneel":false,"done":func(): called[0] += 1}
		if phase == 5: u.order.merge({"hold":0.0,"t0":0.0})
		u._do_use(GameUnit.TICK)
		check(called[0] == 1 and u.order.is_empty(),"phase %d ordinary interaction still finishes" % phase)
	u.free(); w.free()
	print("USE_CALLBACK_ORDERS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
