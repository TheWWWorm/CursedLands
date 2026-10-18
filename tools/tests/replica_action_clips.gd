extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	var run := ArenaRun.new(); run.auto_save=false; run.begin(7319); run.training=126
	for pair in [[0,0],[1,0],[4,2],[6,0],[15,2],[24,2]]: run._recruit(pair[0],pair[1],9)
	run.arrange()
	var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
	add_child(battle); battle._world_parent=self; battle.prepare(); battle.world.authority=false
	for unit: GameUnit in battle.world.unit_rows():
		if int(unit.get_meta("arena_placement",{}).get("team",1))!=0: continue
		for action in ["run","idle","walk","idle","run","idle"]:
			var snap := unit.snapshot(); snap[4]=action; snap[13]=0.0 if action=="idle" else 4.0
			unit.apply_snapshot(snap,false,ArenaOnlineGame.exact_body(unit))
			check(unit.action==action and unit.model._cycle==unit.model.code_for(action),"snapshot clip %s: %s"%[unit.info.prototype,action])
		unit._set_action("run")
	battle._stop_locomotion()
	for unit: GameUnit in battle.world.unit_rows():
		check(unit.dead or unit.model._cycle==unit.model.code_for("idle"),"round end replaces the final movement clip")
	print("REPLICA_ACTION_CLIPS ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
