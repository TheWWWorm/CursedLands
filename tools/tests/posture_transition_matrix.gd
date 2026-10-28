extends Node
## The posture-transition family (#109 cast, #113 killing blow, #118 prone
## recovery) reopened under new numbers because each fix tested one cell of
## the same matrix. This test covers the whole matrix: a one-shot (self cast,
## non-lethal melee hit, killing blow, damage reaction; targeted and direct
## attacks) begun from crawl, kneel or stand, with the other two gaits
## requested at two offsets while the one-shot plays. The displayed posture
## stays until the one-shot completes, the authority then plays the crossing
## into the requested posture, a replica fed the authority's snapshots plays
## the same crossing, and both end in the requested gait.
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func step(w: GameWorld, u: GameUnit) -> void:
	w.time += GameUnit.TICK
	u._tick(GameUnit.TICK); u._draw_step(GameUnit.TICK); u.anim_flush()
	u.model.player.advance(GameUnit.TICK); u.model._process(0)

func feed(host: GameUnit, replica: GameUnit) -> void:
	replica.apply_snapshot(host.snapshot()); replica._draw_step(GameUnit.TICK); replica.anim_flush()
	replica.model.player.advance(GameUnit.TICK); replica.model._process(0)

## 0 crawl, 1 kneel, 2 stand: the posture family a displayed pose belongs to.
func family(pose_state: int) -> int:
	return 0 if pose_state == EIUnitModel.ST_LIE else 1 if pose_state == EIUnitModel.ST_WARRY else 2

func crossing(u: GameUnit, requested: int) -> bool:
	return u.model._current.begins_with("ucross") and family(u.model.pose_state) == requested

func began(u: GameUnit, shot: String) -> bool:
	match shot:
		"cast": return u.action.begins_with("cast")
		"damage": return u.action == "hit" and u._anim_lock > 0.0
		_: return u.action == "attack" and not u._pending_hit.is_empty()

func finished(u: GameUnit, shot: String) -> bool:
	match shot:
		"cast": return not u.action.begins_with("cast")
		"damage": return u._anim_lock <= 0.0 and u.action != "hit"
		_: return u._pending_hit.is_empty() and u.action != "attack"

func _ready() -> void:
	var w := GameWorld.new(); add_child(w); w.set_process(false); w.set_physics_process(false); w.zone = {"type":"game"}
	var rw := GameWorld.new(); add_child(rw); rw.authority = false; rw.set_process(false); rw.set_physics_process(false)
	w.set_relation(0, 1, 2)
	var rows := []
	# Each case gets its own units far from the others: a direct attack swings
	# at whatever stands in reach, and the worlds keep every unit (hidden, not
	# freed) so the activity lists never point at a freed instance.
	var slot := 0
	for start: int in [0, 1, 2]:
		for shot: String in ["cast", "attack", "direct_attack", "kill", "direct_kill", "damage"]:
			for requested: int in [0, 1, 2]:
				if requested == start: continue
				for offset: int in [0, 4]:
					var label := "start=%d shot=%s request=%d offset=%d" % [start, shot, requested, offset]
					var x := 5.0 + 4.0 * slot; slot += 1
					var a := w.spawn_unit({"prototype":"Human Hero", "position":Vector3(x, 5, 0)})
					var b := w.spawn_unit({"prototype":"Human Hero", "position":Vector3(x + 0.8, 5, 0)})
					for u: GameUnit in [a, b]:
						u.set_process(false); u.set_physics_process(false); u.ai_next = INF; u._perceive_next = INF
					a.controller = 0; a.set_meta("hero", {}); a.faction = 0; b.faction = 1; b.controller = -1
					a.facing = 0.0; b.facing = 0.0
					# A party order on a unit goes on only while the party has noticed it;
					# perception is switched off here, so record the sighting directly.
					a.set_meta("noticed", {b.get_instance_id(): b})
					a.restore_gait(start); a._anim_lock = 0.0; a._attack_cd = 0.0; a.action = "idle"; a._update_pose()
					a.max_mana = 10000.0; a.mana = 10000.0; a.stats.int = 25.0
					var lethal: bool = shot.ends_with("kill")
					a.stats.dmg_min = 10000.0 if lethal else 5.0; a.stats.dmg_max = a.stats.dmg_min
					a.stats.to_hit = 10000.0; a.stats.dmg_types = PackedFloat32Array([0, 0, 1, 0, 0, 0, 0])
					a.direct_controlled = shot.begins_with("direct")
					match shot:
						"cast": a.command({"type":"cast", "spell":"healing{}", "target":a})
						"damage":
							for attempt in 16:
								a.take_damage(0.1, b, 1)
								if a.action == "hit": break
						"attack", "kill": a.command({"type":"attack", "target":b, "aim":1})
						_: a.command({"type":"direct_attack", "direction":Vector3.RIGHT})
					for i in 150:
						if began(a, shot): break
						step(w, a)
					check(began(a, shot), label + ": one-shot begins")
					var replica := rw.spawn_unit({"prototype":"Human Hero", "position":Vector3(x, 5, 0)})
					replica.set_process(false); replica.set_physics_process(false)
					replica.apply_snapshot(a.snapshot(), true); replica._draw_step(0)
					for i in offset:
						step(w, a); feed(a, replica)
					var from: int = a.model.pose_state
					var in_shot := not finished(a, shot)
					check(in_shot, label + ": request arrives while the one-shot plays")
					a.set_gait(requested); a._draw_step(0); feed(a, replica)
					check(a.model.pose_state == from and replica.model.pose_state == from, label + ": request keeps the displayed posture")
					var needs_cross: bool = family(from) != requested
					var host_cross := false; var replica_cross := false; var done_at := -1
					for i in 260:
						step(w, a); feed(a, replica)
						if done_at < 0 and finished(a, shot): done_at = i
						host_cross = host_cross or crossing(a, requested)
						replica_cross = replica_cross or crossing(replica, requested)
					check(done_at >= 0, label + ": one-shot completes")
					if needs_cross:
						check(host_cross, label + ": authority crosses into the requested posture")
						check(replica_cross, label + ": replica crosses into the requested posture")
					else:
						check(family(a.model.pose_state) == requested and family(replica.model.pose_state) == requested, label + ": displayed posture already matches the request")
					if shot == "attack":
						# The target survives, so the attack order continues: the
						# next swing needs the standing pose again (#118). What the
						# unit remembers of the request once the fight ends is not
						# pinned here (unverified against the original).
						check(a.order.get("type", "") == "attack" or a.action == "attack", label + ": the attack order continues after the crossing")
						check(family(a.model.pose_state) == 2 and family(replica.model.pose_state) == 2, label + ": the continuing attack stands the unit up again")
					else:
						check(a.gait() == requested and replica.gait() == requested, label + ": both end in the requested gait")
					# A targeted blow aims at the torso and kills; a direct swing strikes
					# whatever body part the crosshair meets, so only its contact is required.
					if shot == "kill": check(b.dead, label + ": blow kills the target")
					elif shot == "direct_kill": check(b.hp < b.max_hp, label + ": direct swing connects")
					elif shot != "cast" and shot != "damage": check(not b.dead, label + ": hit leaves the target alive")
					rows.append({"case":label, "from":from, "done_at":done_at, "host_cross":host_cross, "replica_cross":replica_cross,
						"gait":a.gait(), "replica_gait":replica.gait(), "clip":a.model._current, "target_hp":b.hp, "target_max_hp":b.max_hp,
						"miss":a.strike_miss, "distance":a.pos.distance_to(b.pos), "facing":a.facing, "pending":a._pending_hit.size()})
					a.hide(); b.hide(); replica.hide()
	w.queue_free(); rw.queue_free()
	for i in 6: await get_tree().process_frame
	FileAccess.open("user://posture-transition-matrix.json", FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	print("POSTURE_TRANSITION_MATRIX ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
