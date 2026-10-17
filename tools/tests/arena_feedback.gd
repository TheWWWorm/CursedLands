extends Node
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func fresh()->ArenaRun:
	var run:=ArenaRun.new();run.auto_save=false;run.begin(7311);run.gold=100
	return run
func offer(run:ArenaRun,family:int)->int:
	return run.shop.find_custom(func(row):return int(row.family)==family)
func _ready()->void:
	var run:=fresh()
	for family in [0,1,2]:check(run.buy(offer(run,family)).is_empty(),"recruit joins available field slot")
	check(run.deployed_count()==3 and run.bench_count()==0,"first three purchases deploy automatically")
	var positions:=run.army.map(func(entry):return entry.point.duplicate())
	check(run.buy(offer(run,3)).is_empty() and run.deployed_count()==3 and run.bench_count()==1,"full field sends next recruit to reserves")
	for index in 3:check(run.army[index].point==positions[index],"existing formation remains fixed")
	var saved:=run.snapshot();run.undo()
	check(run.army.size()==3 and run.bench_count()==0,"one undo removes purchase and placement")
	var restored:=ArenaRun.new();restored.auto_save=false
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))) and restored.bench_count()==1,"automatic placement saves")
	run=fresh();run.buy(offer(run,0));run.buy(offer(run,1))
	for index in run.bench_limit():run._recruit(-1,0,9,ArenaRules.COMPANIONS[0])
	check(run.buy(offer(run,2)).is_empty() and run.deployed_count()==3 and run.bench_count()==8,"full reserves still allow an open field slot")
	var before:=run.snapshot()
	check(not run.buy(offer(run,3)).is_empty() and run.snapshot()==before,"full field and reserves reject purchase atomically")
	run=fresh();run.deployment_check=func(_point):return false
	check(run.buy(offer(run,0)).is_empty() and run.bench_count()==1 and run.deployed_count()==0,"blocked ground sends recruit to reserves")
	run=fresh();var first:=offer(run,0);run.buy(first)
	var uid:=int(run.army[0].uid);var point:Array=run.army[0].point.duplicate()
	for copy in 2:
		run.shop[0]={"family":0,"rank":0,"locked":false};run.buy(0)
	check(run.army.size()==1 and run.unit(uid).rank==1 and run.unit(uid).point==point and run.unit(uid).deployed,"evolution preserves deployed survivor and position")
	run.undo();check(run.army.size()==2 and run.unit(uid).rank==0,"evolution and purchase undo together")
	check(EIAudio.sfx("buttons\\camp\\perk.wav")!=null and EIAudio.sfx("buttons\\camp\\buy.wav")!=null,"level and reroll sounds exist in original archives")
	print("ARENA_FEEDBACK ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
