extends Node
## A quiet spawn/load record must be drawable before any unpaused frame.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func body_pose(u: GameUnit) -> Dictionary:
	var out := {}
	for n: Node3D in u.model.find_children("*", "Node3D", true, false):
		if not n is EIAnimPart: continue
		out[String(u.model.get_path_to(n))] = n.transform
	return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"volume_sfx":0,"volume_stream":0},true)
	var world := GameWorld.new(); add_child(world)
	world.set_process(false); world.set_physics_process(false); world.authority=false
	world.zone={"type":"game"}
	get_tree().paused = true
	var source := world.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(5,5,0)})
	check(source!=null,"original hero loads")
	if source==null: get_tree().quit(1); return
	for gait: int in [0,1,2,3]:
		for action: String in ["idle","walk"]:
			source.action=action
			source.restore_gait(gait)
			source.model.act(action,1,0.0); source.model.player.advance(0.0)
			var dest := world.spawn_unit({"nid":2,"prototype":"Human Hero","position":Vector3(5,5,0)})
			var label := "gait=%d action=%s" % [gait,action]
			dest.apply_snapshot(source.snapshot(),true)
			check(dest.stance==source.stance,label+" logical posture restored")
			check(dest.model.pose_state==source.model.pose_state,label+" displayed posture ready while paused")
			var before := body_pose(dest)
			check(not before.is_empty(),label+" native animation parts inspected")
			# Evaluate the selected clip at its current time, without a game tick.
			# Already materialized poses must not change on this first evaluation.
			dest._update_pose()
			dest.model.player.advance(0.0)
			check(before==body_pose(dest),label+" first evaluation cannot correct a stale pose")
			check(dest.model._resume.is_empty(),label+" no transition into saved stance")
			world.remove_unit(dest)
	# Corpses already have their final authored pose; quiet restoration must
	# not restart their death clip or replace it with a standing idle.
	source.lie_dead()
	var corpse := world.spawn_unit({"nid":3,"prototype":"Human Hero","position":Vector3(5,5,0)})
	corpse.apply_snapshot(source.snapshot(),true)
	var dead_pose := body_pose(corpse)
	corpse.apply_snapshot(source.snapshot(),true)
	check(corpse.dead and corpse.action=="death" and dead_pose==body_pose(corpse),"quiet corpse retains held final pose")
	get_tree().paused=false
	world.free()
	print("PAUSED_SPAWN_POSE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
