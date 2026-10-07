extends Node
## Cache invalidation must follow every combat/save/network mutation. The
## numeric oracle uses the old body formula, independently of the new records.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 25: printerr("FAIL ", label)

func same(u: GameUnit, label: String) -> void:
	var lost := 0.0
	for p in u.parts:
		if p.state > 0:
			lost += u.max_hp * p.lethal * (1.0 if p.cur < 0.0 else (p.max-p.cur)/p.max)
	var want := u._hp if u.parts.is_empty() else u.max_hp-lost
	check(u.hp == want and u.hp == want, label)

func body() -> GameUnit:
	var u := GameUnit.new()
	u.race = {"head":["skull",1,0.4,1.01], "torso":["torso",0,1.0,1.01],
		"left_arm":["arm",1,0.3,0.25], "right_arm":["arm",1,0.3,0.25],
		"left_leg":["leg",1,0.5,0.25], "right_leg":["leg",1,0.5,0.25]}
	u.max_hp = 100.0
	u._init_parts()
	return u

func _ready() -> void:
	var u := body()
	check(u.parts.is_read_only(), "roster membership cannot bypass invalidation")
	check(u.hp == 100.0, "fresh body is healthy")
	check(u.run_refusal() == 0 and u._legs_ratio() == 1.0 and u.wound_factor(3) == 1.0, "healthy typed legs permit running")
	u.parts[4].cur = u.parts[4].max * 0.25
	check(u.run_refusal() == 1 and u._legs_ratio() == 0.25 and u.wound_factor(3) < 1.0, "injury invalidates movement values immediately")
	u.parts[4].type = 2
	check(u.run_refusal() == 0 and u.wound_factor(3) == 1.0 and u.wound_factor(2) < 1.0, "part regrouping invalidates limb membership")
	u.parts[4].type = 3
	u.restore_parts()
	check(u.run_refusal() == 0 and u.wound_factor(3) == 1.0, "restored limbs permit normal movement")
	u._hurt_part(2,3.0)
	check(is_equal_approx(u.hp,97.5), "limb damage keeps original lethal weighting")
	u.heal(2.5)
	check(is_equal_approx(u.hp,100.0), "healing restores the weighted health")
	u._hurt_part(4,50.0)
	check(u.parts[4].state == 2 and u.hp == 75.0, "destroyed leg keeps capped health loss")
	u.heal(1.0)
	check(u.parts[4].state == 3 and u.hp == 76.0, "healing reactivates destroyed limb")
	u._hurt_part(3,1.0,PackedFloat32Array([30.0]))
	check(u.parts[3].state == 1 and (u.severed_mask() & 8) != 0, "type-specific severance")
	var severed: float = u.parts[3].cur
	u.heal(1000.0)
	check(u.parts[3].cur == severed and u.hp == 75.0, "ordinary healing cannot restore severed part")
	u.restore_parts()
	check(u.hp == 100.0 and u.severed_mask() == 0, "resurrection restores all limbs")
	u.body_damage(17.0)
	check(is_equal_approx(u.hp,83.0), "whole-body damage preserves requested loss")
	u.max_hp = 250.0
	check(is_equal_approx(u.hp,207.5), "maximum scaling keeps wound fractions")
	u.buffs.strength = {"hp_mul":1.25,"until":100.0}
	u.refresh_max_hp()
	check(is_equal_approx(u.hp,259.375), "buff scaling refreshes cached health")
	var saved := CampaignState.body_state(u)
	var v := body()
	v.max_hp = 250.0
	CampaignState.apply_body(v, saved)
	check(v.hp == u.hp and CampaignState.body_state(v) == saved, "body save round-trip with buff and wounds")
	u.restore_parts()
	u.body_damage(8.0)
	var shot := u.snapshot()
	v.apply_snapshot(shot,true)
	same(v,"snapshot invalidates each changed body fraction")
	for i in 6:
		check(v.parts[i].cur == shot[8][i]/255.0*v.parts[i].max, "snapshot part %d" % i)
	u.lie_dead()
	u.rise(1.0)
	check(not u.dead and is_equal_approx(u.hp,1.0), "revival from cached dead health")
	u.revive()
	check(u.hp == u.max_hp, "full revival restores cached health")
	# A held record from the previous body must neither mutate nor invalidate
	# the replacement body, including when both rosters contain six parts.
	var previous: UnitBodyPart = u.parts[0]
	u._init_parts()
	var current_hp := u.hp
	previous.cur = -previous.max
	check(u.hp == current_hp, "detached old part cannot affect replacement body")
	var rng := RandomNumberGenerator.new()
	rng.seed = 805017
	for turn in 2000:
		var p: UnitBodyPart = u.parts[rng.randi_range(0,5)]
		match turn % 7:
			0: p.cur = rng.randf_range(-3.0,1.2)*p.max
			1: p.max = rng.randf_range(0.01,500.0)
			2: p.lethal = rng.randf_range(0.0,1.1)
			3: p.state = rng.randi_range(0,3)
			4: u._max_hp = rng.randf_range(1.0,500.0)
			5: u.parts = u.parts
			6: u.heal(rng.randf_range(0.0,100.0))
		same(u,"mutation %d" % turn)
		var keep := u.hp
		v.parts[0].cur -= 1.0
		check(u.hp == keep,"separate unit revisions")
	# Absent bodies retain the old scalar fallback, including direct changes.
	u.parts = []
	u.hp = 11.0
	check(u.hp == 11.0,"empty body scalar setter")
	u._hp = -2.0
	check(u.hp == -2.0,"empty body direct scalar change")
	u.free(); v.free()
	print("BODY_RECORDS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
