extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	var r := ArenaRun.new(); r.auto_save = false; r.begin(7319)
	var family:=int(r.shop[0].family)
	var a := r._recruit(family,0,1); var b := r._recruit(int(r.shop[1].family),0,1)
	a.deployed=false; b.deployed=false; r.reserve_slots()
	var aid:=int(a.uid); var bid:=int(b.uid)
	var original:=r.army.duplicate(true); var gold:=r.gold
	check(r.bench(aid,6).is_empty() and int(r.unit(aid).bench_slot)==6,"move reserve into empty slot")
	check(r.reserve_slots()[0].is_empty() and int(r.reserve_slots()[6].uid)==aid,"vacated slot remains empty")
	check(r.bench(aid,1).is_empty() and int(r.unit(bid).bench_slot)==6,"occupied destination swaps both reserves")
	check(r.gold==gold and r.army.size()==2,"reorder spends nothing and loses no creature")
	r.undo();check(int(r.unit(aid).bench_slot)==6 and int(r.unit(bid).bench_slot)==1,"swap is undoable")
	r.undo();check(r.army==original,"move is undoable")
	r.bench(aid,6)
	var copy:=ArenaRun.new();copy.auto_save=false
	check(copy.restore(JSON.parse_string(JSON.stringify(r.snapshot()))) and int(copy.unit(aid).bench_slot)==6 and int(copy.unit(bid).bench_slot)==1,"slot order survives JSON save/load")
	r.undo()
	for i in 6:
		var u:=r._recruit(family,0,1);u.deployed=false
	r.reserve_slots()
	check(r.bench_count()==r.bench_limit(),"full bench fixture")
	check(r.bench(aid,7).is_empty() and int(r.unit(aid).bench_slot)==7,"full bench can swap")
	var before:=r.snapshot()
	for slot in [-2,8,1000]:check(not r.bench(aid,slot).is_empty() and r.snapshot()==before,"invalid slot rejected without mutation")
	check(not r.bench(999999,0).is_empty() and r.snapshot()==before,"foreign or stale unit rejected")
	check(r.bench(aid,7).is_empty() and r.snapshot()==before,"same slot is a no-op")
	for stage in ["fight","result"]:
		r.stage=stage
		check(r.bench(aid,2).is_empty() and int(r.unit(aid).bench_slot)==2,"reserve can move during "+stage)
		check(r.bench(aid,7).is_empty(),"reserve can swap during "+stage)
		r.unit(bid).deployed=true
		check(not r.bench(bid,0).is_empty() and r.unit(bid).deployed,"field creature cannot withdraw during "+stage)
		r.unit(bid).deployed=false
	r.stage="prepare";r.preparing_battle=true;before=r.snapshot()
	check(not r.bench(aid,0).is_empty() and r.snapshot()==before,"staging lock rejects reserve moves")
	r.preparing_battle=false;r.stage="defeat";before=r.snapshot()
	check(not r.bench(aid,0).is_empty() and r.snapshot()==before,"finished run rejects moves")
	print("ARENA_RESERVE_MOVES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
