extends Node
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func scoped(w: GameWorld, early: bool) -> int:
	var _profile := w.profile_scope("early" if early else "normal", 17) if w.profile_simulation else null
	if early: return 12
	return 34

func nested(w: GameWorld) -> void:
	var _profile := w.profile_scope("outer")
	check(scoped(w,true) == 12,"nested return unchanged")
	check(w.profile_counts.get("early",0) == 2 and not w.profile_counts.has("outer"),"scope closes at function return")

func suspended(w: GameWorld) -> void:
	var _profile := w.profile_scope("suspended")
	await get_tree().process_frame
	check(not w.profile_counts.has("suspended"),"scope survives await")

func _ready() -> void:
	var w := GameWorld.new()
	check(scoped(w,true) == 12 and w.profile_counts.is_empty(),"disabled profiler has no scope")
	w.profile_simulation = true
	check(scoped(w,true) == 12,"early return value")
	check(scoped(w,false) == 34,"normal return value")
	check(w.profile_counts == {"early":1,"normal":1},"each branch records once")
	nested(w)
	check(w.profile_counts.outer == 1,"outer closes exactly once")
	await suspended(w)
	# A coroutine signals its awaiting caller before releasing its frame.
	await get_tree().process_frame
	check(w.profile_counts.suspended == 1,"suspended scope closes after resume")
	var u := GameUnit.new()
	var other := GameUnit.new()
	u.world = w
	other.hidden = true
	check(not w.ai.can_notice_with(u,other,PackedFloat64Array()),"real AI early return")
	check(w.profile_counts.get("aican_notice_with",0) == 1,"real AI method recorded")
	u._set_action("idle")
	check(w.profile_counts.get("unit_set_action",0) == 1,"real unit method recorded")
	w.profile_simulation = false
	u._set_action("idle")
	check(w.profile_counts.unit_set_action == 1,"disabled real method skips recording")
	for value in w.profile_us.values(): check(value >= 0,"nonnegative duration")
	u.free(); other.free()
	var orphan := w.profile_scope("orphan")
	w.free()
	orphan = null
	print("SIMULATION_PROFILE_SCOPES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
