extends Node
## Authority fits survive body effects, figure replacement and enemy snapshots.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func _ready() -> void:
	var world := GameWorld.new(); world.zone={"type":"arena"}; world.process_mode=Node.PROCESS_MODE_DISABLED; add_child(world)
	var serial := 800000
	for id: String in ["dragonbrownm16","cyclopsa20"]:
		for side in [1,2]:
			serial += 1
			var actor := GameUnit.new(); world.add_child(actor)
			check(actor.setup(world,{"prototype":id,"nid":serial,"player":side}), "loads scaled creature "+id)
			world.set_unit(actor.uid,actor)
			ArenaPveMatch._fit_figure(actor)
			var scale: Vector3 = actor.model.scale
			var height := actor.model.height_k
			var radius := actor.figure_radius
			check(scale.x < 1.0, "large native figure is fitted "+id)
			actor.refresh_figure(true)
			check(actor.model.scale.is_equal_approx(scale) and is_equal_approx(actor.model.height_k,height), "forced replacement retains fit and gait %s:%d" % [id,side])
			actor.buffs.strength={"until":20.0}; actor.refresh_figure()
			check(actor.model.scale.is_equal_approx(scale), "body effect retains arena fit %s:%d" % [id,side])
			var strength_height := actor.model.height_k
			var snapshot := actor.snapshot()
			actor.buffs.clear(); actor.refresh_figure()
			actor.apply_snapshot(snapshot,true)
			check(actor.model.scale.is_equal_approx(scale) and is_equal_approx(actor.model.height_k,strength_height), "snapshot body effect retains fit and gait %s:%d" % [id,side])
			for repeat in 5: ArenaPveMatch._fit_figure(actor)
			check(actor.figure_radius == radius and actor.model.scale.is_equal_approx(scale), "repeated fits do not compound collision or scale "+id)
			var replica := GameUnit.new(); world.add_child(replica)
			var record := actor.info.duplicate(true); record.nid=serial+100
			check(replica.setup(world,record), "loads authoritative scaled record "+id)
			replica.apply_snapshot(snapshot,true)
			ArenaPveMatch._fit_figure(replica)
			check(replica.model.scale.is_equal_approx(scale) and replica.figure_radius == radius, "late enemy record uses authoritative fit rather than posed bounds "+id)
			replica.buffs.clear(); replica.refresh_figure()
			check(replica.model.scale.is_equal_approx(scale) and is_equal_approx(replica.model.height_k,height), "enemy effect expiry retains fit and gait "+id)
			world.erase_unit(actor.uid); actor.free(); replica.free()
	world.queue_free(); await get_tree().process_frame
	print("ARENA_SCALE_PRESERVATION ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
