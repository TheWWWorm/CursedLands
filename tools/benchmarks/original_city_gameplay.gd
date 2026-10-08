extends "user://original_gameplay_versioned.gd"
## Additional ordinary-camera coverage; keep separate from close Terror runs.
var _logged_census := 0
func _process(dt:float)->void:
	super._process(dt)
	if not recording or census.size()==_logged_census:return
	_logged_census=census.size()
	var actors:=[]
	for uid in controlled:
		var u:GameUnit=session.world.units.get(uid)
		if u:actors.append({"uid":uid,"dead":u.dead,"hp":u.hp,"pos":u.pos,"action":u.action})
	census[-1]["controlled"]=actors
	var asleep:=0
	for u:GameUnit in session.world.unit_rows():
		if is_instance_valid(u) and u._presentation_sleeping:asleep+=1
	census[-1]["sleeping_replicas"]=asleep
