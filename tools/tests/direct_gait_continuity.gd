extends Node
var checks := 0
var failures := []
var selections := {}
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); if failures.size()<10: printerr("FAIL ",label)
func _ready() -> void:
	var unit := GameUnit.new()
	unit.model = EIUnitModel.create({"prototype":"Human Hero"},true)
	unit.direct_controlled = true; unit.direct_motion = Vector2.RIGHT; unit._move_speed = 1.2
	unit.action = "walk"; unit.facing = 0.0
	add_child(unit); unit.set_process(false); unit.set_physics_process(false)
	unit.add_child(unit.model); unit.model.set_process(false)
	var model := unit.model
	var pose := DirectPose.new(unit); unit.add_child(pose); pose.set_process(false)
	var wrong_healthy := 0
	for weapon: String in ["","sword","axe","dagger","spear","hammer","bow","crossbow"]:
		model.weapon_type = weapon
		model.pose_state = EIUnitModel.ST_NEUTRAL
		for injury in [0,1,2]:
			model.pose_mod = injury * EIUnitModel.MOD_1
			for running: bool in [false,true]:
				unit.running = running
				unit.action = "run" if running else "walk"
				model.act(unit.action)
				for trial in 24:
					seed(trial*1231+injury*97)
					pose.restore_pose(); pose.lower_clip=""; pose._lower_code=-1
					pose.apply_pose(1.0/60)
					var record: Dictionary = model._clip_records().get(pose.lower_clip,{})
					var modifier := int(record.get("code",0)) & 0x3fc00000
					selections[pose.lower_clip] = int(selections.get(pose.lower_clip,0))+1
					if injury==0 and modifier!=0: wrong_healthy+=1
					check(modifier==model.pose_mod or (injury>0 and modifier==0),"requested injury respected: %s run=%s injury=%d clip=%s"%[weapon,running,injury,pose.lower_clip])
			pose.restore_pose()
	# Verify continuous advancing cycles after sprint/recovery and combat
	# readiness changes. Placement fields must remain byte-for-byte untouched.
	model.pose_mod=0; model.weapon_type="sword"; unit.running=false; unit.action="walk"
	var at := unit.pos
	for trial in 32:
		model.pose_state=EIUnitModel.ST_ATTACK if trial%2 else EIUnitModel.ST_NEUTRAL
		unit.running=trial%3==0;unit.action="run" if unit.running else "walk"
		for frame in 12:
			pose.restore_pose();var previous:=pose.phase;pose.apply_pose(1.0/60)
			check(pose.phase!=previous,"leg cycle advances after gait/readiness transition")
			check(unit.pos==at and unit._move_speed==1.2,"pose composition leaves movement authority unchanged")
	# A held run request remains set while exhausted. Use walking clips at
	# the same walking speed, including attack/cast leg composition.
	unit.set_meta("hero", {})
	unit.max_mana = 100.0
	for action: String in ["walk","attack","cast"]:
		for stamina: float in [0.0,10.0,0.0]:
			pose.restore_pose(); unit.running = true; unit.mana = stamina
			unit.action = action; model.act(action,1,0.0); pose.weight = 1.0
			pose.apply_pose(0.016)
			var expected := "walk" if stamina <= 0.0 else "run"
			var record: Dictionary = model._clip_records().get(pose.lower_clip,{})
			check((int(record.get("code",-1)) & 0x3c0000) == (EIUnitModel.AC_WALK if stamina <= 0.0 else EIUnitModel.AC_RUN),"held run request uses %s legs with %s stamina during %s" % [expected,stamina,action])
	pose.restore_pose();unit.free()
	var result := {"checks":checks,"failures":failures.size(),"wrong_healthy_selections":wrong_healthy,"clips":selections}
	FileAccess.open("user://direct-gait-continuity.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DIRECT_GAIT_CONTINUITY ",JSON.stringify(result))
	get_tree().quit(1 if failures else 0)
