extends Node
## Shared UI broad phases must retain live membership, order and flags.
var checks := 0
var failures := 0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func compare(w:GameWorld,label:String)->void:
	var expected:Array[GameUnit]=[]
	var party:Array[GameUnit]=[]
	for u in w.units.values():
		if is_instance_valid(u):
			if u.visible:expected.append(u)
			if u.controller>=0:party.append(u)
	check(w.visible_units()==expected,label+" visible order/membership")
	check(w.party_units()==party,label+" party order/membership")
	check(w.visible_units().is_read_only(),label+" immutable visible roster")

func _ready()->void:
	var w:=GameWorld.new()
	w.authority=false
	w.process_mode=Node.PROCESS_MODE_DISABLED
	var rows:Array[GameUnit]=[]
	for i in 12:
		var u:=GameUnit.new()
		u.uid=i+1
		u.world=w
		u.controller=i%3-1
		u.visible=i%2==0
		w.set_unit(u.uid,u)
		w.add_child(u)
		rows.append(u)
	compare(w,"off tree")
	rows[0].hide()
	rows[1].show()
	compare(w,"off tree flags")
	add_child(w)
	compare(w,"entered tree")
	var retained:=w.visible_units()
	var retained_ids:=retained.map(func(u):return u.uid)
	var rng:=RandomNumberGenerator.new()
	rng.seed=717309
	for i in 200:
		var u:=rows[rng.randi_range(0,rows.size()-1)]
		u.visible=not u.visible
		u.controller=rng.randi_range(-1,2)
		compare(w,"same-frame change %d"%i)
	check(retained.map(func(u):return u.uid)==retained_ids,"retained snapshot remains unchanged")
	w.hide()
	compare(w,"hidden ancestor retains local visible semantics")
	w.show()
	compare(w,"shown ancestor")
	var detached:=rows[2]
	w.remove_child(detached)
	compare(w,"registered detached unit")
	detached.visible=not detached.visible
	compare(w,"detached visibility changes")
	w.add_child(detached)
	compare(w,"reentered unit")
	var old:GameUnit=rows.pop_back()
	var replacement:=GameUnit.new()
	replacement.uid=old.uid
	replacement.world=w
	w.add_child(replacement)
	w.set_unit(replacement.uid,replacement)
	old.free()
	compare(w,"same-count replacement")
	w.erase_unit(detached.uid)
	w.set_unit(detached.uid,detached)
	compare(w,"erase and reinsert changes order")
	replacement.free()
	compare(w,"freed registered unit")
	w.erase_unit(12)
	w.free()
	print("PRESENTATION_ROSTER checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
