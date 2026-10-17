extends Node
## Public save attached to https://github.com/TheWWWorm/CursedLands/issues/19.
func _ready() -> void:
	var run:=ArenaRun.new();run.auto_save=false
	var path: String = get_script().resource_path.get_base_dir().path_join("fixtures/issue-19-arena-expedition.json")
	var restored:=run.restore(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var battle:=ArenaPveMatch.new();battle.run=run;battle.drives_clock=false
	add_child(battle);battle.set_process(false);battle.set_physics_process(false);battle._world_parent=self
	battle.prepare()
	var started:=battle.start();var elapsed:=0.0
	while battle.phase==ArenaMatch.Phase.DEPLOY and elapsed<12.0:
		battle._physics_process(1.0/60.0);elapsed+=1.0/60.0
	print("ISSUE_19 restored=",restored," accepted=",started," arrival_seconds=",elapsed," phase=",battle.phase," movers=",battle.formation_motion.movers.size())
	var good:=restored and started and battle.phase==ArenaMatch.Phase.FIGHT and elapsed<=2.1
	var steps:=0
	while good and battle.phase==ArenaMatch.Phase.FIGHT and steps<2300:
		battle.simulate_tick();steps+=1
	good=good and battle.phase==ArenaMatch.Phase.FINISHED and battle.world.time<=120.055
	print("ISSUE_19 finished=",battle.phase==ArenaMatch.Phase.FINISHED," seconds=",battle.world.time," damage=",battle.damage," success=",good)
	get_tree().quit(0 if good else 1)
